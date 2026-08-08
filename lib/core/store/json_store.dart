/// Файловое JSON-хранилище приложения — то, чем на десктопе служит
/// `localStorage`.
///
/// Один файл на всё (`bloom.json`) в каталоге приложения. Запись отложенная:
/// лайк и добавление трека дёргают стор пачками, а писать файл на каждое
/// изменение незачем.
///
/// Файл пишется через временный и переименовывается: обрыв на середине не
/// оставит битый JSON, из-за которого библиотека выглядела бы пустой.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_dirs.dart';

const Duration _saveDelay = Duration(milliseconds: 400);

class JsonStore {
  JsonStore._(this._file, this._data);

  final File _file;
  final Map<String, dynamic> _data;
  Timer? _debounce;

  static Future<JsonStore> open({String name = 'bloom.json'}) async {
    final dir = await appPrivateDir();
    final file = File('${dir.path}/$name');
    Map<String, dynamic> data = {};
    try {
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) data = decoded.cast<String, dynamic>();
      }
    } catch (_) {
      // Битый/чужой файл — начинаем с чистого листа, но НЕ удаляем его:
      // пусть останется на диске, если пользователь захочет посмотреть.
    }
    return JsonStore._(file, data);
  }

  /// Хранилище в памяти — для тестов и первого запуска без файловой системы.
  factory JsonStore.memory([Map<String, dynamic>? seed]) =>
      JsonStore._(File(''), seed ?? {});

  Object? read(String key) => _data[key];

  List<Object?> readList(String key) {
    final v = _data[key];
    return v is List ? v : const [];
  }

  Map<String, dynamic> readMap(String key) {
    final v = _data[key];
    return v is Map ? v.cast<String, dynamic>() : {};
  }

  void write(String key, Object? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_saveDelay, flush);
  }

  /// Записать немедленно (закрытие приложения, тесты).
  Future<void> flush() async {
    _debounce?.cancel();
    if (_file.path.isEmpty) return; // in-memory
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_data), flush: true);
      await tmp.rename(_file.path);
    } catch (_) {
      // Нет места/прав — библиотека продолжает работать в памяти.
    }
  }
}
