/// Свои треки: разбор ответа нативной стороны и всё, что вокруг него ломается
/// тихо.
///
/// Проверяем ровно то, что не видно на глаз: id обязан быть стабильным (иначе
/// повторное добавление того же файла даёт второй трек и дедуп не работает),
/// теги обязаны честно уступать имени файла, а удаление — знать, за какими
/// треками стоит наш файл, и не трогать чужие.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/library/local_tracks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ответ канала: минимум полей, остальное дописывают тесты.
Map<String, Object?> _entry({
  String key = 'content://audio/1',
  String name = 'song.mp3',
  Object? title,
  Object? artist,
  Object? album,
  Object? year,
  Object? genre,
  Object? cover,
  int durationMs = 180000,
  int size = 4096,
  String? uri = 'content://audio/1',
  String? file,
}) => {
  'key': key,
  'name': name,
  'size': size,
  'title': title,
  'artist': artist,
  'album': album,
  'year': year,
  'genre': genre,
  'cover': cover,
  'durationMs': durationMs,
  'uri': ?uri,
  'file': ?file,
};

Track _track(Map<String, Object?> entry) {
  final track = localTrackFromEntry(entry, unknownArtist: 'Неизвестный');
  expect(track, isNotNull);
  return track!;
}

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(JsonStore.memory())],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('разбор записи', () {
    test('теги важнее имени файла', () {
      final track = _track(
        _entry(
          name: 'Кто-то - Что-то.mp3',
          title: 'Настоящее название',
          artist: 'Настоящий артист',
          album: 'Альбом',
          year: '2019-04-05',
          genre: 'Rock;Indie',
        ),
      );
      expect(track.name, 'Настоящее название');
      expect(track.artist, 'Настоящий артист');
      expect(track.album, 'Альбом');
      // Из полной даты берём год, как lofty-часть на ПК.
      expect(track.year, '2019');
      expect(track.genres, ['Rock', 'Indie']);
      expect(track.duration, const Duration(minutes: 3));
      expect(track.source, MusicSource.local);
    });

    test('без тегов имя файла режется на «Артист - Название»', () {
      final track = _track(_entry(name: 'Аквариум - Город золотой.flac'));
      expect(track.artist, 'Аквариум');
      expect(track.name, 'Город золотой');
    });

    test('нет ни тегов, ни дефиса — артист «Неизвестный»', () {
      final track = _track(_entry(name: 'record 7.wav'));
      expect(track.artist, 'Неизвестный');
      expect(track.name, 'record 7');
    });

    test('пустые теги считаются отсутствующими', () {
      final track = _track(
        _entry(name: 'A - B.mp3', title: '  ', artist: '', album: ''),
      );
      expect(track.name, 'B');
      expect(track.artist, 'A');
      expect(track.album, isNull);
    });

    test('обложка приезжает именем файла и становится своей картинкой', () {
      final track = _track(_entry(cover: 'lt_1.jpg'));
      expect(track.cover, 'local:lt_1.jpg');
    });

    test('без ключа записи нет', () {
      expect(
        localTrackFromEntry({'name': 'x.mp3'}, unknownArtist: '—'),
        isNull,
      );
      expect(localTrackFromEntry('мусор', unknownArtist: '—'), isNull);
    });
  });

  group('id и дедуп', () {
    test('id стабилен по ключу и не зависит от тегов', () {
      final first = _track(_entry(title: 'Раз'));
      final second = _track(_entry(title: 'Два'));
      expect(first.id, second.id);
      expect(first.id, startsWith('lf'));
      // Префикса площадки нет — трек считается своим.
      expect(MusicSource.fromId(first.id), MusicSource.local);
    });

    test('разные файлы — разные id', () {
      final a = _track(_entry(key: 'a.mp3|100', uri: null, file: 'a.mp3'));
      final b = _track(_entry(key: 'b.mp3|100', uri: null, file: 'b.mp3'));
      expect(a.id, isNot(b.id));
    });

    test('повторное добавление того же файла библиотеку не растит', () {
      final c = _container();
      final lib = c.read(libraryProvider.notifier);
      expect(lib.addToLibrary([_track(_entry())]), 1);
      expect(lib.addToLibrary([_track(_entry(title: 'Переименовали'))]), 0);
      expect(c.read(libraryProvider).allTracks.length, 1);
    });

    test('ключи для нативной стороны — только у своих треков', () {
      final c = _container();
      c.read(libraryProvider.notifier).addToLibrary([
        _track(_entry()),
        const Track(
          id: 'sc_1',
          name: 'Сетевой',
          artist: 'X',
          duration: Duration(minutes: 2),
          source: MusicSource.soundcloud,
        ),
      ]);
      expect(knownLocalKeys(c.read(libraryProvider)), ['content://audio/1']);
    });
  });

  group('хранение', () {
    test('трек переживает запись в файл библиотеки', () {
      final store = JsonStore.memory();
      final c = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c.read(libraryProvider.notifier).addToLibrary([
        _track(_entry(uri: null, file: 'song.mp3')),
      ]);

      final reopened = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWithValue(store)],
      );
      addTearDown(reopened.dispose);
      final track = reopened.read(libraryProvider).allTracks.single;
      // Без `sourceData` трек остался бы строкой, которую нечем заиграть.
      expect(isLocalTrack(track), isTrue);
      expect(track.sourceData?['file'], 'song.mp3');
      expect(localTrackKey(track), 'content://audio/1');
    });

    test('свои треки среди удаляемых id находятся, чужие — нет', () {
      final c = _container();
      final own = _track(_entry(uri: null, file: 'song.mp3'));
      const foreign = Track(
        id: 'ym_9',
        name: 'Сетевой',
        artist: 'X',
        duration: Duration(minutes: 2),
        source: MusicSource.yandex,
      );
      c.read(libraryProvider.notifier).addToLibrary([own, foreign]);

      final found = localTracksOf(c.read(libraryProvider), [
        own.id,
        foreign.id,
        'нет такого',
      ]);
      expect(found.map((t) => t.id), [own.id]);
    });
  });

  group('настройка режима', () {
    test('по умолчанию — «на месте», как на ПК', () {
      expect(
        _container().read(settingsProvider).localImport,
        LocalImportMode.inPlace,
      );
    });

    test('выбор переживает перезапуск', () {
      final store = JsonStore.memory();
      final c = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c.read(settingsProvider.notifier).setLocalImport(LocalImportMode.copy);

      final reopened = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWithValue(store)],
      );
      addTearDown(reopened.dispose);
      expect(reopened.read(settingsProvider).localImport, LocalImportMode.copy);
    });

    test('незнакомый режим из чужой сборки не роняет настройки', () {
      expect(readLocalImportMode('вообще не режим'), LocalImportMode.inPlace);
      expect(readLocalImportMode(null), LocalImportMode.inPlace);
      expect(readLocalImportMode('copy'), LocalImportMode.copy);
    });
  });
}
