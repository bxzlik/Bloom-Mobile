/// Фильтры и скоринг кандидатов — порт `src/wave/scoring.ts`.
///
/// Всё здесь — чистые функции над снимком состояния ([WaveFilterCtx]): именно
/// они решают, что человек услышит, и проверять их надо списком, а не на слух.
library;

import 'dart:math';

import '../../core/entities/entities.dart';
import '../../providers/soundcloud/models.dart';
import '../../providers/soundcloud/sc_provider.dart' show trackFromSc;
import 'wave_types.dart';

/// Что площадка разрешает играть. `BLOCK` и `SNIP` (тридцатисекундный отрывок)
/// в волну не пускаем: они звучат как поломка, а не как рекомендация.
const Set<String> _kAllowedPolicies = {'ALLOW', 'MONETIZE'};

/// Кандидат из выдачи SoundCloud. `null` — трек заведомо не заиграет.
WaveCandidate? candidateFromSc(
  ScRawTrack raw,
  WaveOrigin origin,
  int sourceRank,
) {
  final policy = raw.policy;
  if (policy != null &&
      policy.isNotEmpty &&
      !_kAllowedPolicies.contains(policy)) {
    return null;
  }
  return WaveCandidate(
    track: trackFromSc(raw),
    origin: origin,
    sourceRank: sourceRank,
    artistKey: normalizeArtist(raw.artist),
    // Теги площадки — такой же вкусовой сигнал, как жанр, и для скоринга
    // берутся наравне с ним (в сам [Track] они не идут, см. `wave_types`).
    genres: [
      if (raw.genre != null && raw.genre!.isNotEmpty) raw.genre!.toLowerCase(),
      for (final tag in raw.tags) tag.toLowerCase(),
    ],
  );
}

/// Знакомый трек из библиотеки, подмешиваемый в «Мою волну».
WaveCandidate candidateFromLibrary(Track track, int sourceRank) =>
    WaveCandidate(
      track: track,
      origin: WaveOrigin.library,
      sourceRank: sourceRank,
      artistKey: normalizeArtist(track.artist),
      genres: [for (final g in track.genres) g.toLowerCase()],
    );

/// Снимок состояния, по которому кандидаты отсеиваются и ранжируются.
class WaveFilterCtx {
  const WaveFilterCtx({
    required this.seedGenres,
    required this.session,
    required this.queueIds,
    required this.disliked,
    required this.inLibrary,
    required this.favIds,
    required this.wasShown,
    required this.recentlyPlayed,
    this.currentId,
    this.dropRecentDays = 7,
    this.relaxed = false,
  });

  /// Жанровый отпечаток сидов — с ним и сверяются кандидаты.
  final Set<String> seedGenres;
  final WaveSession session;

  /// id того, что уже стоит в очереди, — дублей не ставим.
  final Set<String> queueIds;
  final Set<String> disliked;

  /// id треков библиотеки: свежий кандидат площадки, который там уже есть, в
  /// «Мою волну» попадает только явным подмешиванием.
  final Set<String> inLibrary;
  final Set<String> favIds;

  final bool Function(String trackId) wasShown;
  final bool Function(String trackId, int days) recentlyPlayed;

  final String? currentId;
  final int dropRecentDays;

  /// Ослабленный проход: без «недавно слушали» и «уже показывали». Нужен как
  /// запасной, когда строгий отсёк вообще всё, — иначе человек с обжитой
  /// библиотекой получает глухое «ничего не нашлось» навсегда.
  final bool relaxed;

  WaveFilterCtx relax() => WaveFilterCtx(
    seedGenres: seedGenres,
    session: session,
    queueIds: queueIds,
    disliked: disliked,
    inLibrary: inLibrary,
    favIds: favIds,
    wasShown: wasShown,
    recentlyPlayed: recentlyPlayed,
    currentId: currentId,
    dropRecentDays: dropRecentDays,
    relaxed: true,
  );
}

