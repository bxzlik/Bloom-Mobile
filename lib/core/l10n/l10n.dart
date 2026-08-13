/// Доступ к переводам.
///
/// Сами строки лежат в `lib/l10n/*.arb` и собираются в `AppLocalizations`
/// кодогенератором (`flutter gen-l10n`, настройки в `l10n.yaml`). Здесь только
/// две удобные точки входа: короткая `context.l` для виджетов и [globalL10n]
/// для того, у чего своего контекста нет.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/bloom_toast.dart';

export '../../l10n/app_localizations.dart' show AppLocalizations;

extension BloomL10n on BuildContext {
  /// Переводы текущей локали. Короткая запись вместо
  /// `AppLocalizations.of(context)` — как `context.bloom` для токенов темы.
  AppLocalizations get l => AppLocalizations.of(this);
}

/// Переводы для кода без `BuildContext` — фоновых тостов и утилит.
///
/// Контекст берётся у глобального мессенджера (`bloomMessengerKey`): он живёт
/// столько же, сколько `MaterialApp`, поэтому строка находится даже когда
/// тост прилетает из таймера авто-обновления, а не с экрана.
///
/// `null` возможен ровно до первого кадра — тогда показывать всё равно некому.
///
/// `currentContext` у `GlobalKey` не просто пуст, а БРОСАЕТ, если биндинг
/// виджетов ещё не поднят — так бывает в юнит-тестах стора, где дерева нет
/// вовсе. Для звонящего это тот же случай «языка взять негде», поэтому ловим
/// и отдаём null.
AppLocalizations? get globalL10n {
  try {
    final context = bloomMessengerKey.currentContext;
    return context == null ? null : AppLocalizations.of(context);
  } on FlutterError {
    return null;
  }
}
