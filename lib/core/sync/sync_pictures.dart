/// Свои картинки в посылке синхронизации — порт `SyncPictures` ПК
/// (`src/sync/SyncPictures.cpp`): обложка плейлиста или трека, аватар и
/// баннер профиля — файлы этого устройства, на другом они ничего не значат.
/// В посылке они едут как `img:<имя>`, где имя — хеш байтов, а сами файлы
/// ходят отдельно по этому имени; у кого файл с таким именем уже есть, тот его
/// второй раз не берёт.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../db/db.dart';

const String _wire = 'img:';
const String _local = 'local:';
final RegExp _nameRe = RegExp(r'^[0-9a-f]{32}\.(jpg|png|gif|webp)$');

/// `<32 hex>.<jpg|png|gif|webp>` — ничего другого не берём и не отдаём.
bool validPictureName(String name) => _nameRe.hasMatch(name);

/// Расширение по первым байтам — как у ПК, чтобы одна картинка звалась на
/// обеих сторонах одинаково.
String pictureExt(Uint8List b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
  if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
  return 'jpg';
}

String pictureName(Uint8List bytes) =>
    '${sha256.convert(bytes).toString().substring(0, 32)}.${pictureExt(bytes)}';

class SyncPictures {
  /// [dir] — каталог своих картинок (`covers/`, см. `cover_store`).
  SyncPictures(this.db, this.dir);

  final BloomDb db;
  final String dir;

  /// Свои файлы по именам, посчитанные за запуск: файл картинки не меняется,
  /// новая картинка — новый файл.
  final Map<String, String> _byName = {}, _byFile = {};
  bool _scanned = false;

  /// Свои файлы в уходящей посылке ([SyncLog.outgoing]) становятся
  /// `img:<имя>`; возвращает имена, на которые она ссылается.
  Set<String> toWire(Map<String, Object?> payload) {
    final names = <String>{};
    _each(payload, (ref, _) {
      if (!ref.startsWith(_local)) return ref; // картинка площадки — как есть
      final name = _nameOf(ref.substring(_local.length));
      if (name == null) return ''; // файла уже нет — там пусто
      names.add(name);
      return '$_wire$name';
    });
    return names;
  }

  /// Имена картинок, на которые ссылается пришедшая посылка.
  Set<String> wanted(Map<String, Object?> payload) {
    final names = <String>{};
    _each(payload, (ref, _) {
      if (ref.startsWith(_wire) &&
          validPictureName(ref.substring(_wire.length))) {
        names.add(ref.substring(_wire.length));
      }
      return ref;
    });
    return names;
  }

  /// `img:<имя>` в пришедшей посылке — свой файл этой картинки; пусто, где
  /// его нет (теряется картинка, а не изменение).
  void fromWire(Map<String, Object?> payload) => _each(payload, (ref, _) {
    if (!ref.startsWith(_wire)) return ref;
    final file = _fileOf(ref.substring(_wire.length));
    return file == null ? '' : '$_local$file';
  });

  /// Есть ли у нас файл этой картинки.
  bool has(String name) => _fileOf(name) != null;

  /// Байты своей картинки; `null` — её нет.
  Uint8List? read(String name) {
    final file = _fileOf(name);
    if (file == null) return null;
    try {
      return File('$dir/$file').readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  /// Картинка с другой стороны; `false` — байты не сходятся с именем.
  bool put(String name, Uint8List bytes) {
    if (!validPictureName(name) || pictureName(bytes) != name) return false;
    if (has(name)) return true;
    try {
      File('$dir/$name').writeAsBytesSync(bytes, flush: true);
      _remember(name, name);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Внутреннее ──────────────────────────────────────────────────────────

  void _remember(String name, String file) {
    _byName[name] = file;
    _byFile[file] = name;
  }

  String? _nameOf(String file) {
    final known = _byFile[file];
    if (known != null) return known;
    if (file.contains('/') || file.contains('\\')) return null;
    try {
      final name = pictureName(File('$dir/$file').readAsBytesSync());
      _remember(name, file);
      return name;
    } catch (_) {
      return null;
    }
  }

  String? _fileOf(String name) {
    if (!validPictureName(name)) return null;
    if (File('$dir/$name').existsSync()) return name;
    String? known() {
      final f = _byName[name];
      return f != null && File('$dir/$f').existsSync() ? f : null;
    }

    final f = known();
    if (f != null || _scanned) return f;
    _scan();
    return known();
  }

  /// Все картинки, которыми пользуются строки, — для той, что спросили по
  /// имени, а ни одна посылка этого запуска её не называла.
  void _scan() {
    _scanned = true;
    final refs = [
      for (final r in db.select(
        "SELECT cover FROM lists WHERE cover LIKE 'local:%' UNION SELECT cover FROM tracks WHERE cover LIKE 'local:%' AND id NOT LIKE 'lf:%'",
      ))
        r['cover'] as String,
    ];
    final card = db.getMap('profile');
    for (final k in const ['avatar', 'banner']) {
      if (card[k] case final String ref) refs.add(ref);
    }
    for (final ref in refs) {
      if (ref.startsWith(_local)) _nameOf(ref.substring(_local.length));
    }
  }
}

/// Каждое поле картинки посылки — через [fn] (ссылка, это профиль ли).
void _each(
  Map<String, Object?> payload,
  String Function(String ref, bool profile) fn,
) {
  final changes = payload['changes'];
  if (changes is List) {
    for (final c in changes) {
      if (c is! Map || c['row'] is! Map) continue;
      final row = Map<String, Object?>.of(
        (c['row'] as Map).cast<String, Object?>(),
      );
      final kind = c['kind'];
      if (kind == 'list' || kind == 'track') {
        row['cover'] = fn(
          row['cover'] is String ? row['cover'] as String : '',
          false,
        );
      } else if (kind == 'kv' && c['key'] == 'profile') {
        // kv держит значение обёрнутым в массив (`BloomDb.set`).
        Object? wrapped;
        try {
          wrapped = jsonDecode(row['value'] as String? ?? '');
        } catch (_) {}
        if (wrapped is! List || wrapped.isEmpty || wrapped.first is! Map) {
          continue;
        }
        final card = Map<String, Object?>.of(
          (wrapped.first as Map).cast<String, Object?>(),
        );
        for (final k in const ['avatar', 'banner']) {
          card[k] = fn(card[k] is String ? card[k] as String : '', true);
        }
        row['value'] = jsonEncode([card]);
      } else {
        continue;
      }
      c['row'] = row;
    }
  }
  final tracks = payload['tracks'];
  if (tracks is List) {
    for (final t in tracks) {
      if (t is! Map) continue;
      t['cover'] = fn(t['cover'] is String ? t['cover'] as String : '', false);
    }
  }
}
