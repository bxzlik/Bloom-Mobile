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

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/cover_store.dart';
import '../../core/l10n/l10n.dart';
import 'offline_store.dart';

const MethodChannel _channel = MethodChannel('bloom/downloads');

/// Есть ли на этой платформе куда сохранить файл «наружу».
bool get canSaveFiles => Platform.isAndroid || Platform.isIOS;

/// Куда, по-человечески, — для снекбара и подписей.
String saveTargetLabel(AppLocalizations l) =>
    Platform.isIOS ? l.fdPathIos : l.fdPathAndroid;

/// Сохранить трек файлом. Возвращает путь для показа пользователю; `null` —
/// файл лёг в место по умолчанию, и назвать его человеческим языком (см.
/// [saveTargetLabel]) должен уже UI.
///
/// Уже скачанный офлайн трек второй раз не качается — файл просто копируется
/// из кеша (и, разумеется, из кеша не пропадает).
Future<String?> saveTrackAsFile(
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
      throw const DownloadFailure(DownloadFailureKind.notDownloadable);
    }
    final stream = await provider.resolveDownload(track);
    if (stream == null) {
      throw const DownloadFailure(DownloadFailureKind.notDownloadable);
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
  return saved;
}

/// «Скачать обложку» — порт десктопного `cover_download`. Ложится рядом с
/// треками: на Android — «Изображения/Bloom» (в «Музыке» галерея картинку не
/// покажет), на iOS — та же папка приложения в «Файлах». Возвращает путь так же,
/// как [saveTrackAsFile].
///
/// В треке обложка хранится уменьшенной (под строку списка), поэтому сначала
/// просим крупную версию той же картинки, а не вышло — берём как есть.
Future<String?> saveCoverAsFile(Track track) async {
  final cover = track.cover;
  if (cover == null || cover.isEmpty) {
    throw const DownloadFailure(DownloadFailureKind.notDownloadable);
  }

  final Uint8List bytes;
  final localPath = localCoverPath(cover);
  if (localPath != null) {
    bytes = await File(localPath).readAsBytes();
  } else if (isLocalCover(cover)) {
    throw const DownloadFailure(DownloadFailureKind.notDownloadable);
  } else if (cover.startsWith('data:')) {
    final decoded = decodeDataUrl(cover);
    if (decoded == null) {
      throw const DownloadFailure(DownloadFailureKind.notDownloadable);
    }
    bytes = decoded.bytes;
  } else {
    bytes = await _fetchCover(cover);
  }

  final ext = _imageExt(bytes);
  final filename = '${trackFileBase(track)}.$ext';
  final tmp = File('${(await getTemporaryDirectory()).path}/$filename');
  await tmp.writeAsBytes(bytes, flush: true);

  if (Platform.isIOS) return _saveToVisibleDir(tmp, filename, true);
  return _channel.invokeMethod<String>('save', {
    'sourcePath': tmp.path,
    'filename': filename,
    'mime': switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    },
    'deleteSource': true,
  });
}

/// Крупная версия сетевой обложки, при отказе — исходная ссылка.
Future<Uint8List> _fetchCover(String url) async {
  // Referer — как на ПК: CDN SoundCloud без него иногда отвечает 403.
  const headers = {'Referer': 'https://soundcloud.com/'};
  final big = largeCoverUrl(url);
  if (big != url) {
    try {
      final r = await http
          .get(Uri.parse(big), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
    } catch (_) {
      // Крупной нет — ниже возьмём ту, что показывали.
    }
  }
  final r = await http
      .get(Uri.parse(url), headers: headers)
      .timeout(const Duration(seconds: 15));
  if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
    throw DownloadFailure(DownloadFailureKind.unknown, 'HTTP ${r.statusCode}');
  }
  return r.bodyBytes;
}

/// Ссылка на ту же обложку крупнее. Размер у всех трёх площадок сидит прямо в
/// URL: Яндекс — `/400x400`, SoundCloud — `-t500x500`, YouTube — `=w544-h544`.
@visibleForTesting
String largeCoverUrl(String url) {
  if (url.contains('avatars.yandex.net')) {
    return url.replaceFirst(RegExp(r'/\d+x\d+$'), '/1000x1000');
  }
  if (url.contains('sndcdn.com')) {
    return url.replaceFirst(RegExp(r'-(t\d+x\d+|large|crop)\.'), '-original.');
  }
  if (url.contains('googleusercontent.com') || url.contains('ggpht.com')) {
    return url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w1200-h1200');
  }
  return url;
}

/// Расширение по сигнатуре байтов — как `ext` в десктопном `download_cover`.
String _imageExt(Uint8List b) {
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[8] == 0x57 &&
      b[9] == 0x45) {
    return 'webp';
  }
  return 'jpg';
}

/// iOS: кладём файл в `Documents` приложения — ту самую папку, которую система
/// показывает в «Файлах» (за это отвечают `UIFileSharingEnabled` и
/// `LSSupportsOpeningDocumentsInPlace` в Info.plist).
///
/// Нативный код тут не нужен: это обычный каталог приложения. Общей медиатеки,
/// как `Музыка/Bloom` на Android, у iOS для сторонних приложений нет — отсюда
/// файл человек уже сам утаскивает куда хочет.
Future<String?> _saveToVisibleDir(
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
  return null;
}

/// Сохранить файлами весь список. Возвращает число неудач.
///
/// Ссылки резолвятся покадрово и с паузами — по той же причине, что и в
/// офлайн-пакете: подписанный CDN-URL живёт минуты, а поток резолвов площадка
/// начинает отбивать.
Future<({int total, int failed})> saveListAsFiles(
  WidgetRef ref,
  String sourceId,
  List<Track> tracks,
) async {
  final offline = ref.read(offlineProvider.notifier);
  final pending = tracks.where(offline.canDownload).toList();
  if (pending.isEmpty || !offline.beginBatch(sourceId, pending.length)) {
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

/// Почему файл не сохранился. Текста тут нет намеренно — язык интерфейса
/// известен только UI (`describeSaveError` в `offline_actions.dart`).
enum DownloadFailureKind {
  notDownloadable,
  needPermission,
  noConnection,
  unknown,
}

class DownloadFailure implements Exception {
  const DownloadFailure(this.kind, [this.detail]);

  final DownloadFailureKind kind;

  /// Текст от платформы для `unknown` — Android присылает своё сообщение.
  final String? detail;
}

/// Разобрать пойманное исключение в причину.
DownloadFailure readableSaveError(Object e) {
  if (e is DownloadFailure) return e;
  if (e is PlatformException) {
    if (e.code == 'permission') {
      return const DownloadFailure(DownloadFailureKind.needPermission);
    }
    return DownloadFailure(DownloadFailureKind.unknown, e.message);
  }
  if (e is SocketException) {
    return const DownloadFailure(DownloadFailureKind.noConnection);
  }
  return DownloadFailure(DownloadFailureKind.unknown, '$e');
}
