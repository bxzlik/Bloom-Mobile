/// Форматирование длительностей, чисел и дат релиза.
library;

import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

String mmss(Duration d) {
  final s = d.inSeconds.clamp(0, 24 * 3600);
  final m = s ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  if (m < 60) return '$m:$sec';
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:$sec';
}

String mmssMs(int ms) => mmss(Duration(milliseconds: ms));

/// Суммарное время списка: «1ч 23м» / «45 мин» — порт `fmtTotalDur` с десктопа.
///
/// Не [mmss]: у сотни треков часы-минуты-секунды читаются как таймкод, а в
/// подписи под названием секунды не нужны вовсе. Меньше минуты — «0 мин»,
/// но звонящий такой список подписывать не обязан.
String totalDur(AppLocalizations l, Duration d) {
  final m = d.inMinutes;
  return m >= 60 ? l.commonDurHm(m ~/ 60, m % 60) : l.commonDurMin(m);
}

/// Короткое число: 1234 → «1.2K», 6700572 → «6.7M».
String compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return '${k < 10 ? k.toStringAsFixed(1) : k.round()}K';
  }
  final m = n / 1000000;
  return '${m < 10 ? m.toStringAsFixed(1) : m.round()}M';
}

/// Полная дата релиза под язык: «2024-05-13T00:00:00Z» → «13 мая 2024» /
/// «May 13, 2024». Площадка отдала один год («2024») или вообще не дату — `null`:
/// звонящему тогда остаётся показать сам год, как он это делал раньше.
///
/// Берём только календарную часть строки: у SoundCloud и Яндекса к дате
/// прицеплено время с часовым поясом, и перевод его в местный сдвинул бы день
/// на сутки — релиз «13 мая 00:00 +03» в Лондоне стал бы двенадцатым.
String? releaseDateLabel(String? raw, String locale) {
  if (raw == null) return null;
  final day = DateTime.tryParse(raw.length > 10 ? raw.substring(0, 10) : raw);
  if (day == null) return null;
  // Русский `yMMMMd` кончается на «г.» — в подписи из трёх кусков через точку
  // это лишний шум, а сам порядок слов («13 мая» против «May 13») нужен родной.
  return DateFormat.yMMMMd(
    locale,
  ).format(day).replaceFirst(RegExp(r'\s*г\.$'), '');
}

/// Короткая дата события из метки времени: «2 сент. 2026 г.» / «Sep 2, 2026».
/// Ею подписаны шапки шторок («Добавлен …», «Создан …»).
///
/// В отличие от [releaseDateLabel] русское «г.» тут остаётся: строка стоит
/// одна, отдельной, и без него читается как обрубок.
String stampDate(int ms, String locale) =>
    DateFormat.yMMMd(locale).format(DateTime.fromMillisecondsSinceEpoch(ms));

// «12 треков» переехало в словарь: ключ `tracksCount` в `lib/l10n/*.arb`
// считает формы через ICU-плюрали, поэтому русская тройка (трек/трека/треков)
// и английская пара живут рядом с остальными строками, а не в коде.
