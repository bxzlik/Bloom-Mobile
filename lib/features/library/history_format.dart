/// Подписи «Истории» — порт десктопных `historyLabel` и `historyTime`
/// (`features/library/lib/formatCount.ts`).
///
/// Заголовок группы: «Сегодня» / «Вчера» / «N дней назад» / «Неделю назад» /
/// «15 марта». Дни считаются КАЛЕНДАРНЫЕ, а не по 86 400 000 мс: иначе
/// прослушивание в 00:30 попадало бы во «вчера» до самого обеда, а в поясах с
/// переводом часов границы дней уезжают ещё и на час.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';

/// Номер календарного дня — считаем в UTC от той же тройки Y-M-D, чтобы
/// вычитание не зависело от длины местных суток.
int _dayNumber(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// Заголовок группы для записи истории, сделанной в [at].
String historyLabel(BuildContext context, DateTime at, {DateTime? now}) {
  final l = context.l;
  final days = _dayNumber(now ?? DateTime.now()) - _dayNumber(at);
  if (days <= 0) return l.histToday;
  if (days == 1) return l.histYesterday;
  if (days < 7) return l.histDaysAgo(days);
  if (days < 14) return l.histWeekAgo;
  // «15 марта» — без года, как на десктопе: дальше двух недель точная дата
  // важнее, чем «сколько прошло», а год в истории на 200 записей не нужен.
  return DateFormat.MMMMd(
    Localizations.localeOf(context).toString(),
  ).format(at);
}

/// «18:32» у строки истории. Формат берём у Material: он знает и локаль, и
/// системную настройку 12/24 часа — на телефоне это ожидаемее жёстких 24.
String historyTime(BuildContext context, DateTime at) =>
    TimeOfDay.fromDateTime(at).format(context);
