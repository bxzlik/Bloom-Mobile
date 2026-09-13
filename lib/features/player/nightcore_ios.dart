/// Nightcore на iOS.
///
/// just_audio на iOS `setPitch` не умеет и сам держит тон при смене скорости.
/// Тон за темпом включает наш канал `bloom/nightcore` в `AppDelegate.swift`:
/// там подменяется алгоритм растяжки у AVPlayer. На Android то же самое
/// делает обычный `setPitch` через ExoPlayer, и канал там не заведён.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('bloom/nightcore');

/// Сообщить iOS, включён ли nightcore. На остальных площадках — ничего.
Future<void> setIosNightcore(bool on) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await _channel.invokeMethod<void>('set', on);
  } on PlatformException {
    // Канал не ответил — темп всё равно работает, просто без тона.
  } on MissingPluginException {
    // Тесты.
  }
}
