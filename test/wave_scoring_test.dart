/// Фильтры, скоринг и разрядка пачки — то, что решает, ЧТО именно человек
/// услышит в волне и в каком порядке.
library;

import 'dart:math';

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/wave/wave_scoring.dart';
import 'package:bloom/features/wave/wave_types.dart';
import 'package:bloom/providers/soundcloud/models.dart';
import 'package:flutter_test/flutter_test.dart';

ScRawTrack _raw(
  int id, {
  String artist = 'Artist',
  String? genre,
  List<String> tags = const [],
  String? policy,
}) => ScRawTrack(
  id: id,
  title: 'Song $id',
  artist: artist,
  artistScId: 1,
  artwork: null,
  duration: 100000,
  permalink: null,
  media: null,
  genre: genre,
  tags: tags,
  album: '',
  publisher: '',
  description: '',
  explicit: false,
  creditedArtist: '',
  artistAvatar: null,
  artistPermalink: null,
  artistVerified: false,
  year: '',
  playbackCount: null,
  policy: policy,
);

Track _track(String id, {String artist = 'Artist'}) => Track(
  id: id,
  name: id,
  artist: artist,
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
);

WaveCandidate _guest(
  int id, {
  String artist = 'Artist',
  int rank = 0,
  List<String> genres = const [],
}) => WaveCandidate(
  track: _track('sc_$id', artist: artist),
  origin: WaveOrigin.station,
  sourceRank: rank,
  artistKey: normalizeArtist(artist),
  genres: genres,
);

WaveFilterCtx _ctx({
  Set<String> seedGenres = const {},
  WaveSession? session,
  Set<String> queueIds = const {},
  Set<String> disliked = const {},
  Set<String> inLibrary = const {},
  Set<String> favIds = const {},
  Set<String> shown = const {},
  Set<String> recent = const {},
  String? currentId,
}) => WaveFilterCtx(
  seedGenres: seedGenres,
  session:
      session ??
      WaveSession(mode: WaveMode.personal, seeds: const [], startedAt: 0),
  queueIds: queueIds,
  disliked: disliked,
  inLibrary: inLibrary,
  favIds: favIds,
  wasShown: shown.contains,
  recentlyPlayed: (id, _) => recent.contains(id),
  currentId: currentId,
);

