/// Пачка волны из того, что отдали станции, — `Wave::pick` ПК.
///
/// Чистая функция над снимком ([WavePick]): она решает, что человек услышит,
/// и проверять её надо списком, а не на слух. Сеть и постановка в очередь —
/// в `wave_controller`.
library;

import 'dart:math';

import '../../core/entities/entities.dart';
import '../../shared/util/taste.dart';
import '../../shared/util/track_dedup.dart';
import 'wave_types.dart';

/// Сколько треков в пачке.
const int kWaveBatch = 20;

/// Осталось столько впереди — пора просить следующую (у станции Яндекса — 4).
const int kWaveRefillAt = 5;
const int kWaveRefillAtNative = 4;

/// Не больше стольких треков одного артиста в пачке.
const int kWaveMaxPerArtist = 2;

/// Доля своих треков в «Моей волне».
const double kWaveFamiliarShare = 0.2;

/// Слушали за столько дней — снова не предлагаем; показывали за столько — тоже.
const int kWaveRecentDays = 7;
const int kWaveShownDays = 14;

/// Снимок, по которому собирается пачка.
class WavePick {
  WavePick({
    required this.run,
    required this.queue,
    required this.library,
    required this.inLibrary,
    required this.isFav,
    required this.isDisliked,
    required this.playedWithin,
    required this.shown,
    this.currentId,
    Random? random,
  }) : random = random ?? Random();

  final WaveRun? run;

  /// Очередь плеера: что в ней, второй раз не встаёт (ни тем же id, ни
  /// перезаливом).
  final List<Track> queue;
  final String? currentId;

  /// Треки библиотеки — из них «Моя волна» подмешивает свои.
  final List<Track> library;
  final bool Function(String id) inLibrary;
  final bool Function(String id) isFav;
  final bool Function(String id) isDisliked;

  /// Звучал ли трек за последние N дней.
  final bool Function(String id, int days) playedWithin;

  /// Что волна показывала за [kWaveShownDays].
  final Set<String> shown;
  final Random random;
}

/// Пачка из порций станций (по порции на сид). Станция, которая учится сама,
/// сохраняет свой порядок — уходит только то, что уже в очереди или с
/// дизлайком. У остальных: ничего слышанного за неделю, показанного за две или
/// уже лежащего в библиотеке (свои приходят только долей «Моей волны»); дальше
/// по месту в станции, лайкам и тому, чему волна научилась; артист — не больше
/// двух раз и никогда дважды подряд.
List<Track> pickBatch(
  List<List<Track>> pages,
  WavePick ctx, {
  int take = kWaveBatch,
}) {
  final queued = {for (final t in ctx.queue) t.id, ?ctx.currentId};

  final cands = <WaveCandidate>[
    for (final page in pages)
      for (var i = 0; i < page.length; i++)
        WaveCandidate(
          page[i],
          20.0 * i / max(1, page.length),
          artistKeys(page[i]),
        ),
  ];

  final dup = DupGuard();
  for (final t in ctx.queue) {
    dup.add(t);
  }
  final out = <Track>[];
  void fill(Iterable<WaveCandidate> list) {
    for (final c in list) {
      if (out.length >= take) break;
      if (dup.accept(c.track)) out.add(c.track);
    }
  }

  final run = ctx.run;
  if (run != null && run.native) {
    fill(
      cands.where((c) => !queued.contains(c.id) && !ctx.isDisliked(c.id)),
    );
    return out;
  }

  final personal = run?.mode == WaveMode.personal;
  final played = {...?run?.played};
  if (personal) {
    // Доля своих: не слышанных последние три дня.
    final lib = [
      for (final t in ctx.library)
        if (!queued.contains(t.id) &&
            !played.contains(t.id) &&
            !ctx.isDisliked(t.id) &&
            !ctx.playedWithin(t.id, 3))
          t,
    ]..shuffle(ctx.random);
    final familiar = max(1, (take * kWaveFamiliarShare).round()) * 2;
    for (var i = 0; i < familiar && i < lib.length; i++) {
      cands.add(
        WaveCandidate(lib[i], i.toDouble(), artistKeys(lib[i]), library: true),
      );
    }
  }

  bool passes(WaveCandidate c, {required bool relaxed}) {
    final id = c.id;
    if (queued.contains(id) || played.contains(id) || ctx.isDisliked(id)) {
      return false;
    }
    if (!c.library && ctx.inLibrary(id)) return false;
    return relaxed ||
        (!ctx.playedWithin(id, kWaveRecentDays) &&
            (c.library || !ctx.shown.contains(id)));
  }

  var kept = [
    for (final c in cands)
      if (passes(c, relaxed: false)) c,
  ];
  // Всё слышали или показывали недавно: лучше повтор, чем тишина.
  if (kept.isEmpty) {
    kept = [
      for (final c in cands)
        if (passes(c, relaxed: true)) c,
    ];
  }

  for (final c in kept) {
    var s = 20 - c.rank;
    if (ctx.isFav(c.id)) s += 8;
    if (run != null) {
      var b = 0;
      for (final a in c.artists) {
        b += run.bonus[a] ?? 0;
      }
      s += min(b, 12);
    }
    if (!c.library) s += 1;
    c.score = s + ctx.random.nextDouble() * 2;
  }
  // Сортировка устойчивая: `List.sort` в Dart — нет.
  kept = _stableSorted(kept, (a, b) => b.score.compareTo(a.score));

  // «Моя волна»: один свой после каждых четырёх новых.
  if (personal) {
    final fresh = [for (final c in kept) if (!c.library) c];
    final own = [for (final c in kept) if (c.library) c];
    kept = [];
    var f = 0, o = 0;
    for (var step = 0; f < fresh.length || o < own.length; step++) {
      if ((step % 5 == 4 && o < own.length) || f >= fresh.length) {
        kept.add(own[o++]);
      } else {
        kept.add(fresh[f++]);
      }
    }
  }

  // Те, что сверх потолка, ждут в конце — на случай короткой пачки.
  final spaced = <WaveCandidate>[];
  final later = <WaveCandidate>[];
  final cap = ArtistCap(kWaveMaxPerArtist);
  var lastArtists = <String>{};
  for (final c in kept) {
    if (!cap.fits(c.track) || c.artists.any(lastArtists.contains)) {
      later.add(c);
      continue;
    }
    spaced.add(c);
    cap.take(c.track);
    lastArtists = c.artists;
  }
  fill([...spaced, ...later]);
  return out;
}

List<T> _stableSorted<T>(List<T> list, int Function(T, T) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])]
    ..sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final x in indexed) x.$2];
}

/// Сиды поровну по списку: все из ≤8, 8 из ≤15, иначе 10. Каждый сид — запрос
/// или два; больше десяти стартуют медленно и мало что добавляют.
List<T> spreadSeeds<T>(List<T> all) {
  final n = all.length;
  final want = n <= 8
      ? n
      : n <= 15
      ? 8
      : 10;
  if (want >= n) return all;
  return [for (var i = 0; i < want; i++) all[min(n - 1, (i * n / want).round())]];
}
