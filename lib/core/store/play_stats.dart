/// Общая статистика прослушиваний: «сколько раз» и «когда в последний раз» —
/// порт десктопного `db/playStats.ts` (3.0).
///
/// Единственный источник правды для всего, что опирается на слушание: список
/// «История», статистика профиля и достижения, сиды волны, сортировка «по
/// прослушиваниям». Раньше каждый считал сам по `LibraryState.history`, а та
/// держала ОДНУ запись на трек с лимитом 200 и вытеснением по давности: трек,
/// отыгранный три сотни раз полгода назад, выпадал вместе со счётчиком, и «топ
/// по прослушиваниям» превращался в «топ среди двух сотен недавних». Здесь
/// читается журнал [PlayLog] — поток событий на 60 000 записей с датами.
///
/// Старая история (ключ `history` в `bloom.json`) больше не пишется, но
/// читается: журнал появился позже неё, и у давнего пользователя часть
/// прослушиваний есть только там.
///
/// **Склейка — не десктопная.** На ПК правило «есть хоть одно событие в
/// журнале — верим только журналу»: складывать нельзя, периоды пересекаются.
/// У нас пересечение известно ТОЧНО: пока история ещё писалась, каждое
/// прослушивание попадало и в неё, и в журнал, а `at` записи — момент
/// последнего из них. Значит, всё, что в журнале до `at`, в счётчике истории
/// уже учтено, и от истории берём только недостающее ([_TrackPlays.extra]).
/// Десктопное правило у нас обрушило бы цифры: журнал моложе истории на
/// месяцы, и трек, послушанный сотню раз до «Итогов» и раз после, стал бы
/// «послушанным один раз».
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_store.dart' show jsonStoreProvider;
import 'play_log.dart';

const int _dayMs = 24 * 3600 * 1000;

/// Зазор между записью истории и событием журнала об ОДНОМ прослушивании: оба
/// пишутся подряд из `_credit` плеера, но каждое своими часами. Два настоящих
/// прослушивания одного трека за столько не случаются.
const int _legacySlackMs = 5000;

/// Ключ старой истории в `bloom.json`.
const String kLegacyHistoryKey = 'history';

/// Запись старой истории: одна на трек, `at` — последнее прослушивание,
/// [count] — сколько всего.
@immutable
class HistoryEntry {
  const HistoryEntry(this.trackId, this.at, {this.count = 1});

  final String trackId;
  final int at;

  /// У записей, сделанных до появления счётчика, он равен единице.
  final int count;

  Map<String, dynamic> toJson() => {'id': trackId, 'at': at, 'n': count};

  static HistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return HistoryEntry(
      id,
      (json['at'] as num?)?.toInt() ?? 0,
      count: (json['n'] as num?)?.toInt() ?? 1,
    );
  }
}

final legacyHistoryProvider =
    NotifierProvider<LegacyHistoryController, List<HistoryEntry>>(
      LegacyHistoryController.new,
    );

/// Старая история — только чтение и две правки, которым без неё не обойтись.
class LegacyHistoryController extends Notifier<List<HistoryEntry>> {
  @override
  List<HistoryEntry> build() => [
    for (final raw in ref.read(jsonStoreProvider).readList(kLegacyHistoryKey))
      ?HistoryEntry.fromJson(raw),
  ];

  /// Смена площадки трека: его прошлые прослушивания переезжают на новый id
  /// вместе с журналом, иначе счётчик остался бы висеть под старым.
  void renameTrack(String oldId, String newId) {
    if (!state.any((h) => h.trackId == oldId)) return;
    state = [
      for (final h in state)
        if (h.trackId == oldId)
          HistoryEntry(newId, h.at, count: h.count)
        else
          h,
    ];
    ref.read(jsonStoreProvider).write(kLegacyHistoryKey, [
      for (final h in state) h.toJson(),
    ]);
  }

  /// Часть «Очистить статистику». Без этого после очистки журнала запасной
  /// источник отвечал бы за ВСЕ треки: сиды волны и цифры профиля жили бы на
  /// статистике, которую человек только что стёр (десктопный `resetPlayStats`
  /// удаляет ключ по той же причине).
  void clear() {
    state = const [];
    ref.read(jsonStoreProvider).removeAll(const [kLegacyHistoryKey]);
  }
}

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

  /// Сколько раз — только по видимой части (спрятанное не в счёт).
  final int count;
}

/// Что человек убрал из «Истории». Не список id, а отметки времени — «прятать
/// всё по момент T»: трек, убранный вчера и снова прослушанный сегодня, сам
/// возвращается в список, потому что новое событие свежее отметки. Список id
/// прятал бы его навсегда.
@immutable
class HistoryHide {
  const HistoryHide({this.before = 0, this.byId = const {}});

  /// «Очистить историю» — один рубеж на всё.
  final int before;

  /// Точечные удаления: id → момент, по который прятать.
  final Map<String, int> byId;

  int cutOf(String id) => math.max(before, byId[id] ?? 0);

  Map<String, dynamic> toJson() => {
    if (before > 0) 'before': before,
    if (byId.isNotEmpty) 'byId': byId,
  };

