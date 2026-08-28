/// Числа и время «Итогов» — порт десктопного `features/wrapped/lib/fmt.ts`.
///
/// На ПК склонения считает свой `ruForm` (общего plural-хелпера там нет); у нас
/// формы живут прямо в ARB (`{count, plural, …}`), поэтому от десктопного файла
/// остаётся только сборка фраз.
library;

import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';

/// Время прослушивания: «12 часов 34 минуты», «45 минут», «меньше минуты».
///
/// Секунды не показываем — это оценка, а не секундомер (см. `wrapped_data.dart`).
String fmtListenTime(AppLocalizations l, int seconds) {
  final totalMin = (seconds / 60).round();
  if (totalMin < 1) return l.wrTimeLessThanMin;
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h == 0) return l.wrMinutesN(m);
  if (m == 0) return l.wrHoursN(h);
  return '${l.wrHoursN(h)} ${l.wrMinutesN(m)}';
}

/// «14:00 — 15:00» для любимого часа.
String fmtHourRange(AppLocalizations l, int hour) => l.wrHourRange(
  '${hour.toString().padLeft(2, '0')}:00',
  '${((hour + 1) % 24).toString().padLeft(2, '0')}:00',
);

/// Число с разделителями разрядов на языке интерфейса.
String fmtCount(String locale, int n) =>
    NumberFormat.decimalPattern(locale).format(n);
