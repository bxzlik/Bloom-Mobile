/// Витрины главной «Для вас» и «Похожие на»: сиды из журнала, отбор незнакомого,
/// отсев реаплоадов, смесь треков и артистов. Площадка — фейковая, сеть не нужна.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:bloom/features/home/for_you.dart';
import 'package:bloom/features/home/similar_to.dart';
import 'package:bloom/shared/util/track_dedup.dart';
import 'package:flutter_test/flutter_test.dart';

const int _day = 24 * 3600 * 1000;

Track _t(
  String id, {
  String? name,
  String artist = 'Artist',
  int seconds = 180,
  String? artistId,
}) => Track(
  id: id,
  name: name ?? id,
  artist: artist,
  duration: Duration(seconds: seconds),
  source: MusicSource.fromId(id),
  artistId: artistId,
);

/// Площадка, которая отвечает похожими из словаря.
class _Fake extends MusicProvider {
  _Fake({this.similar = const {}, this.pages = const {}});

  final Map<String, List<Track>> similar;
  final Map<String, ArtistPageData> pages;
  final List<String> asked = [];

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<List<Track>?> getSimilarTracks(String seedId) async {
    asked.add(seedId);
    return similar[seedId] ?? const [];
  }

  @override
  Future<ArtistPageData?> getArtist(String id) async => pages[id];
}

/// Вход витрин: [plays] — id → сколько раз слушали (в пределах [daysAgo]).
/// [heard] — слышанное, но не сохранённое: есть только снимок в журнале.
RecsInput _input({
  required _Fake provider,
  Map<String, int> plays = const {},
  Map<String, int> daysAgo = const {},
  List<Track> tracks = const [],
  List<Track> heard = const [],
  Set<String> favs = const {},
  Set<String> disliked = const {},
  DateTime? now,
}) {
  final at = (now ?? DateTime(2026, 9, 13)).millisecondsSinceEpoch;
  final events = <PlayEvent>[
    for (final e in plays.entries)
      for (var i = 0; i < e.value; i++)
        PlayEvent(at - (daysAgo[e.key] ?? 1) * _day + i, e.key),
  ]..sort((a, b) => a.ts.compareTo(b.ts));
  final snapshots = {
    for (final t in [...tracks, ...heard]) t.id: t,
  };
  return RecsInput(
    registry: ProviderRegistry()..register(provider),
    stats: PlayStats.build(PlayLog(events: events, tracks: snapshots)),
    lib: LibraryState(
      tracks: {for (final t in tracks) t.id: t},
      // Последний в [favs] — самый свежий лайк, он и сверху.
      libIds: [
        for (final t in tracks.reversed)
          if (favs.contains(t.id)) t.id,
      ],
      inLib: {
        for (final (i, t) in tracks.indexed)
          if (favs.contains(t.id)) t.id: i,
      },
      favIds: favs.toList().reversed.toList(),
      favs: {for (final (i, id) in favs.indexed) id: i},
    ),
    disliked: disliked,
    now: now ?? DateTime(2026, 9, 13),
  );
}

