/// Авто-обновление плейлистов: кого обходим, что считаем «добавилось» и что
/// остаётся от плейлиста, когда площадка не ответила.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/library/pl_auto_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  sourceData: const {'transcodings': []},
);

/// Площадка, у которой по ссылке лежит плейлист с заданным составом.
class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud(this.byUrl);

  /// Ссылка → треки. `null` вместо списка — площадка падает.
  final Map<String, List<Track>?> byUrl;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  /// id сета делаем равным ссылке — так `getPlaylist` находит его состав.
  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    if (!byUrl.containsKey(url)) return null;
    if (byUrl[url] == null) throw StateError('нет сети');
    return ResolvedSet(
      Playlist(id: url, title: 'Сет', source: MusicSource.soundcloud),
    );
  }

  @override
  Future<SetContent?> getPlaylist(String id) async => SetContent(
    playlist: Playlist(id: id, title: 'Сет', source: MusicSource.soundcloud),
    tracks: byUrl[id] ?? const [],
  );
}

ProviderContainer _container(_FakeSoundCloud provider, JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      registryProvider.overrideWithValue(
        ProviderRegistry()..register(provider),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  // Проход ищет мессенджер приложения, чтобы сказать о новых треках, — а тот
  // живёт в дереве виджетов, и без биндинга поиск падает.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('кандидаты — только плейлисты с источником', () {
    final c = _container(_FakeSoundCloud(const {}), JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.createPlaylist('Свой');
    lib.createPlaylist('Импортированный', sourceUrl: 'https://sc/one');

    final names = c
        .read(plAutoProvider.notifier)
        .candidates()
        .map((p) => p.name)
        .toList();
    expect(names, ['Импортированный']);
  });

  test('проход обновляет только отмеченные и считает новые треки', () async {
    final sc = _FakeSoundCloud({
      'https://sc/one': [_track('sc_1'), _track('sc_2')],
      'https://sc/two': [_track('sc_9')],
    });
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final one = lib.createPlaylist(
      'Первый',
      tracks: [_track('sc_1')],
      sourceUrl: 'https://sc/one',
    );
    final two = lib.createPlaylist('Второй', sourceUrl: 'https://sc/two');

    final auto = c.read(plAutoProvider.notifier);
    auto.setIds([one.id]);
    final result = await auto.runSweep(silent: true);

    // В первом прибавился один трек, второй не отмечен — его не трогали.
    expect(result.added, 1);
    expect(result.changed, 1);
    expect(result.failed, 0);
    final playlists = c.read(libraryProvider).playlists;
    expect(playlists.firstWhere((p) => p.id == one.id).trackIds, [
      'sc_1',
      'sc_2',
    ]);
    expect(playlists.firstWhere((p) => p.id == two.id).trackIds, isEmpty);

    // Итог прохода запомнен — из него собирается подпись в шторке.
    final state = c.read(plAutoProvider);
    expect(state.runs[one.id]?.added, 1);
    expect(state.lastRun, greaterThan(0));
    expect(state.busy, isNull);
  });

  test('упавший источник не стирает состав плейлиста', () async {
    final sc = _FakeSoundCloud({'https://sc/one': null});
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist(
      'Первый',
      tracks: [_track('sc_1')],
      sourceUrl: 'https://sc/one',
    );

    final auto = c.read(plAutoProvider.notifier);
    auto.setIds([pl.id]);
    final result = await auto.runSweep(silent: true);

    expect(result.failed, 1);
    expect(c.read(libraryProvider).playlists.single.trackIds, ['sc_1']);
    expect(c.read(plAutoProvider).runs[pl.id]?.failed, isTrue);
  });

  test('без отмеченных плейлистов проход не запускается', () async {
    final c = _container(_FakeSoundCloud(const {}), JsonStore.memory());
    c.read(libraryProvider.notifier).createPlaylist(
      'Импортированный',
      sourceUrl: 'https://sc/one',
    );

    final result = await c.read(plAutoProvider.notifier).runSweep(silent: true);
    expect(result.skipped, isTrue);
    expect(c.read(plAutoProvider).lastRun, 0);
  });

  test('настройки расписания переживают перезапуск', () {
    final store = JsonStore.memory();
    final first = _container(_FakeSoundCloud(const {}), store);
    first.read(plAutoProvider.notifier)
      ..setEnabled(true)
      ..setEveryMin(720)
      ..setOnStart(false)
      ..setIds(['pl_1']);

    final second = _container(_FakeSoundCloud(const {}), store);
    final state = second.read(plAutoProvider);
    expect(state.enabled, isTrue);
    expect(state.everyMin, 720);
    expect(state.onStart, isFalse);
    expect(state.ids, ['pl_1']);
  });
}
