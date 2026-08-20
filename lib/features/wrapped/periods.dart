/// Периоды «Итогов» и расписание их показа — порт десктопного
/// `features/wrapped/lib/periods.ts`.
///
/// Итоги нельзя показывать посреди периода — год ещё не прошёл, неделя не
/// кончилась. Поэтому у каждого периода есть ОКНО показа:
///   неделя — каждый понедельник (итоги прошлой недели, пн–вс);
///   месяц  — 1-е число (итоги прошлого месяца);
///   год    — с 21 по 31 декабря (итоги текущего года).
///
/// Ручки тюнинга — константы ниже. Проверить интерфейс вне окна можно
/// тумблером «Показывать всегда» (`wrapped_store.dart`).
library;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum PeriodKind {
  week('week'),
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

/// День недели окна «недели» — понедельник (как `DateTime.monday`).
const int kWeekWindowWeekday = DateTime.monday;

/// День месяца окна «месяца».
const int kMonthWindowDay = 1;

/// Окно «года»: с 21 по 31 декабря включительно.
const int kYearWindowFromDay = 21;
const int kYearWindowToDay = 31;

/// Порядок «значимости»: год важнее месяца, месяц — недели (1 января доступны
/// все три сразу, и в списке они идут именно так).
const List<PeriodKind> kPeriodOrder = [
  PeriodKind.year,
  PeriodKind.month,
  PeriodKind.week,
];

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

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Понедельник той недели, в которую попадает [d] (локальная полночь).
DateTime _startOfWeek(DateTime d) {
  final s = _startOfDay(d);
  return s.subtract(Duration(days: s.weekday - DateTime.monday));
}

/// Границы периода. Неделя и месяц — ПРОШЕДШИЕ целиком, год — текущий с
/// 1 января по «сейчас» (так же делают Spotify и Яндекс в декабре).
PeriodRange periodRange(PeriodKind kind, [DateTime? now]) {
  final at = now ?? DateTime.now();
  switch (kind) {
    case PeriodKind.week:
      final thisWeek = _startOfWeek(at);
      return PeriodRange(
        kind,
        thisWeek.subtract(const Duration(days: 7)),
        thisWeek,
      );
    case PeriodKind.month:
      return PeriodRange(
        kind,
        DateTime(at.year, at.month - 1, 1),
        DateTime(at.year, at.month, 1),
      );
    case PeriodKind.year:
      return PeriodRange(kind, DateTime(at.year, 1, 1), at);
  }
}

bool _inYearWindow(DateTime now) =>
    now.month == DateTime.december &&
    now.day >= kYearWindowFromDay &&
    now.day <= kYearWindowToDay;

/// Какие итоги «сегодня» уместно показывать. [force] — игнорировать расписание
/// (тумблер «Показывать всегда»).
List<PeriodKind> availablePeriods({DateTime? now, bool force = false}) {
  if (force) return kPeriodOrder;
  final at = now ?? DateTime.now();
  return [
    if (_inYearWindow(at)) PeriodKind.year,
    if (at.day == kMonthWindowDay) PeriodKind.month,
    if (at.weekday == kWeekWindowWeekday) PeriodKind.week,
  ];
}

/// Стабильный ключ периода («2026-W31» / «2026-07» / «2026») — им помечаем
/// просмотренные итоги, чтобы кольцо кружка гасло, как у сторис.
String periodKey(PeriodRange r) {
  final d = r.from;
  switch (r.kind) {
    case PeriodKind.year:
      return '${d.year}';
    case PeriodKind.month:
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    case PeriodKind.week:
      // Номер недели от начала периода (понедельника) — та же формула, что на
      // ПК: ключу нужна не каноничность ISO, а стабильность.
      //
      // Дни считаем по UTC-двойникам дат: разница локальных полуночей через
      // перевод часов даёт 23 либо 25 часов, и `inDays` округлился бы на день
      // вниз — номер недели поехал бы у половины планеты.
      final day = DateTime.utc(d.year, d.month, d.day);
      final jan1 = DateTime.utc(d.year, 1, 1);
      final week = ((day.difference(jan1).inDays + jan1.weekday % 7 + 1) / 7)
          .ceil();
      return '${d.year}-W${week.toString().padLeft(2, '0')}';
  }
}

/// Подпись диапазона: «28 июля — 3 августа» / «Июль 2026» / «2026».
///
/// Месяц идёт с заглавной — это заголовок, а `intl` даёт строчную. Для месяца
/// берём standalone-форму (`LLLL` — «август»), для дат внутри недели —
/// форматную (`MMMM` — «3 августа»): в русском это РАЗНЫЕ слова.
String periodDatesLabel(PeriodRange r, String locale) {
  final from = r.from;
  switch (r.kind) {
    case PeriodKind.year:
      return '${from.year}';
    case PeriodKind.month:
      final mon = DateFormat('LLLL', locale).format(from);
      return '${_capitalize(mon)} ${from.year}';
    case PeriodKind.week:
      // Конец периода не включён: последний ЕГО день — на миллисекунду раньше.
      final to = r.to.subtract(const Duration(milliseconds: 1));
      final full = DateFormat('d MMMM', locale);
      // Внутри одного месяца хватит одного его упоминания: «3 — 9 августа».
      if (from.month == to.month && from.year == to.year) {
        return '${from.day} — ${full.format(to)}';
      }
      return '${full.format(from)} — ${full.format(to)}';
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
