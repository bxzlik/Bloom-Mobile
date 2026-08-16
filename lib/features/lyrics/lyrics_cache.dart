/// Кеш текстов: память + диск — порт `CACHE`/`try_read_disk_cache` из
/// `lyrics_service.rs`.
///
/// Зачем два уровня: за одну сессию трек переслушивают по кругу (память), а
/// между запусками текст не меняется (диск). Файлами, а не строкой в
/// `bloom.json`: тексты весят килобайтами, и класть их в файл библиотеки —
/// значит переписывать его целиком на каждый найденный текст.
///
/// Ненайденное кешируется ТОЛЬКО в памяти и ненадолго ([notFoundTtl]): сегодня
/// текста в LRCLIB нет, а завтра его кто-нибудь зальёт.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/store/app_dirs.dart';
import 'lyrics_api.dart';

/// Сколько живёт запись «текста нет» в памяти.
const Duration notFoundTtl = Duration(minutes: 5);

/// Сколько живёт найденный текст на диске.
const Duration diskTtl = Duration(days: 30);

class LyricsCache {
  LyricsCache({this.dir});

  /// Каталог кеша. `null` — только память (тесты, первый запуск до готовности
  /// файловой системы).
  final Directory? dir;

  final Map<String, ({LyricsResult result, DateTime at})> _mem = {};

  static String keyOf(String artist, String title) =>
      '${artist.toLowerCase()}::${title.toLowerCase()}';

  /// Имя файла — первые 16 hex-символов sha256 от ключа, как на ПК: артист и
  /// название бывают с любыми символами, именем файла их не сделать.
  static String fileNameOf(String artist, String title) =>
      '${sha256.convert(utf8.encode(keyOf(artist, title))).toString().substring(0, 16)}.json';

  /// Готовый ответ или `null` — надо идти в сеть.
  Future<LyricsResult?> read(String artist, String title) async {
    final key = keyOf(artist, title);
    final hit = _mem[key];
    if (hit != null) {
      if (hit.result.found || DateTime.now().difference(hit.at) < notFoundTtl) {
        return hit.result;
      }
      _mem.remove(key);
    }

    final file = _fileOf(artist, title);
    if (file == null || !file.existsSync()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final at = DateTime.tryParse(raw['cachedAt'] as String? ?? '');
      if (at == null || DateTime.now().difference(at) > diskTtl) return null;
      final result = LyricsResult.fromJson(raw);
      if (result == null) return null;
      _mem[key] = (result: result, at: DateTime.now());
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Запомнить ответ. Ненайденное на диск не пишем.
  Future<void> write(String artist, String title, LyricsResult result) async {
    _mem[keyOf(artist, title)] = (result: result, at: DateTime.now());
    if (!result.found) return;
    final file = _fileOf(artist, title);
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          ...result.toJson(),
          'cachedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Нет места/прав — текст остаётся в памяти на эту сессию.
    }
  }

  /// Сколько текстов и байт лежит на диске — для раздела «Хранилище».
  ///
  /// Память не считаем: в разделе речь про место на телефоне, а её содержимое
  /// исчезнет само с закрытием приложения.
  Future<({int count, int bytes})> stats() async {
    final d = dir;
    if (d == null || !d.existsSync()) return (count: 0, bytes: 0);
    var count = 0;
    var bytes = 0;
    for (final e in d.listSync()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      count++;
      try {
        bytes += await e.length();
      } catch (_) {
        // Файл исчез между обходом и чтением — просто не считаем его.
      }
    }
    return (count: count, bytes: bytes);
  }

  /// Стереть кеш целиком. Возвращает число удалённых файлов.
  Future<int> clear() async {
    _mem.clear();
    final d = dir;
    if (d == null || !d.existsSync()) return 0;
    var n = 0;
    for (final e in d.listSync()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          e.deleteSync();
          n++;
        } catch (_) {
          // Занят другим процессом — не беда, срок жизни его всё равно добьёт.
        }
      }
    }
    return n;
  }

  File? _fileOf(String artist, String title) {
    final d = dir;
    return d == null ? null : File('${d.path}/${fileNameOf(artist, title)}');
  }
}

/// Кеш поверх служебного каталога приложения.
Future<LyricsCache> openLyricsCache() async =>
    LyricsCache(dir: Directory('${(await appPrivateDir()).path}/lyrics'));