void main() {
  group('реаплоады', () {
    test('имя автора, переехавшее в заголовок, не делает трек другим', () {
      final a = TrackFingerprint(name: 'целоваться', artist: 'lightprey');
      final b = TrackFingerprint(
        name: 'lightprey - целоваться',
        artist: 'クリソライト',
      );
      expect(sameTrack(a, b), isTrue);
    });

    test('разные треки одного артиста — не дубли', () {
      final a = TrackFingerprint(name: 'Ночь', artist: 'Artist', seconds: 200);
      final b = TrackFingerprint(name: 'День', artist: 'Artist', seconds: 202);
      expect(sameTrack(a, b), isFalse);
    });

    test('короткое общее название сверяется по длительности', () {
      TrackFingerprint fp(String artist, int sec) =>
          TrackFingerprint(name: 'sleep mode', artist: artist, seconds: sec);
      expect(sameTrack(fp('a', 180), fp('b', 195)), isTrue);
      expect(sameTrack(fp('a', 180), fp('b', 300)), isFalse);
    });

    test('накопитель пропускает повтор, а новое принимает', () {
      final guard = DupGuard()..add(_t('sc:1', name: 'целоваться'));
      expect(
        guard.accept(_t('sc:2', name: 'Artist - целоваться', artist: 'x')),
        isFalse,
      );
      expect(guard.accept(_t('sc:3', name: 'другое')), isTrue);
    });

    test('снимок из журнала ловит перезалив, как и трек', () {
      final guard = DupGuard()
        ..addPrint(TrackFingerprint(name: 'Ночь', artist: 'X', seconds: 200));
      expect(
        guard.accept(_t('sc:1', name: 'X - Ночь', artist: 'up', seconds: 203)),
        isFalse,
      );
      // Общее слово есть, но это другой трек (длительность далеко за
      // допуском) — индекс не должен его путать.
      expect(
        guard.accept(_t('sc:2', name: 'Ночь', artist: 'Y', seconds: 260)),
        isTrue,
      );
    });
  });

  group('«Для вас»: сиды', () {
    test('самое слушаемое за окно, только площадки с похожими', () {
      final input = _input(
        provider: _Fake(),
        plays: {'sc:1': 5, 'ym:2': 4, 'sc:3': 3, 'ytm:4': 9, 'lf_5': 9},
      );
      expect(pickForYouSeeds(input), ['sc:1', 'ym:2', 'sc:3']);
    });

    test('за окном мало — считаем за всё время', () {
      final input = _input(
        provider: _Fake(),
        plays: {'sc:old': 6, 'sc:new': 2},
        daysAgo: {'sc:old': 200},
      );
      // За 90 дней только один трек — меньше трёх, поэтому берём всё время.
      expect(pickForYouSeeds(input), ['sc:old', 'sc:new']);
    });

    test('дизлайкнутое сидом не становится, лайки добивают', () {
      final input = _input(
        provider: _Fake(),
        plays: {'sc:1': 5, 'sc:2': 4},
        tracks: [_t('sc:9')],
        favs: {'sc:9'},
        disliked: {'sc:1'},
      );
      expect(pickForYouSeeds(input), ['sc:2', 'sc:9']);
    });
  });

  group('«Для вас»: полоса', () {
    test(
      'по кругу, без знакомого, не больше двух от артиста, без дублей',
      () async {
        final provider = _Fake(
          similar: {
            'sc:1': [
              _t('sc:10', artist: 'A'),
              _t('sc:11', artist: 'A'),
              _t('sc:12', artist: 'A'),
              _t('sc:2'), // уже слушали
            ],
            'sc:2': [
              _t('sc:20', name: 'Песня', artist: 'B'),
              _t('sc:21', name: 'B - Песня', artist: 'uploader'), // реаплоад
              _t('sc:22', artist: 'C'),
            ],
          },
        );
        final input = _input(provider: provider, plays: {'sc:1': 3, 'sc:2': 2});
        final out = await buildForYou(input);

        expect(out.map((t) => t.id), ['sc:10', 'sc:20', 'sc:11', 'sc:22']);
      },
    );

    test('перезалив слышанного, но не сохранённого, не встаёт', () async {
      final provider = _Fake(
        similar: {
          'sc:1': [
            _t('sc:30', name: 'lightprey - целоваться', artist: 'クリソライト'),
            _t('sc:31', name: 'Другое', artist: 'D'),
          ],
        },
      );
      final input = _input(
        provider: provider,
        // ytm_ — не сид (похожих у площадки нет), только слышанное.
        plays: {'sc:1': 3, 'ytm:9': 1},
        heard: [_t('ytm:9', name: 'целоваться', artist: 'lightprey')],
      );
      expect((await buildForYou(input)).map((t) => t.id), ['sc:31']);
    });

    test('площадка без похожих — полосы нет', () async {
      final input = _input(provider: _Fake(), plays: {'sc:1': 3});
      expect(await buildForYou(input), isEmpty);
    });
  });

  group('«Похожие на»', () {
    test('смесь: артист на каждой третьей позиции, хвост добивается', () {
      final tracks = [for (var i = 0; i < 3; i++) _t('sc:$i')];
      final artists = [
        for (var i = 0; i < 3; i++)
          Artist(
            id: 'sc:artist:$i',
            name: 'A$i',
            source: MusicSource.soundcloud,
          ),
      ];
      final kinds = [
        for (final it in mixSimilar(tracks, artists))
          it is SimilarTrackItem ? 'T' : 'A',
      ];
      expect(kinds.join(), 'TATTAA');
    });

    DateTime dayWith({required bool even}) {
      var d = DateTime(2026, 9, 13);
      while (recsDayNumber(d).isEven != even) {
        d = d.add(const Duration(days: 1));
      }
      return d;
    }

    test('нечётный день — трек-сид с похожими треками', () async {
      final seed = _t('sc:1', name: 'Сид');
      final provider = _Fake(
        similar: {
          'sc:1': [for (var i = 0; i < 5; i++) _t('sc:1$i', artist: 'X$i')],
        },
      );
      final res = await buildSimilarTo(
        _input(
          provider: provider,
          plays: {'sc:1': 4},
          tracks: [seed],
          now: dayWith(even: false),
        ),
      );

      expect(res?.seed, isA<SimilarTrackSeed>());
      expect(res!.seed.name, 'Сид');
      expect((res.seed as SimilarTrackSeed).track?.id, 'sc:1');
      expect(res.items.length, 5);
    });

    test('без перезаливов «Для вас» и слышанного', () async {
      final provider = _Fake(
        similar: {
          'sc:1': [
            _t('sc:40', name: 'X - Ночь', artist: 'uploader'),
            _t('sc:41', name: 'lightprey - целоваться', artist: 'クリソライト'),
            for (var i = 0; i < 5; i++) _t('sc:5$i', artist: 'Y$i'),
          ],
        },
      );
      final res = await buildSimilarTo(
        _input(
          provider: provider,
          plays: {'sc:1': 4, 'ytm:9': 1},
          tracks: [_t('sc:1', name: 'Сид')],
          heard: [_t('ytm:9', name: 'целоваться', artist: 'lightprey')],
          now: dayWith(even: false),
        ),
        forYou: [_t('sc:70', name: 'Ночь', artist: 'X')],
      );

      final ids = [
        for (final it in res!.items)
          if (it is SimilarTrackItem) it.track.id,
      ];
      expect(ids, isNot(contains('sc:40')));
      expect(ids, isNot(contains('sc:41')));
      expect(ids, contains('sc:50'));
    });

    test('чётный день — артист-сид, его собственные треки не лезут', () async {
      final mine = _t('sc:1', artist: 'Хозяин', artistId: 'sc:artist:7');
      final provider = _Fake(
        similar: {
          'sc:1': [
            _t('sc:50', artist: 'Хозяин'),
            for (var i = 0; i < 3; i++) _t('sc:6$i', artist: 'Y$i'),
          ],
        },
        pages: {
          'sc:artist:7': ArtistPageData(
            artist: const Artist(
              id: 'sc:artist:7',
              name: 'Хозяин',
              avatar: 'https://a/ava.jpg',
              source: MusicSource.soundcloud,
            ),
            similarArtists: [
              for (var i = 0; i < 2; i++)
                Artist(
                  id: 'sc:artist:8$i',
                  name: 'Сосед $i',
                  avatar: 'https://a/$i.jpg',
                  source: MusicSource.soundcloud,
                ),
            ],
          ),
        },
      );
      final res = await buildSimilarTo(
        _input(
          provider: provider,
          plays: {'sc:1': 4},
          tracks: [mine],
          now: dayWith(even: true),
        ),
      );

      expect(res?.seed, isA<SimilarArtistSeed>());
      expect(res!.seed.cover, 'https://a/ava.jpg');
      final ids = [
        for (final it in res.items)
          switch (it) {
            SimilarTrackItem(:final track) => track.id,
            SimilarArtistItem(:final artist) => artist.id,
          },
      ];
      expect(ids, isNot(contains('sc:50')));
      expect(ids, containsAll(['sc:60', 'sc:artist:80']));
    });

    test('сид и элементы переживают кэш', () {
      const artist = Artist(
        id: 'sc:artist:1',
        name: 'A',
        avatar: 'https://a',
        source: MusicSource.soundcloud,
      );
      final seed = SimilarTrackSeed(
        id: 'sc:1',
        name: 'Сид',
        artist: 'A',
        track: _t('sc:1', name: 'Сид'),
      );
      final back = SimilarSeed.fromJson(seed.toJson());
      expect(back, isA<SimilarTrackSeed>());
      expect((back as SimilarTrackSeed).track?.name, 'Сид');

      final item = SimilarItem.fromJson(
        const SimilarArtistItem(artist).toJson(),
      );
      expect((item as SimilarArtistItem).artist.avatar, 'https://a');
    });
  });
}
