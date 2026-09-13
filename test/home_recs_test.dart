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
  final meta = {
    for (final t in [...tracks, ...heard])
      t.id: PlayMeta(
        name: t.name,
        artist: t.artist,
        cover: null,
        seconds: t.duration.inSeconds,
      ),
  };
  return RecsInput(
    registry: ProviderRegistry()..register(provider),
    stats: PlayStats.build(PlayLog(events: events, meta: meta), const []),
    lib: LibraryState(
      tracks: {for (final t in tracks) t.id: t},
      inLib: {
        for (final (i, t) in tracks.indexed)
          if (favs.contains(t.id)) t.id: i,
      },
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
      final guard = DupGuard()..add(_t('sc_1', name: 'целоваться'));
      expect(
        guard.accept(_t('sc_2', name: 'Artist - целоваться', artist: 'x')),
        isFalse,
      );
      expect(guard.accept(_t('sc_3', name: 'другое')), isTrue);
    });

    test('снимок из журнала ловит перезалив, как и трек', () {
      final guard = DupGuard()
        ..addPrint(TrackFingerprint(name: 'Ночь', artist: 'X', seconds: 200));
      expect(
        guard.accept(_t('sc_1', name: 'X - Ночь', artist: 'up', seconds: 203)),
        isFalse,
      );
      // Общее слово есть, но это другой трек (длительность далеко за
      // допуском) — индекс не должен его путать.
      expect(
        guard.accept(_t('sc_2', name: 'Ночь', artist: 'Y', seconds: 260)),
        isTrue,
      );
    });
  });

  group('«Для вас»: сиды', () {
    test('самое слушаемое за окно, только площадки с похожими', () {
      final input = _input(
        provider: _Fake(),
        plays: {'sc_1': 5, 'ym_2': 4, 'sc_3': 3, 'ytm_4': 9, 'lf_5': 9},
      );
      expect(pickForYouSeeds(input), ['sc_1', 'ym_2', 'sc_3']);
    });

    test('за окном мало — считаем за всё время', () {
      final input = _input(
        provider: _Fake(),
        plays: {'sc_old': 6, 'sc_new': 2},
        daysAgo: {'sc_old': 200},
      );
      // За 90 дней только один трек — меньше трёх, поэтому берём всё время.
      expect(pickForYouSeeds(input), ['sc_old', 'sc_new']);
    });

    test('дизлайкнутое сидом не становится, лайки добивают', () {
      final input = _input(
        provider: _Fake(),
        plays: {'sc_1': 5, 'sc_2': 4},
        tracks: [_t('sc_9')],
        favs: {'sc_9'},
        disliked: {'sc_1'},
      );
      expect(pickForYouSeeds(input), ['sc_2', 'sc_9']);
    });
  });

  group('«Для вас»: полоса', () {
    test(
      'по кругу, без знакомого, не больше двух от артиста, без дублей',
      () async {
        final provider = _Fake(
          similar: {
            'sc_1': [
              _t('sc_10', artist: 'A'),
              _t('sc_11', artist: 'A'),
              _t('sc_12', artist: 'A'),
              _t('sc_2'), // уже слушали
            ],
            'sc_2': [
              _t('sc_20', name: 'Песня', artist: 'B'),
              _t('sc_21', name: 'B - Песня', artist: 'uploader'), // реаплоад
              _t('sc_22', artist: 'C'),
            ],
          },
        );
        final input = _input(provider: provider, plays: {'sc_1': 3, 'sc_2': 2});
        final out = await buildForYou(input);

        expect(out.map((t) => t.id), ['sc_10', 'sc_20', 'sc_11', 'sc_22']);
      },
    );

    test('перезалив слышанного, но не сохранённого, не встаёт', () async {
      final provider = _Fake(
        similar: {
          'sc_1': [
            _t('sc_30', name: 'lightprey - целоваться', artist: 'クリソライト'),
            _t('sc_31', name: 'Другое', artist: 'D'),
          ],
        },
      );
      final input = _input(
        provider: provider,
        // ytm_ — не сид (похожих у площадки нет), только слышанное.
        plays: {'sc_1': 3, 'ytm_9': 1},
        heard: [_t('ytm_9', name: 'целоваться', artist: 'lightprey')],
      );
      expect((await buildForYou(input)).map((t) => t.id), ['sc_31']);
    });

    test('площадка без похожих — полосы нет', () async {
      final input = _input(provider: _Fake(), plays: {'sc_1': 3});
      expect(await buildForYou(input), isEmpty);
    });
  });

  group('«Похожие на»', () {
    test('смесь: артист на каждой третьей позиции, хвост добивается', () {
      final tracks = [for (var i = 0; i < 3; i++) _t('sc_$i')];
      final artists = [
        for (var i = 0; i < 3; i++)
          Artist(
            id: 'sc_artist_$i',
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
      final seed = _t('sc_1', name: 'Сид');
      final provider = _Fake(
        similar: {
          'sc_1': [for (var i = 0; i < 5; i++) _t('sc_1$i', artist: 'X$i')],
        },
      );
      final res = await buildSimilarTo(
        _input(
          provider: provider,
          plays: {'sc_1': 4},
          tracks: [seed],
          now: dayWith(even: false),
        ),
      );

      expect(res?.seed, isA<SimilarTrackSeed>());
      expect(res!.seed.name, 'Сид');
      expect((res.seed as SimilarTrackSeed).track?.id, 'sc_1');
      expect(res.items.length, 5);
    });

    test('без перезаливов «Для вас» и слышанного', () async {
      final provider = _Fake(
        similar: {
          'sc_1': [
            _t('sc_40', name: 'X - Ночь', artist: 'uploader'),
            _t('sc_41', name: 'lightprey - целоваться', artist: 'クリソライト'),
            for (var i = 0; i < 5; i++) _t('sc_5$i', artist: 'Y$i'),
          ],
        },
      );
      final res = await buildSimilarTo(
        _input(
          provider: provider,
          plays: {'sc_1': 4, 'ytm_9': 1},
          tracks: [_t('sc_1', name: 'Сид')],
          heard: [_t('ytm_9', name: 'целоваться', artist: 'lightprey')],
          now: dayWith(even: false),
        ),
        forYou: [_t('sc_70', name: 'Ночь', artist: 'X')],
      );

      final ids = [
        for (final it in res!.items)
          if (it is SimilarTrackItem) it.track.id,
      ];
      expect(ids, isNot(contains('sc_40')));
      expect(ids, isNot(contains('sc_41')));
      expect(ids, contains('sc_50'));
    });

    test('чётный день — артист-сид, его собственные треки не лезут', () async {
      final mine = _t('sc_1', artist: 'Хозяин', artistId: 'sc_artist_7');
      final provider = _Fake(
        similar: {
          'sc_1': [
            _t('sc_50', artist: 'Хозяин'),
            for (var i = 0; i < 3; i++) _t('sc_6$i', artist: 'Y$i'),
          ],
        },
        pages: {
          'sc_artist_7': ArtistPageData(
            artist: const Artist(
              id: 'sc_artist_7',
              name: 'Хозяин',
              avatar: 'https://a/ava.jpg',
              source: MusicSource.soundcloud,
            ),
            similarArtists: [
              for (var i = 0; i < 2; i++)
                Artist(
                  id: 'sc_artist_8$i',
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
          plays: {'sc_1': 4},
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
      expect(ids, isNot(contains('sc_50')));
      expect(ids, containsAll(['sc_60', 'sc_artist_80']));
    });

    test('сид и элементы переживают кэш', () {
      const artist = Artist(
        id: 'sc_artist_1',
        name: 'A',
        avatar: 'https://a',
        source: MusicSource.soundcloud,
      );
      final seed = SimilarTrackSeed(
        id: 'sc_1',
        name: 'Сид',
        artist: 'A',
        track: _t('sc_1', name: 'Сид'),
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
