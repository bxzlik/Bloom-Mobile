/// Счётчики статистики профиля — порт десктопных `activityStore` и
/// `usageStore`.
///
/// Два числа, которых нет больше нигде: дневной журнал прослушиваний
/// (`день → сколько треков`) и суммарное время в приложении. Третий счётчик —
/// сколько раз слушали каждый трек — живёт в самой истории
/// ([HistoryEntry.count]), как и на десктопе.
///
/// Ключ дня — ЛОКАЛЬНАЯ дата, а не UTC: «сегодня» в графике должно совпадать с
/// сегодня у пользователя. На десктопе там `toISOString`, и под утро в плюсовых
/// поясах день там уезжает на предыдущий.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_store.dart' show jsonStoreProvider;

/// `YYYY-MM-DD` по локальному времени.
String dayKey(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

@immutable
class StatsState {
  const StatsState({this.activity = const {}, this.appMs = 0});

  /// День → сколько треков в этот день заиграло.
  final Map<String, int> activity;

  /// Сколько времени приложение реально было открыто, миллисекунды.
  final int appMs;

  StatsState copyWith({Map<String, int>? activity, int? appMs}) =>
      StatsState(activity: activity ?? this.activity, appMs: appMs ?? this.appMs);
}

final statsProvider = NotifierProvider<StatsController, StatsState>(
  StatsController.new,
);

class StatsController extends Notifier<StatsState> {
  @override
  StatsState build() {
    final raw = ref.read(jsonStoreProvider).readMap('stats');
    final log = raw['activity'];
    return StatsState(
      activity: log is Map
          ? {
              for (final e in log.entries)
                if (e.key is String && e.value is num)
                  e.key as String: (e.value as num).toInt(),
            }
          : const {},
      appMs: (raw['appMs'] as num?)?.toInt() ?? 0,
    );
  }

  void _save() {
    ref.read(jsonStoreProvider).write('stats', {
      'activity': state.activity,
      'appMs': state.appMs,
    });
  }

  /// Засчитать одно прослушивание в сегодняшний день. Зовётся там же, где
  /// история, — в момент, когда трек реально пошёл играть.
  void addPlay() {
    final key = dayKey(DateTime.now());
    state = state.copyWith(
      activity: {...state.activity, key: (state.activity[key] ?? 0) + 1},
    );
    _save();
  }

  void addUsage(int ms) {
    state = state.copyWith(appMs: state.appMs + ms);
    _save();
  }

  /// Сброс — часть «Очистить статистику».
  void clear() {
    state = const StatsState();
    _save();
  }
}

/// Учёт времени в приложении.
///
/// Тот же приём, что на десктопе: раз в [_beat] берём НАСТОЯЩУЮ дельту часов, а
/// не шаг таймера, и отбрасываем всё, что больше [_maxDelta] — это не работа, а
/// провал (сон устройства, замороженный движок). Плюс жизненный цикл: уходя в
/// фон, добираем хвост, возвращаясь — начинаем отсчёт заново, чтобы время в
/// чужом приложении не попало в наше.
class UsageTracker with WidgetsBindingObserver {
  UsageTracker(this._stats);

  final StatsController _stats;

  static const Duration _beat = Duration(seconds: 20);
  static const int _maxDelta = 90000;

  Timer? _timer;
  int _last = 0;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _last = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer.periodic(_beat, (_) => _flush());
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  void _flush() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = now - _last;
    _last = now;
    if (delta > 0 && delta < _maxDelta) _stats.addUsage(delta);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _last = DateTime.now().millisecondsSinceEpoch;
    } else {
      _flush();
    }
  }
}
