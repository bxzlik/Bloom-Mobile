/// Настройки «Итогов» и сборка того, что показывать сегодня.
///
/// Тумблеры — порт `wrappedShow`/`wrappedAlways` из десктопного `uiPrefsStore`,
/// отметки просмотра — порт `bloom_wrapped_seen` из `localStorage`. Всё лежит в
/// `bloom.json` под ключом `wrapped` (сам журнал — в своём файле, см.
/// [PlayLogController]).
///
/// [wrappedProvider] отдаёт `null`, когда итогов сегодня нет: окно показа
/// закрыто, тумблер выключен либо за период ничего не слушали. Никаких
/// заглушек «пока пусто» — как и на ПК, пункта просто не существует.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;
import '../../core/store/json_store.dart';
import '../../core/store/stats_store.dart' show dayKey;
import 'periods.dart';
import 'play_log.dart';
import 'wrapped_data.dart';

@immutable
class WrappedPrefs {
  const WrappedPrefs({
    this.show = true,
    this.always = false,
    this.seen = const {},
  });

  /// Показывать вход в «Итоги» вообще.
  final bool show;

  /// Не ждать расписания — открывать итоги в любой день.
  final bool always;

  /// Вид периода → ключ последнего просмотренного ([periodKey]).
  final Map<String, String> seen;

  WrappedPrefs copyWith({
    bool? show,
    bool? always,
    Map<String, String>? seen,
  }) => WrappedPrefs(
    show: show ?? this.show,
    always: always ?? this.always,
    seen: seen ?? this.seen,
  );
}

final wrappedPrefsProvider =
    NotifierProvider<WrappedPrefsController, WrappedPrefs>(
      WrappedPrefsController.new,
    );

class WrappedPrefsController extends Notifier<WrappedPrefs> {
  JsonStore get _store => ref.read(jsonStoreProvider);

  @override
  WrappedPrefs build() {
    final raw = _store.readMap('wrapped');
    final seen = raw['seen'];
    return WrappedPrefs(
      show: raw['show'] as bool? ?? true,
      always: raw['always'] as bool? ?? false,
      seen: seen is Map
          ? {
              for (final e in seen.entries)
                if (e.key is String && e.value is String)
                  e.key as String: e.value as String,
            }
          : const {},
    );
  }

  void _save() => _store.write('wrapped', {
    'show': state.show,
    'always': state.always,
    'seen': state.seen,
  });

  void setShow(bool value) {
    state = state.copyWith(show: value);
    _save();
  }

  void setAlways(bool value) {
    state = state.copyWith(always: value);
    _save();
  }

  bool isSeen(PeriodRange range) =>
      state.seen[range.kind.id] == periodKey(range);

  void markSeen(PeriodRange range) {
    if (isSeen(range)) return;
    state = state.copyWith(
      seen: {...state.seen, range.kind.id: periodKey(range)},
    );
    _save();
  }
}

/// «Сегодня» глазами «Итогов».
///
/// Отдельным провайдером, потому что приложение может провисеть открытым до
/// понедельника: экран сверяет дату по возврату из фона и двигает эту метку,
/// а от неё пересчитывается окно показа. На ПК ту же роль играет слушатель
/// `focus` у окна.
final wrappedDayProvider = NotifierProvider<WrappedDayController, String>(
  WrappedDayController.new,
);

class WrappedDayController extends Notifier<String> {
  @override
  String build() => dayKey(ref.read(playLogClockProvider)());

  /// Сверить дату; вернёт `true`, если сутки сменились.
  bool refresh() {
    final now = dayKey(ref.read(playLogClockProvider)());
    if (now == state) return false;
    state = now;
    return true;
  }
}

@immutable
class WrappedReady {
  const WrappedReady({
    required this.periods,
    required this.data,
    required this.unseen,
  });

  /// Доступные сегодня периоды, в порядке значимости ([kPeriodOrder]).
  final List<PeriodKind> periods;
  final Map<PeriodKind, WrappedData> data;

  /// Есть ли среди них непросмотренные — от этого горит точка на кружке.
  final bool unseen;

  /// Самый значимый период — его название стоит подписью у входа.
  PeriodKind get primary => periods.first;

  WrappedData get primaryData => data[primary]!;
}

/// Что показывать сегодня; `null` — входа в «Итоги» нет.
final wrappedProvider = Provider<WrappedReady?>((ref) {
  final prefs = ref.watch(wrappedPrefsProvider);
  if (!prefs.show) return null;

  // Метку суток читаем ДО расписания: она и есть повод пересчитаться.
  ref.watch(wrappedDayProvider);
  final now = ref.watch(playLogClockProvider)();
  final windows = availablePeriods(now: now, force: prefs.always);
  if (windows.isEmpty) return null;

  final log = ref.watch(playLogProvider);
  if (log.isEmpty) return null;

  final periods = <PeriodKind>[];
  final data = <PeriodKind, WrappedData>{};
  var unseen = false;
  for (final kind in windows) {
    final range = periodRange(kind, now);
    final built = buildWrapped(log, range);
    // Пусто — итогов этого периода не существует.
    if (built.isEmpty) continue;
    periods.add(kind);
    data[kind] = built;
    if (prefs.seen[kind.id] != periodKey(range)) unseen = true;
  }
  if (periods.isEmpty) return null;
  return WrappedReady(periods: periods, data: data, unseen: unseen);
});
