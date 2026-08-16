/// Выгрузка и загрузка файла пресетов (`.bloompresets`).
///
/// На десктопе это две команды Rust с нативным диалогом
/// (`export_presets_file` / `import_presets_file`); здесь — свой
/// `MethodChannel`, как у уведомлений и скачивания. Пакета ради этого не
/// тянем: обе стороны — по одному системному экрану.
///
/// Android — SAF (`ACTION_CREATE_DOCUMENT` / `ACTION_OPEN_DOCUMENT`): человек
/// сам выбирает, куда положить и откуда взять, и разрешений на память для
/// этого не нужно. iOS — `UIDocumentPicker`, тот же смысл.
///
/// `null` в ответе означает «диалог закрыли», а не ошибку: на десктопе отмена
/// точно так же тихая.
library;

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('bloom/files');

/// Расширение файла пресетов — то же, что на ПК.
const String kPresetsExt = 'bloompresets';

/// Имя файла для выгрузки всех пресетов: `bloom-presets-2026-08-15`.
String presetsFileName() {
  final now = DateTime.now();
  final date = '${now.year}-${_two(now.month)}-${_two(now.day)}';
  return 'bloom-presets-$date.$kPresetsExt';
}

/// Имя файла одного пресета: запрещённые в путях символы заменяем, как
/// `safeFileName` на десктопе.
String presetFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  final base = safe.isEmpty
      ? 'preset'
      : safe.substring(0, safe.length.clamp(0, 60));
  return '$base.$kPresetsExt';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Предложить сохранить текст файлом. `true` — файл записан, `false` —
/// отменили или не вышло.
Future<bool> saveTextFile(String filename, String content) async {
  try {
    final ok = await _channel.invokeMethod<bool>('saveText', {
      'filename': filename,
      'content': content,
      // Своего типа у `.bloompresets` нет; `application/json` заставляет
      // системный выбор папки предлагать разумное место, а не «двоичное».
      'mime': 'application/json',
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
