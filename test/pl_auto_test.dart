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
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  sourceData: const {'transcodings': []},
);

/// Площадка, у которой по id коллекции лежит плейлист с заданным составом.
class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud(this.byId);

  /// id коллекции → треки. `null` вместо списка — площадка падает.
  final Map<String, List<Track>?> byId;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<SetContent?> getPlaylist(String id) async {
    if (byId.containsKey(id) && byId[id] == null) throw StateError('нет сети');
    return SetContent(
      playlist: Playlist(id: id, title: 'Сет', source: MusicSource.soundcloud),
      tracks: byId[id] ?? const [],
    );
  }
}

/// Привязка SC-плейлиста — обновление ищет его по id.
PlSourceRef _src(String id) => PlSourceRef(id: id, provider: 'sc');

ProviderContainer _container(_FakeSoundCloud provider, JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
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
    lib.createPlaylist('Импортированный', source: _src('sc:set:1'));

    final names = c
        .read(plAutoProvider.notifier)
        .candidates()
        .map((p) => p.name)
        .toList();
    expect(names, ['Импортированный']);
  });

  test('проход обновляет только отмеченные и считает новые треки', () async {
    final sc = _FakeSoundCloud({
      'sc:set:1': [_track('sc:1'), _track('sc:2')],
      'sc:set:2': [_track('sc:9')],
    });
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final one = lib.createPlaylist(
      'Первый',
      tracks: [_track('sc:1')],
      source: _src('sc:set:1'),
    );
    final two = lib.createPlaylist('Второй', source: _src('sc:set:2'));

    final auto = c.read(plAutoProvider.notifier);
    lib.setAutoRefresh([one.id], true);
    final result = await auto.runSweep(silent: true);

    // В первом прибавился один трек, второй не отмечен — его не трогали.
    expect(result.added, 1);
    expect(result.changed, 1);
    expect(result.failed, 0);
    final playlists = c.read(libraryProvider).playlists;
    // Новый трек лёг НАВЕРХ, старый остался на месте: обновление подмешивает, а
    // не заменяет состав.
    expect(playlists.firstWhere((p) => p.id == one.id).trackIds, [
      'sc:2',
      'sc:1',
    ]);
    expect(playlists.firstWhere((p) => p.id == two.id).trackIds, isEmpty);

    // Итог прохода запомнен — из него собирается подпись в шторке.
    final state = c.read(plAutoProvider);
    expect(state.runs[one.id]?.added, 1);
    expect(state.lastRun, greaterThan(0));
    expect(state.busy, isNull);
  });

  test(
    'несколько источников: новое сверху, добавленное руками на месте',
    () async {
      final sc = _FakeSoundCloud({
        'sc:set:1': [_track('sc:1')],
        'sc:set:2': [_track('sc:9')],
      });
      final c = _container(sc, JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      final pl = lib.createPlaylist(
        'Свой',
        tracks: [_track('sc:7')],
        source: _src('sc:set:1'),
      );
      lib.setPlaylistSources(pl.id, [_src('sc:set:1'), _src('sc:set:2')]);

      final auto = c.read(plAutoProvider.notifier);
      lib.setAutoRefresh([pl.id], true);
      final result = await auto.runSweep(silent: true);

      expect(result.added, 2);
      expect(c.read(libraryProvider).playlists.single.trackIds, [
        'sc:1',
        'sc:9',
        'sc:7',
      ]);
    },
  );

  test('один упавший источник не отменяет остальные', () async {
    final sc = _FakeSoundCloud({
      'sc:set:1': null,
      'sc:set:2': [_track('sc:9')],
    });
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Свой', tracks: [_track('sc:7')]);
    lib.setPlaylistSources(pl.id, [_src('sc:set:1'), _src('sc:set:2')]);

    final auto = c.read(plAutoProvider.notifier);
    lib.setAutoRefresh([pl.id], true);
    final result = await auto.runSweep(silent: true);

    // Частичный успех — это успех: недоступную коллекцию могли удалить.
    expect(result.added, 1);
    expect(result.failed, 0);
    expect(c.read(libraryProvider).playlists.single.trackIds, ['sc:9', 'sc:7']);
  });

  test('упавший источник не стирает состав плейлиста', () async {
    final sc = _FakeSoundCloud({'sc:set:1': null});
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist(
      'Первый',
      tracks: [_track('sc:1')],
      source: _src('sc:set:1'),
    );

    final auto = c.read(plAutoProvider.notifier);
    lib.setAutoRefresh([pl.id], true);
    final result = await auto.runSweep(silent: true);

    expect(result.failed, 1);
    expect(c.read(libraryProvider).playlists.single.trackIds, ['sc:1']);
    expect(c.read(plAutoProvider).runs[pl.id]?.failed, isTrue);
  });

  test('без отмеченных плейлистов проход не запускается', () async {
    final c = _container(_FakeSoundCloud(const {}), JsonStore.memory());
    c
        .read(libraryProvider.notifier)
        .createPlaylist('Импортированный', source: _src('sc:set:1'));

    final result = await c.read(plAutoProvider.notifier).runSweep(silent: true);
    expect(result.skipped, isTrue);
    expect(c.read(plAutoProvider).lastRun, 0);
  });

  test('расписание, отметки и итоги переживают перезапуск', () async {
    final store = JsonStore.memory();
    final first = _container(
      _FakeSoundCloud({
        'sc:set:1': [_track('sc:1')],
      }),
      store,
    );
    final lib = first.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Первый', source: _src('sc:set:1'));
    lib.setAutoRefresh([pl.id], true);
    first.read(plAutoProvider.notifier)
      ..setEnabled(true)
      ..setEveryMin(720)
      ..setOnStart(false);
    await first.read(plAutoProvider.notifier).runSweep(silent: true);

    final second = _container(_FakeSoundCloud(const {}), store);
    final state = second.read(plAutoProvider);
    expect(state.enabled, isTrue);
    expect(state.everyMin, 720);
    expect(state.onStart, isFalse);
    // Отметка — на самом плейлисте, итоги и время прохода — в kv базы.
    expect(second.read(libraryProvider).playlists.single.autoRefresh, isTrue);
    expect(state.runs[pl.id]?.added, 1);
    expect(state.lastRun, greaterThan(0));
  });

  test('итоги удалённого плейлиста забываются', () async {
    final store = JsonStore.memory();
    final first = _container(
      _FakeSoundCloud({
        'sc:set:1': [_track('sc:1')],
      }),
      store,
    );
    final lib = first.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Первый', source: _src('sc:set:1'));
    lib.setAutoRefresh([pl.id], true);
    await first.read(plAutoProvider.notifier).runSweep(silent: true);
    lib.deletePlaylist(pl.id);

    final second = _container(_FakeSoundCloud(const {}), store);
    expect(second.read(plAutoProvider).runs, isEmpty);
  });
}
