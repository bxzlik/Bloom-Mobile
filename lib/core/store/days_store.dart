/// Дни, в которые Bloom был открыт, и время в приложении за каждый — таблица
/// `days` базы (на ПК — та же таблица, пишет `Stats::start/flush`).
///
/// Прослушивания по дням здесь не хранятся: они выводятся из журнала
/// ([PlayStats.perDay]). Отсюда — только визиты (для уровня: день засчитан,
/// если приложение открывали или что-то слушали) и `app_ms` (достижение
/// «Ветеран» и «время в приложении» в статистике).
///
/// Ключ дня — ЛОКАЛЬНАЯ дата `YYYY-MM-DD`, как `QDate::currentDate()` на ПК:
/// «сегодня» в графике совпадает с сегодня у слушателя.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../log/bloom_log.dart';
import 'play_log.dart' show playLogClockProvider;

/// `YYYY-MM-DD` по локальному времени.
String dayKey(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

@immutable
class DaysState {
  const DaysState({this.visited = const {}, this.appMs = 0});

  /// Дни, в которые приложение открывали.
  final Set<String> visited;

  /// Сколько времени приложение было открыто за всё время, миллисекунды.
  final int appMs;
}

final daysProvider = NotifierProvider<DaysController, DaysState>(
  DaysController.new,
);

class DaysController extends Notifier<DaysState> {
  BloomDb get _db => ref.read(dbProvider);

  String _today() => dayKey(ref.read(playLogClockProvider)());

  @override
  DaysState build() => _read();

  DaysState _read() {
    final rows = _db.select('SELECT day, app_ms FROM days');
    var ms = 0;
    for (final r in rows) {
      ms += r['app_ms'] as int;
    }
    return DaysState(
      visited: {for (final r in rows) r['day'] as String},
      appMs: ms,
    );
  }

  /// Сегодняшний визит — на запуске и по возвращении из фона (могла
  /// смениться дата).
  void visit() {
    final today = _today();
    if (state.visited.contains(today)) return;
    _db.exec('INSERT OR IGNORE INTO days (day) VALUES (?)', [today]);
    state = DaysState(visited: {...state.visited, today}, appMs: state.appMs);
  }

  /// Прибавить время в приложении к сегодняшнему дню.
  void addUsage(int ms) {
    final today = _today();
    _db.exec(
      'INSERT INTO days (day, app_ms) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET app_ms = app_ms + excluded.app_ms',
      [today, ms],
    );
    state = DaysState(
      visited: state.visited.contains(today)
          ? state.visited
          : {...state.visited, today},
      appMs: state.appMs + ms,
    );
  }

  /// Часть «Очистить статистику»: дни уходят, сегодняшний визит остаётся —
  /// приложение ведь открыто.
  void clear() {
    final today = _today();
    _db.tx(() {
      _db.exec('DELETE FROM days');
      _db.exec('INSERT INTO days (day) VALUES (?)', [today]);
    });
    state = DaysState(visited: {today});
  }
}

/// Учёт времени в приложении.
///
/// Раз в [_beat] берём НАСТОЯЩУЮ дельту часов, а не шаг таймера, и
/// отбрасываем всё, что больше [_maxDelta] — это не работа, а провал (сон
/// устройства, замороженный движок). Плюс жизненный цикл: уходя в фон,
/// добираем хвост, возвращаясь — начинаем отсчёт заново, чтобы время в чужом
/// приложении не попало в наше.
class UsageTracker with WidgetsBindingObserver {
  UsageTracker(this._days);

  final DaysController _days;

  static const Duration _beat = Duration(seconds: 20);
  static const int _maxDelta = 90000;

  Timer? _timer;
  int _last = 0;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _days.visit();
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
    if (delta > 0 && delta < _maxDelta) _days.addUsage(delta);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Заодно единственная на весь процесс точка, откуда виден жизненный цикл, —
    // пишем его в журнал. Без этого по логу нельзя отличить «человек вышел сам»
    // от «система убила приложение на ходу», а разбор сбоя запуска держится
    // именно на этом. Уходя из активного состояния, сбрасываем журнал на диск:
    // из фона процесс убивают без предупреждения, и отложенная запись не
    // доехала бы.
    logInfo('app', 'состояние: ${state.name}');
    if (state != AppLifecycleState.resumed) {
      unawaited(BloomLog.instance.flush());
    }
    if (state == AppLifecycleState.resumed) {
      _days.visit();
      _last = DateTime.now().millisecondsSinceEpoch;
    } else {
      _flush();
    }
  }
}