void main() {
  group('candidateFromSc', () {
    test('заблокированное площадкой в волну не попадает', () {
      expect(
        candidateFromSc(_raw(1, policy: 'BLOCK'), WaveOrigin.station, 0),
        isNull,
      );
      expect(
        candidateFromSc(_raw(2, policy: 'SNIP'), WaveOrigin.station, 0),
        isNull,
      );
      expect(
        candidateFromSc(_raw(3, policy: 'ALLOW'), WaveOrigin.station, 0),
        isNotNull,
      );
      // Поля нет вовсе — это обычный играбельный трек.
      expect(candidateFromSc(_raw(4), WaveOrigin.station, 0), isNotNull);
    });

    test('теги идут в жанры кандидата наравне с жанром', () {
      final c = candidateFromSc(
        _raw(1, genre: 'Techno', tags: ['Detroit', 'Warehouse']),
        WaveOrigin.related,
        3,
      )!;
      expect(c.genres, ['techno', 'detroit', 'warehouse']);
      // Но в сам трек теги не текут — их увидел бы весь остальной интерфейс.
      expect(c.track.genres, ['techno']);
    });
  });

  group('passesFilters', () {
    test('играющий, стоящий в очереди и уже сыгранный отсеиваются', () {
      final session = WaveSession(
        mode: WaveMode.personal,
        seeds: const [],
        startedAt: 0,
        playedIds: ['sc_3'],
      );
      final ctx = _ctx(session: session, currentId: 'sc_1', queueIds: {'sc_2'});
      expect(passesFilters(_guest(1), ctx), isFalse);
      expect(passesFilters(_guest(2), ctx), isFalse);
      expect(passesFilters(_guest(3), ctx), isFalse);
      expect(passesFilters(_guest(4), ctx), isTrue);
    });

    test('дизлайк — про сам трек, соседей того же артиста не трогает', () {
      final ctx = _ctx(disliked: {'sc_1'});
      expect(passesFilters(_guest(1, artist: 'A'), ctx), isFalse);
      expect(passesFilters(_guest(2, artist: 'A'), ctx), isTrue);
    });

    test('свежая находка, которая уже в библиотеке, находкой не считается', () {
      final ctx = _ctx(inLibrary: {'sc_1'});
      expect(passesFilters(_guest(1), ctx), isFalse);
      // А подмешанное знакомое приходит именно из библиотеки — его пускаем.
      final familiar = candidateFromLibrary(_track('sc_1'), 0);
      expect(passesFilters(familiar, ctx), isTrue);
    });

    test('недавно слушанное и уже показанное волной не повторяем', () {
      final ctx = _ctx(recent: {'sc_1'}, shown: {'sc_2'});
      expect(passesFilters(_guest(1), ctx), isFalse);
      expect(passesFilters(_guest(2), ctx), isFalse);
    });

    test(
      'ослабленный проход снимает «недавно» и «показывали», но не дизлайк',
      () {
        final ctx = _ctx(
          recent: {'sc_1'},
          shown: {'sc_2'},
          disliked: {'sc_3'},
        ).relax();
        expect(passesFilters(_guest(1), ctx), isTrue);
        expect(passesFilters(_guest(2), ctx), isTrue);
        expect(passesFilters(_guest(3), ctx), isFalse);
      },
    );

    test('«уже показывали» к подмешанным знакомым не применяется', () {
      final ctx = _ctx(shown: {'sc_1'});
      expect(
        passesFilters(candidateFromLibrary(_track('sc_1'), 0), ctx),
        isTrue,
      );
    });
  });

  group('scoreCandidate', () {
    // Случайную добавку глушим постоянным зерном: сравниваем вклады, а не удачу.
    Random seeded() => Random(1);

    test('верх выдачи площадки идёт выше хвоста', () {
      final ctx = _ctx();
      final top = scoreCandidate(_guest(1, rank: 0), ctx, seeded());
      final tail = scoreCandidate(_guest(2, rank: 15), ctx, seeded());
      expect(top, greaterThan(tail));
    });

    test('совпадение с жанрами сидов поднимает, но не бесконечно', () {
      final ctx = _ctx(seedGenres: {'techno', 'house', 'ambient', 'dub'});
      final none = scoreCandidate(_guest(1), ctx, seeded());
      final three = scoreCandidate(
        _guest(2, genres: ['techno', 'house', 'ambient']),
        ctx,
        seeded(),
      );
      final four = scoreCandidate(
        _guest(3, genres: ['techno', 'house', 'ambient', 'dub']),
        ctx,
        seeded(),
      );
      expect(three, greaterThan(none));
      // Потолок в три совпадения: иначе один жанр забирает всю пачку.
      expect(four, three);
    });

    test('артист, зашедший в этом сеансе, поднимается', () {
      final session = WaveSession(
        mode: WaveMode.personal,
        seeds: const [],
        startedAt: 0,
        artistBonus: {'liked': 6},
      );
      final ctx = _ctx(session: session);
      final boosted = scoreCandidate(_guest(1, artist: 'Liked'), ctx, seeded());
      final plain = scoreCandidate(_guest(2, artist: 'Other'), ctx, seeded());
      expect(boosted - plain, closeTo(6, 0.001));
    });

    test('пролистанный артист опускается', () {
      final session = WaveSession(
        mode: WaveMode.personal,
        seeds: const [],
        startedAt: 0,
        artistBonus: {'skipped': -4},
      );
      final ctx = _ctx(session: session);
      final down = scoreCandidate(_guest(1, artist: 'Skipped'), ctx, seeded());
      final plain = scoreCandidate(_guest(2, artist: 'Other'), ctx, seeded());
      expect(down, lessThan(plain));
    });
  });

  group('antiClumpByArtist', () {
    test('больше двух треков артиста в пачку не идут', () {
      final ranked = [
        for (var i = 0; i < 5; i++) _guest(i, artist: 'Same', rank: i),
      ];
      final out = antiClumpByArtist(ranked);
      // Хвост не выбрасываем — он резерв для следующей пачки.
      expect(out.length, 5);
      expect(out.take(2).every((c) => c.artistKey == 'same'), isTrue);
    });

    test('два трека одного артиста подряд не стоят', () {
      final ranked = [
        _guest(1, artist: 'A'),
        _guest(2, artist: 'A'),
        _guest(3, artist: 'B'),
      ];
      final out = antiClumpByArtist(ranked);
      for (var i = 1; i < out.length; i++) {
        if (out[i].artistKey.isEmpty) continue;
        expect(out[i].artistKey == out[i - 1].artistKey, isFalse);
      }
    });

    test('один жанр не занимает пачку целиком', () {
      final ranked = [
        for (var i = 0; i < 10; i++)
          _guest(i, artist: 'A$i', genres: const ['techno']),
        for (var i = 10; i < 13; i++)
          _guest(i, artist: 'B$i', genres: const ['ambient']),
      ];
      final out = antiClumpByArtist(ranked);
      final head = out.take(6).toList();
      final techno = head.where((c) => c.genres.first == 'techno').length;
      expect(techno, lessThanOrEqualTo(4));
    });
  });

  group('interleaveFamiliar', () {
    test('знакомое идёт через четверых незнакомых, а не подряд', () {
      final ranked = [
        for (var i = 0; i < 8; i++) _guest(i),
        for (var i = 100; i < 104; i++)
          candidateFromLibrary(_track('sc_$i'), i),
      ];
      final out = interleaveFamiliar(ranked);
      expect(out.length, 12);
      // Пятый и десятый — библиотечные (шаг 4 гостя : 1 знакомый).
      expect(out[4].isLibrary, isTrue);
      expect(out[9].isLibrary, isTrue);
      expect(out[0].isLibrary, isFalse);
    });

    test('знакомые кончились — дальше идут одни гости', () {
      final ranked = [
        for (var i = 0; i < 6; i++) _guest(i),
        candidateFromLibrary(_track('sc_100'), 0),
      ];
      final out = interleaveFamiliar(ranked);
      expect(out.length, 7);
      expect(out.where((c) => c.isLibrary).length, 1);
    });
  });

  group('classifyCompletion', () {
    const total = Duration(minutes: 3);

    test('ушёл в первые секунды — пролистнул', () {
      expect(
        classifyCompletion(const Duration(seconds: 5), total),
        WaveVerdict.skip,
      );
    });

    test('дослушал до конца — понравилось', () {
      expect(
        classifyCompletion(const Duration(seconds: 170), total),
        WaveVerdict.finish,
      );
    });

    test('послушал половину — сигнала нет', () {
      expect(
        classifyCompletion(const Duration(seconds: 90), total),
        WaveVerdict.neutral,
      );
    });

    test('длинный трек: минута — ещё не оценка, но и не скип', () {
      // Порог по секундам и порог по доле работают вместе: у получасового
      // микса первая минута мала по доле, но слушали его всё-таки не мельком.
      expect(
        classifyCompletion(
          const Duration(seconds: 60),
          const Duration(minutes: 30),
        ),
        WaveVerdict.neutral,
      );
    });

    test('длительности нет — судить не по чему', () {
      expect(
        classifyCompletion(const Duration(seconds: 30), Duration.zero),
        WaveVerdict.neutral,
      );
    });
  });
}
