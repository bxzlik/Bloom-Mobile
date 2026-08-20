/// Системные диалоги «сохранить текст файлом» и «открыть текстовый файл».
///
/// На десктопе это команды Rust с нативным диалогом; здесь — свой
/// `MethodChannel`, как у уведомлений и скачивания. Пакета ради этого не тянем:
/// обе стороны — по одному системному экрану.
///
/// Android — SAF (`ACTION_CREATE_DOCUMENT` / `ACTION_OPEN_DOCUMENT`): человек
/// сам выбирает, куда положить и откуда взять, и разрешений на память для
/// этого не нужно. iOS — `UIDocumentPicker`, тот же смысл.
///
/// `null`/`false` в ответе означают «диалог закрыли», а не ошибку: на десктопе
/// отмена точно так же тихая.
///
/// Пользователей у этой пары трое: пресеты кастомизации (`.bloompresets`),
/// перенос плейлистов (`.bloomplaylist`) и выгрузка журнала работы.
library;

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('bloom/files');

/// Предложить сохранить текст файлом. `true` — файл записан, `false` —
/// отменили или не вышло.
Future<bool> saveTextFile(
  String filename,
  String content, {
  String mime = 'application/json',
}) async {
  try {
    final ok = await _channel.invokeMethod<bool>('saveText', {
      'filename': filename,
      'content': content,
      // Своих типов у `.bloompresets`/`.bloomplaylist` нет; `application/json`
      // заставляет системный выбор папки предлагать разумное место, а не
      // «двоичное».
      'mime': mime,
    });
    return ok ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false; // платформа без нативной стороны (тесты, десктоп)
  }
}

/// Дать выбрать файл и прочитать его. `null` — отменили или прочитать не
/// вышло.
Future<String?> openTextFile() async {
  try {
    return await _channel.invokeMethod<String>('openText');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Имя и версия сборки — строка «Версия v1.0.0 (сборка 12)» в «О приложении».
///
/// Нативно, а не пакетом `package_info_plus`: обе стороны — одно чтение
/// манифеста, и ради него тянуть зависимость незачем (так же сделаны
/// уведомления, скачивание и чтение тегов).
///
/// `null` — платформа не ответила (тесты, десктоп).
Future<({String version, String build})?> appVersion() async {
  try {
    final info = await _channel.invokeMapMethod<String, Object?>('appInfo');
    final version = info?['version'];
    if (version is! String || version.isEmpty) return null;
    return (version: version, build: '${info?['build'] ?? ''}');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