bool passesFilters(WaveCandidate c, WaveFilterCtx ctx) {
  if (c.id == ctx.currentId) return false;
  if (ctx.session.playedIds.contains(c.id)) return false;
  if (ctx.queueIds.contains(c.id)) return false;

  // Дизлайк — метка самого трека; артист от неё не страдает.
  if (ctx.disliked.contains(c.id)) return false;

  // Свежий кандидат площадки, который уже лежит в библиотеке, — не «находка».
  // Знакомое попадает в волну ровно одним путём — явным подмешиванием, иначе
  // оно течёт туда дважды и доля незнакомого молча падает.
  if (!c.isLibrary && ctx.inLibrary.contains(c.id)) return false;

  if (!ctx.relaxed && ctx.recentlyPlayed(c.id, ctx.dropRecentDays)) {
    return false;
  }

  // Уже мелькало в волне — не повторяемся, даже если человек его не дослушал.
  // К подмешанным знакомым это не относится: там своя ротация.
  if (!ctx.relaxed && !c.isLibrary && ctx.wasShown(c.id)) return false;

  return true;
}

/// Чем больше, тем выше кандидат в пачке.
double scoreCandidate(WaveCandidate c, WaveFilterCtx ctx, Random rnd) {
  // База — оценка самой площадки: верх её выдачи получает +20, хвост уходит в
  // минус.
  var score = 20 - c.sourceRank.toDouble();

  // Совпадение с жанрами сидов, но не больше трёх: дальше это уже не «в тему»,
  // а один и тот же жанр на всю пачку.
  var matched = 0;
  for (final g in c.genres) {
    if (ctx.seedGenres.contains(g)) matched++;
  }
  score += min(matched, 3) * 4;

  // Лайкнутое в библиотеке — знакомое и желанное.
  if (ctx.favIds.contains(c.id)) score += 8;

  // Что человек уже одобрил В ЭТОМ сеансе (дослушал, сохранил) — см.
  // `wave_feedback`.
  final bonus = ctx.session.artistBonus[c.artistKey];
  if (bonus != null) score += min(bonus, 12);

  // Лёгкий перевес незнакомому: волна за тем и нужна.
  if (!c.isLibrary) score += 1;

  // Немного случайности — иначе порядок пачки предсказуем до трека.
  score += rnd.nextDouble() * 2;

  return score;
}

/// Максимум треков одного артиста на пачку.
const int _kMaxPerArtist = 2;

/// Доля пачки, которую может занять один жанр.
const double _kMaxGenreRatio = 0.3;

/// Разрядить пачку: подряд идущие треки одного артиста и жанровый перекос
/// уезжают в хвост — оттуда они попадут в следующую пачку, а не пропадут.
List<WaveCandidate> antiClumpByArtist(List<WaveCandidate> ranked) {
  final maxPerGenre = max(2, (ranked.length * _kMaxGenreRatio).ceil());

  final out = <WaveCandidate>[];
  final tail = <WaveCandidate>[];
  final artistCount = <String, int>{};
  final genreCount = <String, int>{};
  var lastArtist = '';

  for (final c in ranked) {
    final key = c.artistKey;
    final seenOfArtist = key.isEmpty ? 0 : (artistCount[key] ?? 0);
    if (key.isNotEmpty &&
        (seenOfArtist >= _kMaxPerArtist || key == lastArtist)) {
      tail.add(c);
      continue;
    }
    final primaryGenre = c.genres.isEmpty ? '' : c.genres.first;
    if (primaryGenre.isNotEmpty) {
      final seenOfGenre = genreCount[primaryGenre] ?? 0;
      if (seenOfGenre >= maxPerGenre) {
        tail.add(c);
        continue;
      }
      genreCount[primaryGenre] = seenOfGenre + 1;
    }
    out.add(c);
    if (key.isNotEmpty) artistCount[key] = seenOfArtist + 1;
    lastArtist = key;
  }
  return [...out, ...tail];
}

/// Чередование гостей и знакомых для «Моей волны»: четыре незнакомых на один
/// библиотечный (≈80/20). Ровно в этом и состоит обещание волны — узнавание
/// изредка, а не пополам.
List<WaveCandidate> interleaveFamiliar(List<WaveCandidate> ranked) {
  final guests = [
    for (final c in ranked)
      if (!c.isLibrary) c,
  ];
  final familiar = [
    for (final c in ranked)
      if (c.isLibrary) c,
  ];
  final out = <WaveCandidate>[];
  var gi = 0, fi = 0, step = 0;
  while (gi < guests.length || fi < familiar.length) {
    final wantFamiliar = step % 5 == 4;
    if (wantFamiliar && fi < familiar.length) {
      out.add(familiar[fi++]);
    } else if (gi < guests.length) {
      out.add(guests[gi++]);
    } else if (fi < familiar.length) {
      out.add(familiar[fi++]);
    }
    step++;
  }
  return out;
}
