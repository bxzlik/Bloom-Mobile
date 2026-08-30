/// Отдать картинку системной шторке «Поделиться».
///
/// Постер «Итогов» на ПК рисуется на canvas и сохраняется файлом
/// (`cover_download`). На телефоне сохранённый в галерею PNG человек всё равно
/// понесёт в мессенджер руками, поэтому финальный шаг здесь — системный
/// `ACTION_SEND` / `UIActivityViewController`: оттуда карточка уходит в чат или
/// в сторис одним касанием, а «Сохранить в галерею» есть в той же шторке.
///
/// Пакета `share_plus` не тянем — своя пара методов в уже заведённом канале
/// `bloom/files` (тот же приём, что с уведомлениями и скачиванием: ради одного
/// системного вызова пакет в проект не заводим).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

const MethodChannel _channel = MethodChannel('bloom/files');

/// Куда кладём картинку перед отправкой.
///
/// ВРЕМЕННЫЙ каталог, а не `appPrivateDir`, и это не мелочь: на Android файл
/// уходит наружу через `FileProvider`, а тот умеет отдавать `cache/`
/// (`<cache-path>` в `res/xml/bloom_share_paths.xml`) — каталог
/// `app_flutter`, куда смотрит `appPrivateDir`, ему не виден вовсе.
///
/// Файл переживает ровно показ шторки: система читает его уже после нашего
/// возврата, поэтому удалять сразу нельзя — вместо этого следующая отправка
/// перезаписывает тот же файл, а кеш чистит сама система.
Future<File> _shareFile(String name) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/share');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return File('${dir.path}/$name');
}

/// Снять карточку в PNG. [key] — ключ её `RepaintBoundary`; `null` возвращается,
/// когда границы в дереве уже нет (шторку закрыли, пока шёл снимок).
///
/// Живёт здесь, а не в шторке: карточек «Поделиться» две — сущности площадки и
/// профиля, — а снимаются они одинаково.
Future<Uint8List?> captureShareCard(
  GlobalKey key, {
  required double pixelRatio,
}) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

/// Отдать PNG системной шторке. `false` — отправить не удалось (нативная
/// сторона отказала); отмена самим человеком считается успехом — так же ведёт
/// себя любой системный пикер.
Future<bool> shareImageBytes(
  Uint8List png, {
  required String filename,
  String? text,
}) async {
  try {
    final file = await _shareFile(filename);
    await file.writeAsBytes(png, flush: true);
    await _channel.invokeMethod<void>('shareFile', {
      'path': file.path,
      'mime': 'image/png',
      'text': ?text,
    });
    return true;
  } catch (_) {
    // Нет места, нет прав или канал не отвечает — зовущий покажет тост.
    return false;
  }
}
