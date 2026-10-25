/// Статистика прослушиваний: «сколько раз» и «когда в последний раз» — свёртка
/// журнала [PlayLog] (на ПК — запросы `PlayLog::stats/top/history`).
///
/// Единственный источник для всего, что опирается на слушание: «История»,
/// статистика профиля и достижения, сиды волны и главной, сортировка «по
/// прослушиваниям». Считается целиком заново на каждое прослушивание: сотня
/// тысяч событий сворачивается за миллисекунды, а синхронные ответы нужны из
/// горячих мест — компаратора сортировки и фильтра волны.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entities/entities.dart';
import 'play_log.dart';

const int _dayMs = 24 * 3600 * 1000;

/// Трек в топе прослушиваний.
@immutable
class TopPlayed {
  const TopPlayed(this.id, this.plays, this.lastTs, this.firstTs);

  final String id;
  final int plays;
  final int lastTs;

  /// Первое прослушивание — по нему считается разброс дней в статистике.
  final int firstTs;
}

/// Строка списка «История».
@immutable
class HistoryRow {
  const HistoryRow(this.id, this.at, this.count);

  final String id;

  /// Последнее прослушивание.
  final int at;

  /// Сколько раз.
  final int count;
}

/// Индекс первого элемента `>= x`.
int _lowerBound(List<int> arr, int x) {
  var lo = 0;
  var hi = arr.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (arr[mid] < x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

class PlayStats {
  PlayStats._(this._plays, this.tracks);

  factory PlayStats.build(PlayLog log) {
    final byTrack = <String, List<int>>{};
    // События журнала уже по возрастанию — массивы выходят отсортированными.
    for (final e in log.events) {
      (byTrack[e.id] ??= []).add(e.ts);
    }
    return PlayStats._(byTrack, log.tracks);
  }

  static final PlayStats empty = PlayStats._(const {}, const {});

  /// id → моменты прослушиваний по возрастанию.
  final Map<String, List<int>> _plays;

  /// Снимки игранных треков — по ним строка «Истории» живёт и после того, как
  /// сам трек ушёл из библиотеки.
  final Map<String, Track> tracks;

  /// Сколько раз слушали трек.
  int playCount(String id) => _plays[id]?.length ?? 0;

  /// Когда трек звучал последний раз (0 — ни разу).
  int lastPlayedAt(String id) => _plays[id]?.last ?? 0;

  /// Звучал ли трек за последние [days] дней.
  bool recentlyPlayed(String id, int days, {DateTime? now}) {
    final last = lastPlayedAt(id);
    if (last <= 0) return false;
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return at - last < days * _dayMs;
  }

  /// Все когда-либо звучавшие треки, без сортировки и отсечек — для сумм
  /// профиля, которым нужен весь объём, а не верхушка.
  List<TopPlayed> allPlayed() => [
    for (final e in _plays.entries)
      TopPlayed(e.key, e.value.length, e.value.last, e.value.first),
  ];

  /// Самое слушаемое: больше прослушиваний выше, при равенстве свежее.
  /// [sinceDays] сужает окно — «топ за три месяца» отражает нынешний вкус.
  List<TopPlayed> topPlayed({
    int? sinceDays,
    int limit = 20,
    int minPlays = 1,
    DateTime? now,
  }) {
    final since = sinceDays == null
        ? 0
        : (now ?? DateTime.now()).millisecondsSinceEpoch - sinceDays * _dayMs;
    final rows = <TopPlayed>[
      for (final e in _plays.entries)
        if (e.value.length - _lowerBound(e.value, since) case final plays
            when plays >= minPlays)
          TopPlayed(e.key, plays, e.value.last, e.value.first),
    ]..sort(_byPlaysThenFresh);
    return rows.take(limit).toList();
  }

  /// Ряды «Истории», свежие сверху. Из истории ничего не убирается — она
  /// показывает журнал целиком, как на ПК.
  List<HistoryRow> historyRows() => [
    for (final e in _plays.entries)
      HistoryRow(e.key, e.value.last, e.value.length),
  ]..sort((a, b) => b.at.compareTo(a.at));
}

int _byPlaysThenFresh(TopPlayed a, TopPlayed b) => a.plays != b.plays
    ? b.plays.compareTo(a.plays)
    : b.lastTs.compareTo(a.lastTs);

final playStatsProvider = Provider<PlayStats>(
  (ref) => PlayStats.build(ref.watch(playLogProvider)),
);
