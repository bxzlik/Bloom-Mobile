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

  test('пустое имя плейлиста не создаёт безымянный', () {
    final c = _container(JsonStore.memory());
    final pl = c.read(libraryProvider.notifier).createPlaylist('   ');
    expect(pl.name, 'Новый плейлист');
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
