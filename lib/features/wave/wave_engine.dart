/// Сборка пачки треков — порт `src/wave/engine.ts` (часть, отвечающая за
/// подбор; постановка в очередь живёт в `wave_controller`).
///
/// Порядок ровно десктопный: кандидаты от каждого сида → подмешивание знакомых
/// (только «Моя волна») → фильтры → скоринг → чередование → разрядка по
/// артистам и жанрам → срез до размера пачки.
library;

import 'dart:math';

import '../../core/entities/entities.dart';
import '../../providers/soundcloud/models.dart';
import 'wave_scoring.dart';
import 'wave_seeds.dart';
import 'wave_sources.dart';
import 'wave_store.dart';
import 'wave_types.dart';

/// Сколько треков в пачке.
const int kWaveBatch = 20;

/// Осталось столько треков впереди — пора догружать.
const int kWaveRefillThreshold = 5;

/// Доля знакомого из библиотеки в «Моей волне».
const double _kFamiliarRatio = 0.2;

/// За сколько дней прослушанное считается «недавним» и в выдачу не идёт.
const int _kDropRecentDays = 7;

class WaveEngine {
  WaveEngine({
    required this.view,
    required this.store,
    required this.queueIds,
    this.currentId,
    Random? random,
  }) : _rnd = random ?? Random();

  final WaveLibrary view;
  final WaveStore store;

  /// Что уже стоит в очереди — дублей не подбираем.
  final Set<String> queueIds;
  final String? currentId;
  final Random _rnd;

  /// Собрать пачку. Пустой список — площадка ничего не дала (нет сети, у сидов
  /// нет похожих); вызывающий сам решает, что сказать человеку.
  Future<List<WaveCandidate>> buildBatch({
    required WaveMode mode,
    required List<String> seeds,
    required WaveSession session,
    int takeCount = kWaveBatch,
  }) async {
    final fresh = await _fetchFromSeeds(seeds);

    var pool = fresh;
    if (mode == WaveMode.personal) {
      final exclude = {...session.playedIds, ...queueIds};
      final wanted = max(1, (takeCount * _kFamiliarRatio).round());
      // Берём с запасом: половину съедят фильтры.
      final familiar = pickFamiliarPool(view, exclude, limit: wanted * 2);
      pool = [
        ...fresh,
        for (var i = 0; i < familiar.length; i++)
          candidateFromLibrary(familiar[i], i),
      ];
    }

    final ctx = WaveFilterCtx(
      seedGenres: _seedGenres(seeds),
      session: session,
      queueIds: queueIds,
      disliked: view.disliked,
      inLibrary: view.lib.inLib.keys.toSet(),
      favIds: view.lib.favs.keys.toSet(),
      wasShown: store.wasShown,
      recentlyPlayed: view.recentlyPlayed,
      currentId: currentId,
      dropRecentDays: _kDropRecentDays,
    );

    var filtered = [
      for (final c in pool)
        if (passesFilters(c, ctx)) c,
    ];
    // Строгий проход вырезал всё — пробуем ослабленный, см. [WaveFilterCtx].
    if (filtered.isEmpty) {
      final relaxed = ctx.relax();
      filtered = [
        for (final c in pool)
          if (passesFilters(c, relaxed)) c,
      ];
    }
    if (filtered.isEmpty) return const [];

    // Скор считаем один раз на кандидата: в нём есть случайная добавка, и
    // пересчёт внутри сравнения дал бы несогласованный порядок.
    final scored = [for (final c in filtered) (c, scoreCandidate(c, ctx, _rnd))]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    var ordered = [for (final x in scored) x.$1];

    if (mode == WaveMode.personal) ordered = interleaveFamiliar(ordered);
    return antiClumpByArtist(ordered).take(takeCount).toList();
  }

  /// Опросить станцию и похожие у каждого сида. Курсор станции двигаем только
  /// у тех сидов, что реально что-то отдали, — иначе он «уплывает» и следующая
  /// попытка тянет из заведомо пустого диапазона.
  Future<List<WaveCandidate>> _fetchFromSeeds(List<String> seeds) async {
    final out = <WaveCandidate>[];
    final seen = <String>{};

    void take(List<ScRawTrack> raws, WaveOrigin origin) {
      for (var i = 0; i < raws.length; i++) {
        final c = candidateFromSc(raws[i], origin, i);
        if (c == null || !seen.add(c.id)) continue;
        out.add(c);
      }
    }

    for (final seedId in seeds) {
      final scId = scIdOf(view.byId(seedId));
      if (scId == null) continue;

      final offset = store.cursorOf(scId);
      var station = await waveStation(scId, offset: offset);
      // Станция кончилась — начинаем её сначала, чтобы человек не застревал в
      // волне навсегда после долгих сеансов.
      if (station.isEmpty && offset > 0) {
        store.resetCursor(scId);
        station = await waveStation(scId);
      }
      if (station.isNotEmpty) store.advanceCursor(scId);
      take(station, WaveOrigin.station);

      // Похожие дёргаем всегда: они не пагинируются, но для волны по одному
      // треку это главный вкусовой источник — пропустив его на ненулевом
      // смещении, мы потеряли бы половину выдачи.
      take(await waveRelated(scId), WaveOrigin.related);
    }
    return out;
  }

  /// Жанровый отпечаток сидов — с ним сверяются кандидаты в скоринге.
  Set<String> _seedGenres(List<String> seeds) => {
    for (final id in seeds)
      for (final g in view.byId(id)?.genres ?? const <String>[])
        if (g.isNotEmpty) g.toLowerCase(),
  };
}

/// Треки из кандидатов — то, что и уедет в очередь плеера.
List<Track> tracksOf(List<WaveCandidate> batch) => [
  for (final c in batch) c.track,
];
