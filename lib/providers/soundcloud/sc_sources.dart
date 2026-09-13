/// Похожие треки SoundCloud с очередью и кэшем — порт `src/wave/sources.ts`
/// (и его переезда в `soundcloud.rs` на ПК в 3.0).
///
/// Поверх [sc.stationTracks] / [sc.relatedTracks] здесь три вещи, без которых
/// частые запросы упираются в 429: последовательная очередь с паузой между
/// запросами, кэш ответов на время сеанса и одна повторная попытка после
/// отлупа. Живёт в слое площадки, а не в волне: теми же источниками пользуются
/// и витрины главной («Для вас», «Похожие на»), а очередь у них обязана быть
/// общей — иначе волна и витрина вместе снова получат 429.
///
/// Пустой список вместо исключения — сознательно: и волна, и витрины опрашивают
/// сиды пачкой, и один упавший запрос не должен рушить весь подбор.
library;

import 'dart:async';

import 'models.dart';
import 'soundcloud.dart' as sc;

const Duration _stationTtl = Duration(minutes: 5);
const Duration _relatedTtl = Duration(minutes: 10);

/// Пауза между исходящими запросами к api-v2.
const Duration _minGap = Duration(milliseconds: 150);

/// Отступ перед повтором, когда SoundCloud ответил «слишком часто».
const Duration _retryDelay = Duration(seconds: 2);

/// Сколько похожих считаем достаточным, чтобы не добирать станцией
/// (десктопный `SIMILAR_ENOUGH`).
const int _similarEnough = 12;

class _CacheEntry {
  _CacheEntry(this.at, this.data);
  final DateTime at;
  final List<ScRawTrack> data;
}

final Map<String, _CacheEntry> _stationCache = {};
final Map<String, _CacheEntry> _relatedCache = {};

/// Хвост очереди запросов: каждый следующий ждёт предыдущего.
Future<void> _queue = Future.value();
DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

/// Провести запрос через общую очередь, выдержав паузу с прошлым.
Future<List<ScRawTrack>> _enqueue(Future<List<ScRawTrack>> Function() fn) {
  final completer = Completer<List<ScRawTrack>>();
  _queue = _queue.then((_) async {
    final gap = _minGap - DateTime.now().difference(_lastRequestAt);
    if (gap > Duration.zero) await Future<void>.delayed(gap);
    _lastRequestAt = DateTime.now();
    try {
      completer.complete(await fn());
    } catch (e, st) {
      completer.completeError(e, st);
    }
  });
  // Ошибка одного запроса не должна оборвать очередь для следующих.
  _queue = _queue.catchError((_) {});
  return completer.future;
}

Future<List<ScRawTrack>> _cached(
  Map<String, _CacheEntry> cache,
  String key,
  Duration ttl,
  Future<List<ScRawTrack>> Function() fetch,
) async {
  final hit = cache[key];
  if (hit != null && DateTime.now().difference(hit.at) < ttl) return hit.data;

  try {
    return _store(cache, key, await _enqueue(fetch));
  } catch (_) {
    // Одна повторная попытка с отступом: чаще всего это отлуп за частоту.
    // Именно на ОШИБКЕ, а не на пустоте: пустой ответ — это «станция
    // кончилась», и ждать две секунды ради того же ответа незачем.
    try {
      await Future<void>.delayed(_retryDelay);
      return _store(cache, key, await _enqueue(fetch));
    } catch (_) {
      return const [];
    }
  }
}

/// Запомнить ответ. Кэшируем только непустой: пустоту иначе пришлось бы ждать
/// весь срок, хотя станция могла просто моргнуть.
List<ScRawTrack> _store(
  Map<String, _CacheEntry> cache,
  String key,
  List<ScRawTrack> data,
) {
  if (data.isNotEmpty) cache[key] = _CacheEntry(DateTime.now(), data);
  return data;
}

/// Треки станции сида со смещением [offset].
Future<List<ScRawTrack>> waveStation(String scTrackId, {int offset = 0}) =>
    _cached(
      _stationCache,
      '$scTrackId@$offset',
      _stationTtl,
      () => sc.stationTracks(scTrackId, offset: offset),
    );

/// Похожие на сид.
Future<List<ScRawTrack>> waveRelated(String scTrackId) => _cached(
  _relatedCache,
  scTrackId,
  _relatedTtl,
  () => sc.relatedTracks(scTrackId),
);

/// Похожие на трек для витрин главной — порт `similar_tracks` из
/// `soundcloud.rs`. Сеть та же, что у волны, со всеми её кэшами и паузами.
///
/// Станция подмешивается, только когда одних related мало: related — это
/// именно «похожие», а станция ближе к радио и разбавляет подборку. Сид и
/// повторы из выдачи убраны: сид и так стоит в топе того, для кого подборка.
Future<List<ScRawTrack>> similarTracks(String scTrackId) async {
  final seed = int.tryParse(scTrackId) ?? 0;
  final seen = <int>{};
  final out = <ScRawTrack>[];
  void take(List<ScRawTrack> raw) {
    for (final t in raw) {
      if (t.id == 0 || t.id == seed || !seen.add(t.id)) continue;
      out.add(t);
    }
  }

  take(await waveRelated(scTrackId));
  if (out.length < _similarEnough) take(await waveStation(scTrackId));
  return out;
}

/// Сбросить кэш — перед стартом новой волны, чтобы она не собралась из тех же
/// ответов, что предыдущая.
void resetWaveSourceCache() {
  _stationCache.clear();
  _relatedCache.clear();
}
