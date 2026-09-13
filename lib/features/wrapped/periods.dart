/// Периоды «Итогов» — порт десктопного `features/wrapped/lib/periods.ts`.
///
/// Недели больше нет: за семь дней не набирается ничего, что стоило бы
/// показывать историей, а напоминание каждый понедельник быстро надоедало.
///
/// Доступность у месяца и года РАЗНАЯ, и это главное правило файла:
///   месяц — доступен ВСЕГДА (кнопка «Итоги месяца» внизу шторки статистики),
///           а пока их не посмотрели, карточка статистики в профиле подменяется
///           входом в итоги прошедшего месяца;
///   год   — только с 21 по 31 декабря: вне окна плашки года просто нет.
///
/// Ручки тюнинга — константы ниже. Проверить год и подмену вне окна можно
/// тумблером «Показывать всегда» (`wrapped_store.dart`): он и есть [force] во
/// всех функциях этого файла.
library;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum PeriodKind {
  month('month'),
  year('year');

  const PeriodKind(this.id);

  /// Ключ в хранилище просмотренного. В интерфейсе не показывается.
  final String id;

  static PeriodKind? byId(String id) {
    for (final k in PeriodKind.values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// Окно «года»: с 21 по 31 декабря включительно.
const int kYearWindowFromDay = 21;
const int kYearWindowToDay = 31;

/// День месяца, в который напоминаем про итоги прошедшего месяца.
const int kMonthWindowDay = 1;

/// Последний день «недели напоминания»: пока идут первые семь чисел, карточка
/// статистики чередует своё число с надписью «Итоги месяца».
const int kMonthHintToDay = 7;

/// Порядок «значимости»: где показаны оба, год идёт первым.
const List<PeriodKind> kPeriodOrder = [PeriodKind.year, PeriodKind.month];

@immutable
class PeriodRange {
  const PeriodRange(this.kind, this.from, this.to);

  final PeriodKind kind;

  /// Начало периода, включительно (локальная полночь).
  final DateTime from;

  /// Конец периода, НЕ включительно.
  final DateTime to;

  int get fromMs => from.millisecondsSinceEpoch;
  int get toMs => to.millisecondsSinceEpoch;
}

/// Границы периода. Месяц — ПРОШЕДШИЙ целиком (цифры окончательные, ничего не
/// дорастёт), год — текущий с 1 января по «сейчас» (так же делают площадки в
/// декабре).
///
/// [force] берёт у месяца ИДУЩИЙ месяц: журнал копится только с обновления,
/// поэтому у прошедшего сплошь и рядом ноль событий — и проверять подмену
/// карточки было бы нечем, итогов месяца просто не существует.
PeriodRange periodRange(PeriodKind kind, [DateTime? now, bool force = false]) {
  final at = now ?? DateTime.now();
  switch (kind) {
    case PeriodKind.month:
      final thisMonth = DateTime(at.year, at.month, 1);
      if (force) return PeriodRange(kind, thisMonth, at);
      return PeriodRange(kind, DateTime(at.year, at.month - 1, 1), thisMonth);
    case PeriodKind.year:
      return PeriodRange(kind, DateTime(at.year, 1, 1), at);
  }
}

/// Идёт ли окно итогов года (21–31 декабря). Вне его плашки года нет вообще.
bool inYearWindow(DateTime now, {bool force = false}) =>
    force ||
    (now.month == DateTime.december &&
        now.day >= kYearWindowFromDay &&
        now.day <= kYearWindowToDay);

/// Идёт ли «неделя напоминания» (1–7 число). В отличие от подмены карточки,
/// она не зависит от просмотра: это подсказка, что итоги никуда не делись.
bool inMonthHintWindow(DateTime now, {bool force = false}) =>
    force || (now.day >= kMonthWindowDay && now.day <= kMonthHintToDay);

/// О каких итогах «сегодня» уместно НАПОМНИТЬ уведомлением.
///
/// У месяца это ровно 1-е число, а не весь месяц, как у подмены карточки:
/// напоминание — событие, а не состояние. Смотреть итоги месяца можно и после,
/// кнопкой внизу шторки статистики.
List<PeriodKind> scheduledPeriods(DateTime now, {bool force = false}) {
  if (force) return kPeriodOrder;
  return [
    if (inYearWindow(now)) PeriodKind.year,
    if (now.day == kMonthWindowDay) PeriodKind.month,
  ];
}

/// Стабильный ключ периода («2026-07» / «2026») — им помечаем просмотренные
/// итоги: по нему карточка статистики понимает, что подменяться уже не нужно.
String periodKey(PeriodRange r) {
  final d = r.from;
  return switch (r.kind) {
    PeriodKind.year => '${d.year}',
    PeriodKind.month => '${d.year}-${d.month.toString().padLeft(2, '0')}',
  };
}

/// Подпись диапазона: «Июль 2026» / «2026».
///
/// Месяц идёт с заглавной — это заголовок, а `intl` даёт строчную, и форма у
/// него standalone (`LLLL` — «август», не «августа»).
String periodDatesLabel(PeriodRange r, String locale) {
  final from = r.from;
  if (r.kind == PeriodKind.year) return '${from.year}';
  final mon = DateFormat('LLLL', locale).format(from);
  return '${_capitalize(mon)} ${from.year}';
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