  static HistoryHide fromJson(Object? json) {
    if (json is! Map) return const HistoryHide();
    final byId = <String, int>{};
    final raw = json['byId'];
    if (raw is Map) {
      raw.forEach((id, at) {
        if (id is String && at is num) byId[id] = at.toInt();
      });
    }
    return HistoryHide(
      before: (json['before'] as num?)?.toInt() ?? 0,
      byId: byId,
    );
  }
}

/// Прослушивания одного трека: события журнала плюс то, что знает о нём одна
/// старая история.
class _TrackPlays {
  _TrackPlays(this.ts, HistoryEntry? legacy)
    : legacyAt = legacy?.at ?? 0,
      extra = legacy == null
          ? 0
          : math.max(
              0,
              legacy.count - _upperBound(ts, legacy.at + _legacySlackMs),
            );

  /// Моменты событий журнала по возрастанию. Бывает пустым — трек известен
  /// только истории.
  final List<int> ts;

  /// Когда трек последний раз попал в старую историю (0 — не попадал).
  final int legacyAt;

  /// Прослушивания из старой истории, которых НЕТ в журнале. Отнесены к
  /// моменту [legacyAt]: точнее старая запись не знает.
  final int extra;

  int get count => ts.length + extra;

  int get last => math.max(ts.isEmpty ? 0 : ts.last, legacyAt);

  int get first {
    final fromLog = ts.isEmpty ? 0 : ts.first;
    if (extra == 0 || legacyAt == 0) return fromLog;
    return fromLog == 0 ? legacyAt : math.min(fromLog, legacyAt);
  }

  /// Прослушивания начиная с [since].
  int countSince(int since) =>
      ts.length - _lowerBound(ts, since) + (legacyAt >= since ? extra : 0);

  /// Прослушивания строго после [cut] — видимая часть в «Истории».
  int countAfter(int cut) => cut <= 0
      ? count
      : ts.length - _upperBound(ts, cut) + (legacyAt > cut ? extra : 0);
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

/// Индекс первого элемента `> x`.
int _upperBound(List<int> arr, int x) {
  var lo = 0;
  var hi = arr.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (arr[mid] <= x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Снимок статистики. Считается целиком заново на каждое засчитанное
/// прослушивание: 60 тысяч событий сворачиваются за миллисекунды, а синхронные
/// ответы нужны из горячих мест — компаратора сортировки и фильтра волны.
class PlayStats {
  PlayStats._(this._plays, this.meta);

  factory PlayStats.build(PlayLog log, List<HistoryEntry> legacy) {
    final byTrack = <String, List<int>>{};
    // События журнала уже по возрастанию — массивы выходят отсортированными.
    for (final e in log.events) {
      (byTrack[e.id] ??= []).add(e.ts);
    }
    // Одна запись на трек — так история и писалась, но файл правили руками,
    // а смена площадки могла свести два id в один.
    final merged = <String, HistoryEntry>{};
    for (final h in legacy) {
      final was = merged[h.trackId];
      merged[h.trackId] = was == null
          ? h
          : HistoryEntry(
              h.trackId,
              math.max(was.at, h.at),
              count: was.count + h.count,
            );
    }
    return PlayStats._({
      for (final id in {...byTrack.keys, ...merged.keys})
        id: _TrackPlays(byTrack[id] ?? const [], merged[id]),
    }, log.meta);
  }

  static final PlayStats empty = PlayStats._(const {}, const {});

  final Map<String, _TrackPlays> _plays;

  /// Снимки треков из журнала — по ним строка «Истории» живёт и после того,
  /// как сам трек ушёл из библиотеки.
  final Map<String, PlayMeta> meta;

  /// Сколько раз слушали трек.
  int playCount(String id) => _plays[id]?.count ?? 0;

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
      if (e.value.count > 0)
        TopPlayed(e.key, e.value.count, e.value.last, e.value.first),
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
        if (e.value.countSince(since) case final plays when plays >= minPlays)
          TopPlayed(e.key, plays, e.value.last, e.value.first),
    ]..sort(_byPlaysThenFresh);
    return rows.take(limit).toList();
  }

  /// Ряды «Истории», свежие сверху. Спрятанное отсекается по [hide], но
  /// статистику скрытие не трогает: история — это список, а не учёт.
  List<HistoryRow> historyRows([HistoryHide hide = const HistoryHide()]) {
    final rows = <HistoryRow>[
      for (final e in _plays.entries)
        if (e.value.countAfter(hide.cutOf(e.key)) case final n when n > 0)
          HistoryRow(e.key, e.value.last, n),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return rows;
  }
}

int _byPlaysThenFresh(TopPlayed a, TopPlayed b) => a.plays != b.plays
    ? b.plays.compareTo(a.plays)
    : b.lastTs.compareTo(a.lastTs);

final playStatsProvider = Provider<PlayStats>(
  (ref) => PlayStats.build(
    ref.watch(playLogProvider),
    ref.watch(legacyHistoryProvider),
  ),
);
