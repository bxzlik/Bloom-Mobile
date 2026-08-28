/// Запрос разрешения на уведомления (Android 13+).
///
/// Без `POST_NOTIFICATIONS` шторка воспроизведения просто НЕ ПОКАЗЫВАЕТСЯ:
/// служба живёт, звук идёт, а управления нет ни в шторке, ни на экране
/// блокировки — снаружи выглядит как «фон не работает».
///
/// Отдельного плагина ради одного разрешения не берём: `permission_handler`
/// тянет за собой пол-андроида, а тут хватает пары строк в `MainActivity`.
/// На iOS и на Android до 13 канал отвечает `false` и ничего не делает.
library;

import 'package:flutter/services.dart';

const _channel = MethodChannel('bloom/notifications');

/// Спросить разрешение, если его ещё нет. Результат диалога не ждём — он
/// системный и на воспроизведение не влияет.
Future<void> ensureNotificationPermission() async {
  try {
    await _channel.invokeMethod<bool>('ensure');
  } on PlatformException {
    // Канал не отвечает — не повод не играть.
  } on MissingPluginException {
    // iOS / тесты.
  }
}
