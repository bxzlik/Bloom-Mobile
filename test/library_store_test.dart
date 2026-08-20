/// Библиотека: лайки, история, плейлисты и то, что всё это переживает
/// перезапуск. Хранилище — в памяти, файловая система не нужна.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('лайк кладёт трек в библиотеку целиком, снятие его не выбрасывает', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final track = _track('sc_1');

    expect(c.read(libraryProvider).isFav('sc_1'), isFalse);
    lib.toggleFav(track);

    expect(c.read(libraryProvider).isFav('sc_1'), isTrue);
    // Без самого трека в «Любимом» остался бы голый id — ни показать, ни
    // заиграть.
    expect(c.read(libraryProvider).favTracks.single.name, 'Song');

    lib.toggleFav(track);
    expect(c.read(libraryProvider).isFav('sc_1'), isFalse);
    // Трек остаётся в библиотеке: он мог попасть туда и из плейлиста.
    expect(c.read(libraryProvider).tracks.containsKey('sc_1'), isTrue);
  });

  test('любимые отсортированы свежими вверх', () async {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc_1', name: 'Первый'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    lib.toggleFav(_track('sc_2', name: 'Второй'));

    expect(c.read(libraryProvider).favTracks.map((t) => t.name).toList(), [
      'Второй',
      'Первый',
    ]);
  });

  test('прослушивание не кладёт трек в «Все треки»', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.pushHistory(_track('sc_1'));

    // В истории есть, в библиотеке — нет: на десктопе так же.
    expect(c.read(libraryProvider).historyTracks.single.id, 'sc_1');
    expect(c.read(libraryProvider).isInLib('sc_1'), isFalse);
    expect(c.read(libraryProvider).allTracks, isEmpty);
  });

  test('прослушанное уходит из хранилища вместе с историей', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.pushHistory(_track('sc_1'));
    lib.pushHistory(_track('sc_2'));
    lib.toggleFav(_track('sc_2'));
    lib.clearHistory();

    // sc_1 больше никому не нужен, sc_2 держит лайк.
    expect(c.read(libraryProvider).tracks.keys, ['sc_2']);
  });

  test(
    'в библиотеку добавляют явно, свежие сверху, дубли не двигают порядок',
    () {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);

      expect(lib.addToLibrary([_track('sc_1', name: 'A')]), 1);
      expect(lib.addToLibrary([_track('sc_2', name: 'B')]), 1);
      expect(lib.addToLibrary([_track('sc_1', name: 'A')]), 0);

      expect(c.read(libraryProvider).allTracks.map((t) => t.name).toList(), [
        'B',
        'A',
      ]);
    },
  );

  test('удаление трека вычищает его отовсюду', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final track = _track('sc_1');
    lib.toggleFav(track); // лайк заодно кладёт в библиотеку
    lib.pushHistory(track);
    final pl = lib.createPlaylist('Мой', tracks: [track, _track('sc_2')]);

    lib.deleteTrack('sc_1');

    final after = c.read(libraryProvider);
    expect(after.isInLib('sc_1'), isFalse);
    expect(after.isFav('sc_1'), isFalse);
    expect(after.historyTracks, isEmpty);
    expect(after.tracks.containsKey('sc_1'), isFalse);
    // Висячий id в плейлисте показывал бы счётчик без строки.
    expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
      'sc_2',
    ]);
  });

  test('смена площадки переставляет все ссылки на новый id', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final old = _track('sc_1', name: 'Ночь');
    lib.toggleFav(old);
    lib.pushHistory(old);
    final pl = lib.createPlaylist('Мой', tracks: [_track('sc_9'), old]);
    final addedAt = c.read(libraryProvider).inLib['sc_1'];

    lib.replaceTrack(
      'sc_1',
      Track(
        id: 'ytm_1',
        name: 'Ночь',
        artist: 'Artist',
        duration: const Duration(seconds: 100),
        source: MusicSource.ytmusic,
      ),
    );

    final after = c.read(libraryProvider);
    expect(after.tracks.containsKey('sc_1'), isFalse);
    expect(after.isInLib('ytm_1'), isTrue);
    expect(after.isFav('ytm_1'), isTrue);
    expect(after.historyTracks.single.id, 'ytm_1');
    // Место в плейлисте не меняется: сменилась площадка, а не порядок.
    expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
      'sc_9',
      'ytm_1',
    ]);
    // И время добавления тоже: иначе трек прыгнул бы в начало «Всех треков».
    expect(after.inLib['ytm_1'], addedAt);
  });

  test('замена на тот же id ничего не трогает', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc_1', name: 'Ночь'));

    lib.replaceTrack('sc_1', _track('sc_1', name: 'Переписанное'));

    expect(c.read(libraryProvider).tracks['sc_1']?.name, 'Ночь');
  });

  test('старое хранилище без набора библиотеки: в ней остаётся всё', () {
    // Файл, записанный до разделения хранилища и «Всех треков».
    final store = JsonStore.memory({
      'tracks': [_track('sc_1', name: 'A').toJson(), _track('sc_2').toJson()],
    });
    final restored = _container(store).read(libraryProvider);

    expect(restored.allTracks.length, 2);
    expect(restored.allTracks.first.id, 'sc_2'); // свежий сверху
  });

  test('история без дублей: повтор поднимает трек наверх', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.pushHistory(_track('sc_1', name: 'A'));
    lib.pushHistory(_track('sc_2', name: 'B'));
    lib.pushHistory(_track('sc_1', name: 'A'));

    final history = c.read(libraryProvider).historyTracks;
    expect(history.map((t) => t.name).toList(), ['A', 'B']);
  });

  test('история обрезается по лимиту', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    for (var i = 0; i < kHistoryLimit + 20; i++) {
      lib.pushHistory(_track('sc_$i'));
    }
    expect(c.read(libraryProvider).history.length, kHistoryLimit);
  });

  test('плейлист: новый трек наверх, дубли игнорируются', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Мой');

    lib.addTrackToPlaylist(pl.id, _track('sc_1', name: 'A'));
    lib.addTrackToPlaylist(pl.id, _track('sc_2', name: 'B'));
    lib.addTrackToPlaylist(pl.id, _track('sc_1', name: 'A'));

    final saved = c.read(libraryProvider).playlists.single;
    expect(saved.trackIds, ['sc_2', 'sc_1']);
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
        _track('sc_1', name: 'A'),
        _track('sc_2', name: 'B'),
        _track('sc_3', name: 'C'),
      ],
    );

    lib.setPlaylistTracks(pl.id, ['sc_3', 'sc_1']);

    final saved = c.read(libraryProvider).playlists.single;
    expect(saved.trackIds, ['sc_3', 'sc_1']);
    // Выпавший из плейлиста трек остаётся в библиотеке — из «Всех треков» его
    // никто не выкидывал.
    expect(c.read(libraryProvider).isInLib('sc_2'), isTrue);
  });

  test('правка «Всех треков»: порядок сохраняется, убранное уходит насквозь', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final gone = _track('sc_2', name: 'B');
    lib.toggleFav(gone);
    lib.pushHistory(gone);
    final pl = lib.createPlaylist(
      'Мой',
      tracks: [
        _track('sc_1', name: 'A'),
        gone,
        _track('sc_3', name: 'C'),
      ],
    );

    lib.setLibraryTracks(['sc_3', 'sc_1']);

    final after = c.read(libraryProvider);
    expect(after.allTracks.map((t) => t.name).toList(), ['C', 'A']);
    // Убранный из библиотеки не должен остаться ни лайком, ни строкой плейлиста.
    expect(after.isFav('sc_2'), isFalse);
    expect(after.historyTracks, isEmpty);
    expect(after.tracks.containsKey('sc_2'), isFalse);
    expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
      'sc_1',
      'sc_3',
    ]);
  });

  test('правка «Любимых»: снятый лайк не выкидывает трек из библиотеки', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc_1', name: 'A'));
    lib.toggleFav(_track('sc_2', name: 'B'));

    lib.setFavTracks(['sc_2']);

    final after = c.read(libraryProvider);
    expect(after.favTracks.map((t) => t.name).toList(), ['B']);
    expect(after.isInLib('sc_1'), isTrue);
  });

  test('правка «Истории»: время прослушивания уцелевших не переписывается', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.pushHistory(_track('sc_1', name: 'A'));
    lib.pushHistory(_track('sc_2', name: 'B'));
    final wasAt = c
        .read(libraryProvider)
        .history
        .singleWhere((h) => h.trackId == 'sc_1')
        .at;

    lib.setHistoryTracks(['sc_1']);

    final after = c.read(libraryProvider).history;
    expect(after.map((h) => h.trackId).toList(), ['sc_1']);
    expect(after.single.at, wasAt);
  });

  test('пачка в плейлист: порядок внутри сохраняется, дубли пропускаются', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Мой', tracks: [_track('sc_1', name: 'A')]);

    lib.addTracksToPlaylist(pl.id, [
      _track('sc_2', name: 'B'),
      _track('sc_1', name: 'A'),
      _track('sc_3', name: 'C'),
    ]);

    expect(c.read(libraryProvider).playlists.single.trackIds, [
      'sc_2',
      'sc_3',
      'sc_1',
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
    lib.toggleFav(_track('sc_1', name: 'Любимая'));
    final pl = lib.createPlaylist('Импорт');
    lib.addTrackToPlaylist(pl.id, _track('sc_2', name: 'Вторая'));
    lib.toggleFollow(
      const Artist(
        id: 'sc_artist_9',
        name: 'Nick',
        source: MusicSource.soundcloud,
      ),
    );

    // Новый контейнер поверх того же хранилища = перезапуск приложения.
    final second = _container(store);
    final restored = second.read(libraryProvider);

    expect(restored.isFav('sc_1'), isTrue);
    expect(restored.favTracks.single.name, 'Любимая');
    expect(restored.playlists.single.name, 'Импорт');
    expect(restored.tracksOf(restored.playlists.single).single.name, 'Вторая');
    expect(restored.isFollowing('sc_artist_9'), isTrue);
    // sourceData обязан пережить сериализацию, иначе трек не заиграет.
    expect(restored.tracks['sc_2']?.sourceData, isNotNull);
  });
}
