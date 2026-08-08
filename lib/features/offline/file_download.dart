/// «Скачать файлом» — второе скачивание, как на десктопе.
///
/// На ПК их два: `sc_download` сохраняет трек файлом через диалог, а
/// `offline_download` кладёт копию в невидимый кеш профиля. Здесь так же:
/// офлайн-копия живёт внутри приложения (см. `offline_store.dart`), а этот файл
/// ложится туда, где человек его найдёт и без Bloom.
///
/// Куда именно — решает платформа, и они тут не равны:
/// - Android: общая «Музыка/Bloom». Файл видят системные плееры, и он
///   переживает удаление приложения. Писать в общую память с десятки можно
///   только через MediaStore, поэтому запись делает Kotlin ([MediaStoreSaver]).
/// - iOS: `Documents` приложения — папка, которую система показывает в
///   «Файлах». Общей медиатеки для сторонних приложений там нет вовсе, так что
///   файл остаётся в песочнице, зато на виду: его можно отправить дальше или
///   перетащить. Нативный код не нужен, это обычный каталог.
///
/// Диалога «куда сохранить» нет намеренно: на телефоне он мучителен и для
/// плейлиста целиком работает плохо, поэтому папка всегда одна.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/store/app_dirs.dart';
import 'offline_store.dart';

const MethodChannel _channel = MethodChannel('bloom/downloads');

/// Есть ли на этой платформе куда сохранить файл «наружу».
bool get canSaveFiles => Platform.isAndroid || Platform.isIOS;

/// Куда, по-человечески, — для снекбара и подписей.
String get saveTargetLabel =>
    Platform.isIOS ? 'Файлы → На iPhone → Bloom' : 'Музыка/Bloom';

/// Сохранить трек файлом. Возвращает путь для показа пользователю.
///
/// Уже скачанный офлайн трек второй раз не качается — файл просто копируется
/// из кеша (и, разумеется, из кеша не пропадает).
Future<String> saveTrackAsFile(
  WidgetRef ref,
  Track track, {
  void Function(double)? onProgress,
}) async {
  final offline = ref.read(offlineProvider.notifier);
  final cached = offline.pathOf(track.id);

  final String sourcePath;
  final bool deleteSource;
  if (cached != null) {
    sourcePath = cached;
    deleteSource = false;
  } else {
    final provider = ref.read(registryProvider).forEntity(track.id);
    if (provider == null || !provider.canDownload(track)) {
      throw const FormatException('Этот трек нельзя скачать');
    }
    final stream = await provider.resolveDownload(track);
    if (stream == null) {
      throw const FormatException('Этот трек нельзя скачать');
    }
    // Временный каталог: файл живёт ровно до переноса в медиатеку, а система
    // вправе подчистить его сама, если перенос не случится.
    final tmp = await getTemporaryDirectory();
    final file = await fetchAudioToFile(
      url: stream.url,
      headers: stream.headers,
      dir: tmp,
      base: trackFileBase(track),
      onProgress: onProgress,
    );
    sourcePath = file.path;
    deleteSource = true;
  }

  // Имя даём своё: у офлайн-копии оно уже с разведением дублей («… (2).mp3»),
  // а в целевой папке дубли разводятся заново и по ней.
  final ext = sourcePath.split('.').last.toLowerCase();
  final filename = '${trackFileBase(track)}.$ext';

  if (Platform.isIOS) {
    return _saveToVisibleDir(File(sourcePath), filename, deleteSource);
  }
  final saved = await _channel.invokeMethod<String>('save', {
    'sourcePath': sourcePath,
    'filename': filename,
    'mime': ext == 'm4a' ? 'audio/mp4' : 'audio/mpeg',
    'title': track.name,
    'artist': track.artist,
    'deleteSource': deleteSource,
  });
  return saved ?? saveTargetLabel;
}

/// iOS: кладём файл в `Documents` приложения — ту самую папку, которую система
/// показывает в «Файлах» (за это отвечают `UIFileSharingEnabled` и
/// `LSSupportsOpeningDocumentsInPlace` в Info.plist).
///
/// Нативный код тут не нужен: это обычный каталог приложения. Общей медиатеки,
/// как `Музыка/Bloom` на Android, у iOS для сторонних приложений нет — отсюда
/// файл человек уже сам утаскивает куда хочет.
Future<String> _saveToVisibleDir(
  File source,
  String filename,
  bool deleteSource,
) async {
  final dir = await appVisibleDir();
  if (!dir.existsSync()) await dir.create(recursive: true);

  // Два трека могут называться одинаково — разводим, как и в офлайн-кеше.
  final dot = filename.lastIndexOf('.');
  final base = dot > 0 ? filename.substring(0, dot) : filename;
  final ext = dot > 0 ? filename.substring(dot) : '';
  var target = File('${dir.path}/$filename');
  var i = 2;
  while (target.existsSync()) {
    target = File('${dir.path}/$base ($i)$ext');
    i++;
  }

  // Именно копия, а не переезд: источником может быть офлайн-копия, которая
  // нужна плееру на своём месте.
  await source.copy(target.path);
  if (deleteSource) {
    try {
      await source.delete();
    } catch (_) {
      // Временный файл не удалился — система подчистит его сама.
    }
  }
  return saveTargetLabel;
}

/// Сохранить файлами весь список. Возвращает число неудач.
///
/// Ссылки резолвятся покадрово и с паузами — по той же причине, что и в
/// офлайн-пакете: подписанный CDN-URL живёт минуты, а поток резолвов площадка
/// начинает отбивать.
Future<({int total, int failed})> saveListAsFiles(
  WidgetRef ref,
  String title,
  List<Track> tracks,
) async {
  final offline = ref.read(offlineProvider.notifier);
  final pending = tracks.where(offline.canDownload).toList();
  if (pending.isEmpty || !offline.beginBatch(title, pending.length)) {
    return (total: pending.length, failed: 0);
  }

  var failed = 0;
  for (var i = 0; i < pending.length; i++) {
    var ok = true;
    try {
      await saveTrackAsFile(ref, pending[i]);
    } catch (_) {
      ok = false;
      failed++;
    }
    if (!offline.advanceBatch(failed: !ok)) break;
    if (i < pending.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  offline.endBatch();
  return (total: pending.length, failed: failed);
}

/// Ошибку канала показываем текстом Android, остальное — как есть.
String readableSaveError(Object e) {
  if (e is PlatformException) {
    if (e.code == 'permission') {
      return 'Нужен доступ к памяти телефона — разрешите и повторите';
    }
    return e.message ?? 'Не удалось сохранить файл';
  }
  if (e is FormatException) return e.message;
  if (e is SocketException) return 'Нет соединения';
  return 'Не удалось сохранить: $e';
}
