/// Свои обложки плейлистов: выбор картинки из галереи и её хранение.
///
/// Файл галереи копируется в каталог приложения (`covers/`) — то, что вернул
/// image_picker, лежит в кеше и может пропасть в любой момент, а обложка нужна
/// столько же, сколько сам плейлист.
///
/// В плейлисте хранится НЕ абсолютный путь, а `local:<имя файла>`: контейнер
/// приложения на iOS переезжает между запусками, и записанный сегодня путь
/// завтра указывал бы в пустоту.
library;

import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import 'app_dirs.dart';

const String _prefix = 'local:';

Directory? _dir;

/// Готовит каталог обложек. Зовётся из `main()` до первого кадра — дальше путь
/// нужен синхронно, прямо в `build`.
Future<void> initCoverStore() async {
  final root = await appPrivateDir();
  final dir = Directory('${root.path}/covers');
  try {
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
  } catch (_) {
    // Нет прав на запись — свои обложки просто не будут доступны.
  }
}

bool isLocalCover(String? cover) => cover != null && cover.startsWith(_prefix);

/// Абсолютный путь своей обложки; `null` — если это не своя обложка или
/// каталог не поднялся.
String? localCoverPath(String? cover) {
  final dir = _dir;
  if (dir == null || !isLocalCover(cover)) return null;
  return '${dir.path}/${cover!.substring(_prefix.length)}';
}

/// Картинка обложки: своя с диска либо сетевая. `null` — обложки нет.
ImageProvider? coverImage(String? cover) {
  if (cover == null || cover.isEmpty) return null;
  final path = localCoverPath(cover);
  if (path != null) return FileImage(File(path));
  if (isLocalCover(cover)) return null; // своя, но каталога нет
  return NetworkImage(cover);
}

/// Метаданные снимка (EXIF, дата, геометка) нам не нужны — берём только сам
/// файл. Флаг НЕ косметический: при `true` image_picker на iOS 13 идёт в
/// `PHPhotoLibrary requestAuthorization` («Full metadata are available only in
/// PHAsset, which requires gallery permission» — комментарий в самом плагине),
/// а это системный запрос доступа ко ВСЕЙ медиатеке и обязательный
/// `NSPhotoLibraryUsageDescription` в Info.plist. С `false` на iOS 13 открывается
/// просто выбор файла, а на iOS 14+ и так работает `PHPickerViewController`,
/// который разрешений не спрашивает вовсе.
///
/// Поставишь обратно `true` — вернуть и ключ в `ios/Runner/Info.plist`, иначе
/// iOS убьёт приложение в момент запроса.
const bool kPickMetadata = false;

/// Выбрать картинку из галереи и положить её к себе. Возвращает значение для
/// поля `cover` (`local:...`) или `null`, если выбор отменён.
///
/// Сторона ограничена 1024 px: обложке больше не нужно, а хранить полный
/// снимок с камеры в каталоге приложения — лишние мегабайты.
Future<String?> pickCover() async {
  final dir = _dir;
  if (dir == null) return null;
  final XFile? picked;
  try {
    picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
      requestFullMetadata: kPickMetadata,
    );
  } catch (_) {
    return null; // отказ в доступе к галерее
  }
  if (picked == null) return null;
  try {
    final name = 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await picked.saveTo('${dir.path}/$name');
    return '$_prefix$name';
  } catch (_) {
    return null;
  }
}

/// Выбрать картинку из галереи БЕЗ сохранения — путь к тому, что вернул
/// image_picker. Нужна там, где картинку ещё будут резать (аватар и обложка
/// профиля): исходник берётся крупнее обложки, а в каталог приложения ляжет
/// уже обрезок.
Future<String?> pickImageFile({int maxSide = 2048}) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide.toDouble(),
      maxHeight: maxSide.toDouble(),
      requestFullMetadata: kPickMetadata,
    );
    return picked?.path;
  } catch (_) {
    return null; // отказ в доступе к галерее
  }
}

/// Положить готовые байты картинкой приложения. Возвращает значение поля
/// (`local:...`) или `null`, если записать не вышло.
Future<String?> saveLocalImage(Uint8List bytes, {String prefix = 'img'}) async {
  final dir = _dir;
  if (dir == null) return null;
  try {
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
    await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    return '$_prefix$name';
  } catch (_) {
    return null;
  }
}

/// Убрать файл своей обложки — плейлист удалили или обложку сменили.
Future<void> deleteCover(String? cover) async {
  final path = localCoverPath(cover);
  if (path == null) return;
  try {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  } catch (_) {
    // Не удалилась — не беда, это просто мусор в каталоге.
  }
}
