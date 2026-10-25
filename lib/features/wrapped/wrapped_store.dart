/// Настройки «Итогов» и сборка того, что показывать сегодня.
///
/// Тумблеры — порт `wrappedShow`/`wrappedAlways` из десктопного `uiPrefsStore`,
/// отметки просмотра — порт `bloom_wrapped_seen` из `localStorage`. Всё лежит в
/// `bloom.json` под ключом `wrapped` (сам журнал — в своём файле, см.
/// [PlayLogController]).
///
/// [wrappedEntriesProvider] — порт десктопного `wrappedDataStore`: он один
/// отвечает всем входам (подменённая карточка статистики, кнопка в шторке
/// статистики, плашка года), потому что вопрос у них общий. Пустой период — это
/// отсутствие итогов: ни карточки, ни кнопки, ни плашки. Никаких заглушек
/// «пока пусто» — как и на ПК, входа просто не существует.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart';
import '../../core/store/stats_store.dart' show dayKey;
import 'periods.dart';
import '../../core/store/play_log.dart';
import 'wrapped_data.dart';

@immutable
class WrappedPrefs {
  const WrappedPrefs({
    this.show = true,
    this.always = false,
    this.seen = const {},
    this.notified = const {},
  });

  /// Показывать входы в «Итоги» вообще.
  final bool show;

  /// Не ждать декабря — показывать итоги года в любой день, а месяцем считать
  /// идущий (см. [periodRange]).
  final bool always;

  /// Вид периода → ключ последнего просмотренного ([periodKey]).
  final Map<String, String> seen;

  /// Вид периода → ключ того, про который уже кидали уведомление.
  ///
  /// Список уведомлений живёт только сессию, а отметка — на диске: иначе
  /// перезапуск приложения в тот же день звенел бы повторно.
  final Map<String, String> notified;

  WrappedPrefs copyWith({
    bool? show,
    bool? always,
    Map<String, String>? seen,
    Map<String, String>? notified,
  }) => WrappedPrefs(
    show: show ?? this.show,
    always: always ?? this.always,
    seen: seen ?? this.seen,
    notified: notified ?? this.notified,
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
    return WrappedPrefs(
      show: raw['show'] as bool? ?? true,
      always: raw['always'] as bool? ?? false,
      seen: _marks(raw['seen']),
      notified: _marks(raw['notified']),
    );
  }

  /// Карта «вид периода → ключ». Чужие типы в файле молча выбрасываем: отметки
  /// не данные, потерять их не страшно.
  static Map<String, String> _marks(Object? raw) => raw is Map
      ? {
          for (final e in raw.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
        }
      : const {};

  void _save() => _store.write('wrapped', {
    'show': state.show,
    'always': state.always,
    'seen': state.seen,
    'notified': state.notified,
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

  bool isNotified(PeriodRange range) =>
      state.notified[range.kind.id] == periodKey(range);

  void markNotified(PeriodRange range) {
    if (isNotified(range)) return;
    state = state.copyWith(
      notified: {...state.notified, range.kind.id: periodKey(range)},
    );
    _save();
  }
}

/// «Сегодня» глазами «Итогов».
///
/// Отдельным провайдером, потому что приложение может провисеть открытым до
/// 1-го числа: экран сверяет дату по возврату из фона и двигает эту метку, а от
/// неё пересчитываются и период месяца, и окно года. На ПК ту же роль играет
/// слушатель `focus` у окна.
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

/// Что показывать входам прямо сейчас — порт десктопного `useWrappedEntries`.
@immutable
class WrappedEntries {
  const WrappedEntries({
    this.month,
    this.year,
    this.monthUnseen = false,
    this.monthHint = false,
    this.yearUnseen = false,
  });

  /// Итоги прошедшего месяца — есть всегда, когда в нём что-то играло.
  final WrappedData? month;

  /// Итоги года — ТОЛЬКО в декабрьском окне и только если есть данные.
  final WrappedData? year;

  /// Месяц ещё не смотрели: карточка статистики в профиле подменяется входом в
  /// итоги. После просмотра она возвращается на место до следующего месяца.
  final bool monthUnseen;

  /// Первая неделя месяца: карточка статистики чередует своё число с надписью
  /// «Итоги месяца». Работает и ПОСЛЕ просмотра — это подсказка, а не вход:
  /// нажатие по карточке всё так же открывает статистику.
  final bool monthHint;

  /// Год ещё не смотрели — метка «Новое» на плашке.
  final bool yearUnseen;

  bool get isEmpty => month == null && year == null;
}

const WrappedEntries _noEntries = WrappedEntries();

final wrappedEntriesProvider = Provider<WrappedEntries>((ref) {
  final prefs = ref.watch(wrappedPrefsProvider);
  if (!prefs.show) return _noEntries;

  // Метку суток читаем ДО периодов: она и есть повод пересчитаться.
  ref.watch(wrappedDayProvider);
  final now = ref.watch(playLogClockProvider)();

  final log = ref.watch(playLogProvider);
  if (log.isEmpty) return _noEntries;

  // «Показывать всегда» — девтулза, и тумблера в релизе нет (см. группу
  // «ИТОГИ · DEBUG» в `appearance_screen.dart`). Там флаг обязан молчать, даже
  // если остался включённым в файле от отладочной сборки: иначе плашка года
  // висела бы в профиле круглый год.
  final force = prefs.always && kDebugMode;

  WrappedData? built(PeriodKind kind) {
    final data = buildWrapped(log, periodRange(kind, now, force));
    // Пусто — итогов этого периода не существует.
    return data.isEmpty ? null : data;
  }

  final month = built(PeriodKind.month);
  final year = inYearWindow(now, force: force) ? built(PeriodKind.year) : null;

  bool unseen(WrappedData? data) =>
      data != null && prefs.seen[data.range.kind.id] != periodKey(data.range);

  return WrappedEntries(
    month: month,
    year: year,
    monthUnseen: unseen(month),
    monthHint: month != null && inMonthHintWindow(now, force: force),
    yearUnseen: unseen(year),
  );
});
