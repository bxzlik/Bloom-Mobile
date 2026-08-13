/// Главная: снимок сессии («Продолжить»), лента «Недавно слушали» и витрина
/// «Новинки»/«Чарты» с её кешем и тихими повторами.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/home/discover_store.dart';
import 'package:bloom/features/home/ui/home_sections.dart';
import 'package:bloom/features/player/resume_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: 'sc_$id',
  name: id,
  artist: 'A',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

/// Площадка, которая отдаёт витрину не с первого раза.
class _FakeProvider extends MusicProvider {
  _FakeProvider({this.charts, this.releases, this.failFirst = 0});

  final List<Track>? charts;
  final NewReleases? releases;

  /// Сколько первых ответов «сорвать» — пустотой, как это делает landing3.
  int failFirst;

  int chartCalls = 0;

  @override
  MusicSource get source => MusicSource.yandex;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<List<Track>?> getCharts() async {
    chartCalls++;
    if (failFirst > 0) {
      failFirst--;
      return const [];
    }
    return charts;
  }

  @override
  Future<NewReleases?> getNewReleases() async => releases;
}

ProviderContainer _container(MusicProvider provider) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      registryProvider.overrideWithValue(
        ProviderRegistry()..register(provider),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(resetDiscoverCache);

  group('снимок сессии', () {
    test('короткая очередь уносится целиком', () {
      final queue = [_track('a'), _track('b'), _track('c')];
      final data = ResumeData.capture(
        queue: queue,
        index: 1,
        position: const Duration(seconds: 42),
        paused: true,
      );
      expect(data.queue.length, 3);
      expect(data.index, 1);
      expect(data.track.id, 'sc_b');
    });

    test('длинная режется с текущего трека — он обязан попасть в снимок', () {
      final queue = [for (var i = 0; i < 500; i++) _track('t$i')];
      final data = ResumeData.capture(
        queue: queue,
        index: 400,
        position: Duration.zero,
        paused: false,
      );
      expect(data.queue.length, kResumeQueueLimit);
      expect(data.track.id, 'sc_t400');
      // Хвост короче лимита — окно сдвигается назад, но текущий остаётся внутри.
      final tail = ResumeData.capture(
        queue: queue,
        index: 495,
        position: Duration.zero,
        paused: false,
      );
      expect(tail.queue.length, kResumeQueueLimit);
      expect(tail.track.id, 'sc_t495');
    });

    test('переживает запись и чтение', () {
      final saved = ResumeData.capture(
        queue: [_track('a'), _track('b')],
        index: 1,
        position: const Duration(seconds: 90),
        paused: true,
        sourceId: 'pl_1',
      );
      final read = ResumeData.fromJson(saved.toJson());
      expect(read, isNotNull);
      expect(read!.track.id, 'sc_b');
      expect(read.position, const Duration(seconds: 90));
      expect(read.sourceId, 'pl_1');
      expect(read.paused, isTrue);
    });

    test('битый номер трека не теряет снимок', () {
      final json = ResumeData.capture(
        queue: [_track('a')],
        index: 0,
        position: Duration.zero,
        paused: true,
      ).toJson();
      json['index'] = 7;
      expect(ResumeData.fromJson(json)?.track.id, 'sc_a');
    });

    test('пустая очередь снимком не считается', () {
      expect(ResumeData.fromJson({'queue': <Object>[], 'index': 0}), isNull);
    });

    test('контроллер читает записанное и чистит', () {
      final store = JsonStore.memory();
      final c = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      expect(c.read(resumeProvider), isNull);
      c
          .read(resumeProvider.notifier)
          .save(
            ResumeData.capture(
              queue: [_track('a')],
              index: 0,
              position: const Duration(seconds: 5),
              paused: true,
            ),
          );
      expect(store.read(kResumeKey), isNotNull);
      expect(ResumeData.fromJson(store.read(kResumeKey))?.track.id, 'sc_a');
      c.read(resumeProvider.notifier).clear();
      expect(c.read(resumeProvider), isNull);
      expect(store.read(kResumeKey), isNull);
    });
  });

  group('недавно слушали', () {
    test('повторы схлопываются, лимит соблюдается', () {
      final tracks = {
        for (final id in ['a', 'b', 'c']) 'sc_$id': _track(id),
      };
      final lib = LibraryState(
        tracks: tracks,
        history: const [
          HistoryEntry('sc_a', 5),
          HistoryEntry('sc_a', 4),
          HistoryEntry('sc_b', 3),
          HistoryEntry('sc_c', 2),
        ],
      );
      expect(
        recentTracks(lib, 12).map((t) => t.id),
        ['sc_a', 'sc_b', 'sc_c'],
      );
      expect(recentTracks(lib, 2).map((t) => t.id), ['sc_a', 'sc_b']);
    });

    test('трека нет в хранилище — строка просто пропускается', () {
      final lib = LibraryState(
        tracks: {'sc_b': _track('b')},
        history: const [HistoryEntry('sc_a', 2), HistoryEntry('sc_b', 1)],
      );
      expect(recentTracks(lib, 12).map((t) => t.id), ['sc_b']);
    });
  });

  group('витрина', () {
    test('чарт берётся у площадки и кешируется', () async {
      final provider = _FakeProvider(charts: [_track('a')]);
      final c = _container(provider);

      final first = await fetchDiscover(c.read(registryProvider), DiscoverMode.charts);
      expect(first, isNotNull);
      expect(first!.source, MusicSource.yandex);
      expect((first.block as DiscoverTracks).tracks.single.id, 'sc_a');
      expect(provider.chartCalls, 1);

      // Второй заход на главную сеть не дёргает.
      await fetchDiscover(c.read(registryProvider), DiscoverMode.charts);
      expect(provider.chartCalls, 1);
    });

    test('пустой ответ не кешируется, провайдер повторяет запрос', () async {
      final provider = _FakeProvider(charts: [_track('a')], failFirst: 1);
      final c = _container(provider);

      final result = await c.read(discoverProvider(DiscoverMode.charts).future);
      expect(result, isNotNull);
      expect((result!.block as DiscoverTracks).tracks.single.id, 'sc_a');
      // Первый ответ был пустой — значит сходили дважды.
      expect(provider.chartCalls, 2);
    });

    test('площадка молчит совсем — блока нет', () async {
      final provider = _FakeProvider(charts: [_track('a')], failFirst: 99);
      final c = _container(provider);
      expect(
        await c.read(discoverProvider(DiscoverMode.charts).future),
        isNull,
      );
      // Заходов ровно столько, сколько попыток: первая плюс повторы.
      expect(provider.chartCalls, kDiscoverRetries.length + 1);
    });

    test('новинки альбомами разбираются как альбомы', () async {
      final album = Playlist(
        id: 'ym_1',
        title: 'Альбом',
        source: MusicSource.yandex,
        isAlbum: true,
      );
      final c = _container(_FakeProvider(releases: NewAlbums([album])));
      final result = await c.read(
        discoverProvider(DiscoverMode.newReleases).future,
      );
      expect((result!.block as DiscoverAlbums).albums.single.id, 'ym_1');
    });

    test('новинки треками разбираются как треки', () async {
      final c = _container(_FakeProvider(releases: NewTracks([_track('n')])));
      final result = await c.read(
        discoverProvider(DiscoverMode.newReleases).future,
      );
      expect((result!.block as DiscoverTracks).tracks.single.id, 'sc_n');
    });
  });
}
