/// «Перенести на площадку»: скан, решения по трекам и состав копии.
///
/// Площадка — подставная: сеть здесь не при чём, проверяется разбор её выдачи.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/features/library/convert_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(
  String id, {
  String name = 'Ночь',
  String artist = 'Один',
  int seconds = 200,
  MusicSource source = MusicSource.soundcloud,
}) => Track(
  id: id,
  name: name,
  artist: artist,
  duration: Duration(seconds: seconds),
  source: source,
);

/// Отдаёт заранее заданную выдачу по запросу; `null` — площадка «упала».
class _FakeProvider extends MusicProvider {
  _FakeProvider(this.answers, {this.throwsOn = const {}});

  final Map<String, List<Track>> answers;
  final Set<String> throwsOn;

  /// Сколько запросов ушло — по нему видно, что скан не ходит за тем, что и так
  /// на площадке.
  int calls = 0;

  @override
  MusicSource get source => MusicSource.ytmusic;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    calls++;
    if (throwsOn.contains(query)) throw StateError('площадка не ответила');
    return SearchResults(tracks: answers[query] ?? const []);
  }
}

void main() {
  test('уверенное совпадение подставляется само', () async {
    final src = _track('sc_1');
    final provider = _FakeProvider({
      'Ночь Один': [_track('ytm_1', seconds: 201, source: MusicSource.ytmusic)],
    });

    final items = await scanPlaylistConversion(provider, [src]);
    expect(items.single.status, ConvertStatus.exact);

    final decisions = defaultDecisions(items);
    expect(convertResult(items, decisions).single.id, 'ytm_1');
  });

  test('спорное остаётся оригиналом, пока не выбрали', () async {
    final src = _track('sc_1');
    final provider = _FakeProvider({
      // То же название, но на час длиннее — матчер уверенным это не считает.
      'Ночь Один': [
        _track('ytm_1', seconds: 3600, source: MusicSource.ytmusic),
      ],
    });

    final items = await scanPlaylistConversion(provider, [src]);
    expect(items.single.status, ConvertStatus.ambiguous);
    expect(convertResult(items, defaultDecisions(items)).single.id, 'sc_1');

    // Выбрали кандидата руками — в копию идёт он.
    final picked = {'sc_1': TakeMatch(items.single.cands.first.track)};
    expect(convertResult(items, picked).single.id, 'ytm_1');
  });

  test('трек уже на целевой площадке — за ним не ходим', () async {
    final provider = _FakeProvider(const {});
    final items = await scanPlaylistConversion(provider, [
      _track('ytm_7', source: MusicSource.ytmusic),
    ]);

    expect(items.single.status, ConvertStatus.same);
    expect(items.single.cands, isEmpty);
    expect(provider.calls, 0);
  });

  test('упавшая площадка отличается от честного «не нашлось»', () async {
    final provider = _FakeProvider(const {}, throwsOn: {'Ночь Один'});
    final items = await scanPlaylistConversion(provider, [_track('sc_1')]);

    expect(items.single.status, ConvertStatus.notfound);
    expect(items.single.failed, isTrue);
  });

  test('чужие площадки из выдачи в кандидаты не попадают', () async {
    final provider = _FakeProvider({
      'Ночь Один': [
        _track('sc_2', seconds: 200), // тот же трек, но не с целевой площадки
      ],
    });

    final items = await scanPlaylistConversion(provider, [_track('sc_1')]);
    expect(items.single.status, ConvertStatus.notfound);
    expect(items.single.failed, isFalse);
  });

  test('пропущенный трек в копию не идёт, порядок остальных прежний', () async {
    final provider = _FakeProvider({
      'Ночь Один': [_track('ytm_1', seconds: 200, source: MusicSource.ytmusic)],
      'Утро Один': [
        _track(
          'ytm_2',
          name: 'Утро',
          seconds: 200,
          source: MusicSource.ytmusic,
        ),
      ],
    });
    final items = await scanPlaylistConversion(provider, [
      _track('sc_1'),
      _track('sc_2', name: 'Утро'),
    ]);

    final decisions = {...defaultDecisions(items), 'sc_1': const SkipTrack()};
    expect(convertResult(items, decisions).map((t) => t.id), ['ytm_2']);

    final stats = convertStats(items, decisions);
    expect(stats.moved, 1);
    expect(stats.skipped, 1);
    expect(stats.kept, 0);
  });

  test('прогресс доходит до конца и порядок результатов сохраняется', () async {
    final provider = _FakeProvider(const {});
    final tracks = [
      for (var i = 0; i < 7; i++) _track('sc_$i', name: 'Песня $i'),
    ];
    final progress = <int>[];

    final items = await scanPlaylistConversion(
      provider,
      tracks,
      onProgress: (done, _) => progress.add(done),
    );

    expect(items.map((i) => i.src.id), tracks.map((t) => t.id));
    expect(progress.last, 7);
  });

  test('отмена останавливает скан, а не доедает список', () async {
    final provider = _FakeProvider(const {});
    var cancelled = false;
    final tracks = [
      for (var i = 0; i < 20; i++) _track('sc_$i', name: 'Песня $i'),
    ];

    final items = await scanPlaylistConversion(
      provider,
      tracks,
      cancelled: () => cancelled,
      onProgress: (done, _) {
        if (done >= 3) cancelled = true;
      },
    );

    expect(items.length, lessThan(tracks.length));
    expect(provider.calls, lessThan(tracks.length));
  });
}
