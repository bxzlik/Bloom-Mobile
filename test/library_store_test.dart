/// Библиотека: лайки, плейлисты и то, что всё это переживает
/// перезапуск. Хранилище — в памяти, файловая система не нужна.
library;

import 'package:bloom/core/db/track_store.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

Track _track(String id, {String name = 'Song'}) => Track(
  id: id,
  name: name,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  sourceData: const {'transcodings': []},
);

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('лайк кладёт трек в библиотеку целиком, снятие его не выбрасывает', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final track = _track('sc:1');

    expect(c.read(libraryProvider).isFav('sc:1'), isFalse);
    lib.toggleFav(track);

    expect(c.read(libraryProvider).isFav('sc:1'), isTrue);
    // Без самого трека в «Любимом» остался бы голый id — ни показать, ни
    // заиграть.
    expect(c.read(libraryProvider).favTracks.single.name, 'Song');

    lib.toggleFav(track);
    expect(c.read(libraryProvider).isFav('sc:1'), isFalse);
    // Трек остаётся в библиотеке: он мог попасть туда и из плейлиста.
    expect(c.read(libraryProvider).tracks.containsKey('sc:1'), isTrue);
  });

  test('любимые отсортированы свежими вверх', () async {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'Первый'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    lib.toggleFav(_track('sc:2', name: 'Второй'));

    expect(c.read(libraryProvider).favTracks.map((t) => t.name).toList(), [
      'Второй',
      'Первый',
    ]);
  });

  test(
    'в библиотеку добавляют явно, свежие сверху, дубли не двигают порядок',
    () {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);

      expect(lib.addToLibrary([_track('sc:1', name: 'A')]), 1);
      expect(lib.addToLibrary([_track('sc:2', name: 'B')]), 1);
      expect(lib.addToLibrary([_track('sc:1', name: 'A')]), 0);

      expect(c.read(libraryProvider).allTracks.map((t) => t.name).toList(), [
        'B',
        'A',
      ]);
    },
  );

  test('удаление трека вычищает его отовсюду', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final track = _track('sc:1');
    lib.toggleFav(track); // лайк заодно кладёт в библиотеку
    final pl = lib.createPlaylist('Мой', tracks: [track, _track('sc:2')]);

    lib.deleteTrack('sc:1');

    final after = c.read(libraryProvider);
    expect(after.isInLib('sc:1'), isFalse);
    expect(after.isFav('sc:1'), isFalse);
    // «История» трек в хранилище не держит — её строка живёт на снимке журнала
    // (см. `play_stats_test.dart`).
    expect(after.tracks.containsKey('sc:1'), isFalse);
    // Висячий id в плейлисте показывал бы счётчик без строки.
    expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
      'sc:2',
    ]);
  });

  test('трек без истории удаление выносит и из хранилища', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.addToLibrary([_track('sc:1')]);

    lib.deleteTrack('sc:1');

    expect(c.read(libraryProvider).tracks.containsKey('sc:1'), isFalse);
  });

  test('смена площадки переставляет все ссылки на новый id', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final old = _track('sc:1', name: 'Ночь');
    lib.toggleFav(old);
    final pl = lib.createPlaylist('Мой', tracks: [_track('sc:9'), old]);
    final addedAt = c.read(libraryProvider).inLib['sc:1'];

    lib.replaceTrack(
      'sc:1',
      Track(
        id: 'ytm:1',
        name: 'Ночь',
        artist: 'Artist',
        duration: const Duration(seconds: 100),
        source: MusicSource.ytmusic,
      ),
    );

    final after = c.read(libraryProvider);
    expect(after.tracks.containsKey('sc:1'), isFalse);
    expect(after.isInLib('ytm:1'), isTrue);
    expect(after.isFav('ytm:1'), isTrue);
    // Место в плейлисте не меняется: сменилась площадка, а не порядок.
    expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
      'sc:9',
      'ytm:1',
    ]);
    // И время добавления тоже: иначе трек прыгнул бы в начало «Всех треков».
    expect(after.inLib['ytm:1'], addedAt);
  });

  test('замена на тот же id ничего не трогает', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'Ночь'));

    lib.replaceTrack('sc:1', _track('sc:1', name: 'Переписанное'));

    expect(c.read(libraryProvider).tracks['sc:1']?.name, 'Ночь');
  });

  test('перетаскивание лайков не трогает время лайка', () async {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'Первый'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    lib.toggleFav(_track('sc:2', name: 'Второй'));
    final at = Map.of(c.read(libraryProvider).favs);

    lib.setFavTracks(['sc:1', 'sc:2']);

    expect(c.read(libraryProvider).favTracks.map((t) => t.name), [
      'Первый',
      'Второй',
    ]);
    // «Свежие лайки» для волны и «Для вас» по-прежнему знают, когда их ставили.
    expect(c.read(libraryProvider).favs, at);
  });

  test('трек, исправленный руками на ПК, площадка не переписывает', () {
    final c = _container(JsonStore.memory());
    final db = c.read(dbProvider);
    c.read(libraryProvider.notifier).addToLibrary([_track('sc:1', name: 'A')]);
    db.exec(
      "UPDATE tracks SET title = 'Своё', extra = json_set(extra, '\$.edited', json('true')) WHERE id = 'sc:1'",
    );

    c.read(libraryProvider.notifier).addToLibrary([
      _track('sc:1', name: 'С площадки'),
    ]);
    TrackStore(db).put([_track('sc:1', name: 'С площадки')]);

    expect(TrackStore(db).getOne('sc:1')?.name, 'Своё');
  });

  test('формат трека — как на ПК, туда и обратно без потерь', () {
    final t = Track(
      id: 'sc:5',
      name: 'Песня',
      artist: 'Nick',
      duration: const Duration(milliseconds: 185500),
      source: MusicSource.soundcloud,
      url: 'https://soundcloud.com/nick/song',
      artistId: 'sc:artist:9',
      year: '2024',
      genres: const ['house'],
      sourceData: const {'transcodings': []},
    );
    final m = t.toJson();
    expect(m['title'], 'Песня');
    expect(m['duration'], 185.5);
    expect(m['provider'], 'sc');
    expect((m['extra'] as Map)['scId'], 5);
    expect((m['extra'] as Map)['artistId'], 9);

    final back = Track.fromJson(m)!;
    expect(back.artistId, 'sc:artist:9');
    expect(back.url, t.url);
    expect(back.duration, t.duration);
    expect(back.sourceData, t.sourceData);
  });

  test('плейлист: новый трек наверх, дубли игнорируются', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Мой');

    lib.addTrackToPlaylist(pl.id, _track('sc:1', name: 'A'));
    lib.addTrackToPlaylist(pl.id, _track('sc:2', name: 'B'));
    lib.addTrackToPlaylist(pl.id, _track('sc:1', name: 'A'));

    final saved = c.read(libraryProvider).playlists.single;
    expect(saved.trackIds, ['sc:2', 'sc:1']);
    expect(
      c.read(libraryProvider).tracksOf(saved).map((t) => t.name).toList(),
      ['B', 'A'],
    );
  });

  test('правка плейлиста: новый состав и порядок разом', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist(
      'Мой',
      tracks: [
        _track('sc:1', name: 'A'),
        _track('sc:2', name: 'B'),
        _track('sc:3', name: 'C'),
      ],
    );

    lib.setPlaylistTracks(pl.id, ['sc:3', 'sc:1']);

    final saved = c.read(libraryProvider).playlists.single;
    expect(saved.trackIds, ['sc:3', 'sc:1']);
    // Выпавший из плейлиста трек остаётся в библиотеке — из «Всех треков» его
    // никто не выкидывал.
    expect(c.read(libraryProvider).isInLib('sc:2'), isTrue);
  });

  test('правка «Всех треков»: порядок сохраняется, убранное уходит насквозь', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final gone = _track('sc:2', name: 'B');
    lib.toggleFav(gone);
    final pl = lib.createPlaylist(
      'Мой',
      tracks: [
        _track('sc:1', name: 'A'),
        gone,
        _track('sc:3', name: 'C'),
      ],
    );

    lib.setLibraryTracks(['sc:3', 'sc:1']);

    final after = c.read(libraryProvider);
    expect(after.allTracks.map((t) => t.name).toList(), ['C', 'A']);
    // Убранный из библиотеки не должен остаться ни лайком, ни строкой плейлиста.
    expect(after.isFav('sc:2'), isFalse);
    expect(after.tracks.containsKey('sc:2'), isFalse);
    expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
      'sc:1',
      'sc:3',
    ]);
  });

  test('правка «Любимых»: снятый лайк не выкидывает трек из библиотеки', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'A'));
    lib.toggleFav(_track('sc:2', name: 'B'));

    lib.setFavTracks(['sc:2']);

    final after = c.read(libraryProvider);
    expect(after.favTracks.map((t) => t.name).toList(), ['B']);
    expect(after.isInLib('sc:1'), isTrue);
  });

  test('пачка в плейлист: порядок внутри сохраняется, дубли пропускаются', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Мой', tracks: [_track('sc:1', name: 'A')]);

    lib.addTracksToPlaylist(pl.id, [
      _track('sc:2', name: 'B'),
      _track('sc:1', name: 'A'),
      _track('sc:3', name: 'C'),
    ]);

    expect(c.read(libraryProvider).playlists.single.trackIds, [
      'sc:2',
      'sc:3',
      'sc:1',
    ]);
  });

  test('пустое имя плейлиста не создаёт безымянный', () {
    final c = _container(JsonStore.memory());
    final pl = c.read(libraryProvider.notifier).createPlaylist('   ');
    // Без дерева виджетов языку интерфейса взяться неоткуда, и `globalL10n`
    // отдаёт null — createPlaylist падает на английский запасной вариант.
    expect(pl.name, 'New playlist');
  });

  test('всё переживает перезапуск', () {
    final store = JsonStore.memory();
    final first = _container(store);
    final lib = first.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'Любимая'));
    final pl = lib.createPlaylist('Импорт');
    lib.addTrackToPlaylist(pl.id, _track('sc:2', name: 'Вторая'));
    lib.toggleFollow(
      const Artist(
        id: 'sc:artist:9',
        name: 'Nick',
        source: MusicSource.soundcloud,
      ),
    );

    // Новый контейнер поверх того же хранилища = перезапуск приложения.
    final second = _container(store);
    final restored = second.read(libraryProvider);

    expect(restored.isFav('sc:1'), isTrue);
    expect(restored.favTracks.single.name, 'Любимая');
    expect(restored.playlists.single.name, 'Импорт');
    expect(restored.tracksOf(restored.playlists.single).single.name, 'Вторая');
    expect(restored.isFollowing('sc:artist:9'), isTrue);
    // sourceData обязан пережить сериализацию, иначе трек не заиграет.
    expect(restored.tracks['sc:2']?.sourceData, isNotNull);
  });
}
