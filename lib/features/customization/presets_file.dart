/// Выгрузка и загрузка файла пресетов (`.bloompresets`).
///
/// На десктопе это две команды Rust с нативным диалогом
/// (`export_presets_file` / `import_presets_file`); здесь — общий с переносом
/// плейлистов и журналом `MethodChannel` (см. `core/store/text_files.dart`).
/// Сами системные диалоги живут там, здесь — только имена файлов пресетов.
library;

export '../../core/store/text_files.dart' show openTextFile, saveTextFile;

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
