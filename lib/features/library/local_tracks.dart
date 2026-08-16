/// Свои треки: файлы с телефона, добавленные плюсом в шапке «Всех треков».
///
/// Порт десктопных `importTracks` + `add_files`/`make_track` из
/// `folder_watcher.rs`. Отличия от ПК, сделанные осознанно:
///
/// - **папок нет.** На десктопе за папками следит `notify`, и одиночный файл
///   там частный случай общего механизма. На телефоне общей файловой системы,
///   за которой можно следить, у приложения нет — остаются ровно одиночные
///   файлы, выбранные человеком в системном диалоге.
/// - **теги читает не Dart.** Пакета-тегочиталки не тянем (как не тянули ради
///   уведомлений и скачивания): на Android это `MediaMetadataRetriever`, на
///   iOS — `AVAsset`, оба уже умеют mp3/flac/m4a/ogg и отдают встроенную
///   обложку. Байты через канал не гоняем: нативная сторона сама кладёт
///   обложку в `covers/`, а в Dart едет имя файла.
/// - **id стабильный, но не от пути**, как `lf`+md5(path) на ПК, а `lf`+md5
///   от КЛЮЧА (см. [localTrackKey]): в режиме «помнить путь» это выданный
///   системой `content://`, в режиме копии — «имя|размер» исходника. Иначе
///   повторное добавление того же файла давало бы второй трек: у копии каждый
///   раз новое имя.
///
/// Файл трека живёт в одном из двух мест, см. [LocalImportMode]. В `sourceData`
/// хранится ИМЯ файла копии, а не путь: контейнер приложения на iOS переезжает
/// между запусками (та же причина, что у обложек и офлайн-копий).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/cover_store.dart';
import '../../core/store/library_store.dart';
import '../../core/store/settings_store.dart';

/// Тот же канал, что у файла пресетов: обе стороны — системные диалоги файлов,
/// заводить второй канал ради двух методов незачем.
const MethodChannel _channel = MethodChannel('bloom/files');

Directory? _dir;

/// Готовит каталог своих треков (`tracks/` внутри данных приложения). Зовётся
/// из `main()` до первого кадра: дальше путь нужен синхронно, прямо в `_load`
/// плеера.
Future<void> initLocalTracks() async {
  final root = await appPrivateDir();
  final dir = Directory('${root.path}/tracks');
  try {
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
  } catch (_) {
    // Нет прав на запись — режим копии просто не сработает, остальное живо.
  }
}

/// Каталог копий; `null` — он не поднялся.
String? localTracksDirPath() => _dir?.path;

/// Свой ли это трек. Именно по источнику И по данным: `MusicSource.fromId`
/// отдаёт `local` любому id без префикса площадки, а играть можно только то,
/// за чем стоит файл.
bool isLocalTrack(Track track) =>
    track.source == MusicSource.local && track.sourceData?['key'] is String;

/// Ключ дедупа: по нему считается id и по нему же нативная сторона отсеивает
/// уже добавленное.
String? localTrackKey(Track track) {
  final key = track.sourceData?['key'];
  return key is String ? key : null;
}

/// Сквозной id своего трека — `lf` + md5 ключа, как на десктопе.
String localTrackId(String key) =>
    'lf${md5.convert(utf8.encode(key.toLowerCase()))}';

/// Ключи всего, что уже добавлено: нативной стороне, чтобы не копировать и не
/// разбирать файл, который в библиотеке и так есть.
List<String> knownLocalKeys(LibraryState lib) => [
  for (final track in lib.tracks.values) ?localTrackKey(track),
];

/// Где лежит файл своего трека: `file://` копии внутри приложения либо
/// `content://` исходника. `null` — трек не свой, каталог не поднялся или
/// копию уже стёрли.
///
/// Для `content://` существование не проверяем: узнать это можно только
/// открыв поток, и делать это на каждый `_load` дороже, чем один раз честно
/// упасть в ошибку плеера.
Uri? localTrackUri(Track track) {
  if (!isLocalTrack(track)) return null;
  final file = track.sourceData?['file'];
  if (file is String) {
    final dir = _dir;
    if (dir == null) return null;
    final path = '${dir.path}/$file';
    return File(path).existsSync() ? Uri.file(path) : null;
  }
  final uri = track.sourceData?['uri'];
  return uri is String ? Uri.tryParse(uri) : null;
}

/// «Артист - Название» из имени файла — тот же фолбэк, что в `make_track` на
/// ПК: у файла без тегов имя обычно единственное, что о нём известно.
({String artist, String name}) splitFileName(String fileName) {
  var stem = fileName;
  final dot = stem.lastIndexOf('.');
  // Точка первым символом — не расширение, а скрытый файл.
  if (dot > 0) stem = stem.substring(0, dot);
  final sep = stem.indexOf(' - ');
  if (sep < 0) return (artist: '', name: stem.trim());
  return (
    artist: stem.substring(0, sep).trim(),
    name: stem.substring(sep + 3).trim(),
  );
}

String? _norm(Object? value) {
  if (value is! String) return null;
  final s = value.trim();
  return s.isEmpty ? null : s;
}

/// Год из тега: у vorbis/mp4 там обычно полная дата («2019-04-05»), и на ПК от
/// неё точно так же берут первые четыре цифры.
String? _year(Object? value) {
  final raw = _norm(value);
  if (raw == null) return null;
  final match = RegExp(r'\d{4}').firstMatch(raw);
  return match?.group(0);
}

/// Ответ нативной стороны → трек библиотеки. Порт `fromLocal` + `make_track`:
/// пустой тег заменяется тем, что удалось вытащить из имени файла, а совсем
/// безымянному артисту достаётся «Неизвестный».
///
/// `null` — запись битая (без ключа играть нечего).
Track? localTrackFromEntry(Object? raw, {required String unknownArtist}) {
  if (raw is! Map) return null;
  final key = _norm(raw['key']);
  if (key == null) return null;

  final fileName = raw['name'] as String? ?? '';
  final fallback = splitFileName(fileName);
  final cover = _norm(raw['cover']);
  final genre = _norm(raw['genre']);
  final size = raw['size'];
  final uri = _norm(raw['uri']);
  final file = _norm(raw['file']);

  return Track(
    id: localTrackId(key),
    name:
        _norm(raw['title']) ??
        (fallback.name.isEmpty ? fileName : fallback.name),
    artist:
        _norm(raw['artist']) ??
        (fallback.artist.isEmpty ? unknownArtist : fallback.artist),
    duration: Duration(milliseconds: (raw['durationMs'] as num?)?.toInt() ?? 0),
    source: MusicSource.local,
    cover: cover == null ? null : localCoverRef(cover),
    album: _norm(raw['album']),
    year: _year(raw['year']),
    // Несколько жанров в одном теге разделяются `;` или нулём — режем так же,
    // как lofty-часть на ПК.
    genres: genre == null
        ? const []
        : [
            for (final g in genre.split(RegExp(r'[;\x00]')))
              if (g.trim().isNotEmpty) g.trim(),
          ],
    sourceData: {
      'key': key,
      'name': fileName,
      if (size is num) 'size': size.toInt(),
      'uri': ?uri,
      'file': ?file,
    },
  );
}

/// Чем кончился поход в системный диалог.
enum LocalImportStatus {
  /// Диалог закрыли, ничего не выбрав, — говорить не о чем.
  cancelled,

  /// Файлы выбрали, но добавить нечего: всё это уже в библиотеке либо не
  /// читается (десктопный `lib.import.nothingAdded`).
  nothing,

  /// Добавили.
  added,

  /// Диалога нет или он ответил ошибкой.
  failed,
}

typedef LocalImportResult = ({LocalImportStatus status, int added});

/// Выбрать свои файлы и положить их в библиотеку.
///
/// Всё тяжёлое (копирование, чтение тегов, обложка) делает нативная сторона —
/// она же отсеивает дубли по [knownLocalKeys]: гонять мегабайты и разбирать
/// теги ради трека, который в библиотеке уже есть, незачем.
Future<LocalImportResult> importLocalTracks(
  WidgetRef ref,
  AppLocalizations l,
) async {
  final covers = coversDirPath();
  final tracks = localTracksDirPath();
  if (covers == null || tracks == null) {
    return (status: LocalImportStatus.failed, added: 0);
  }

  final mode = ref.read(settingsProvider).localImport;
  final known = knownLocalKeys(ref.read(libraryProvider));

  final List<Object?>? entries;
  try {
    entries = await _channel.invokeMethod<List<Object?>>('pickAudio', {
      'mode': mode.name,
      'tracksDir': tracks,
      'coversDir': covers,
      'known': known,
    });
  } on PlatformException {
    return (status: LocalImportStatus.failed, added: 0);
  } on MissingPluginException {
    // Платформа без нативной стороны (тесты, десктоп).
    return (status: LocalImportStatus.failed, added: 0);
  }
  if (entries == null) return (status: LocalImportStatus.cancelled, added: 0);

  final batch = [
    for (final entry in entries)
      ?localTrackFromEntry(entry, unknownArtist: l.commonUnknownArtist),
  ];
  if (batch.isEmpty) return (status: LocalImportStatus.nothing, added: 0);

  // Новые треки уходят наверх «Всех треков» — там сортировка по времени
  // добавления, и `addToLibrary` ставит им время больше всех прежних.
  final added = ref.read(libraryProvider.notifier).addToLibrary(batch);
  return added == 0
      ? (status: LocalImportStatus.nothing, added: 0)
      : (status: LocalImportStatus.added, added: added);
}

/// Убрать за удалённым своим треком: копию внутри приложения и её обложку — с
/// диска, разрешение на чужой файл — вернуть системе.
///
/// Сам файл пользователя НЕ трогаем: ровно как `remove_file` на ПК, где
/// стирается только копия, сделанная режимом «В Bloom».
Future<void> forgetLocalTracks(Iterable<Track> tracks) async {
  for (final track in tracks) {
    if (!isLocalTrack(track)) continue;
    final file = track.sourceData?['file'];
    if (file is String) {
      final dir = _dir;
      if (dir != null) {
        try {
          final copy = File('${dir.path}/$file');
          if (copy.existsSync()) await copy.delete();
        } catch (_) {
          // Не удалилась — это просто мусор в каталоге, не повод падать.
        }
      }
    }
    final uri = track.sourceData?['uri'];
    if (uri is String) {
      try {
        await _channel.invokeMethod<void>('releaseAudio', {'uri': uri});
      } on PlatformException {
        // Разрешение уже отозвано или его не было — нам всё равно.
      } on MissingPluginException {
        // Платформа без нативной стороны.
      }
    }
    await deleteCover(track.cover);
  }
}

/// Свои треки среди [ids] — вызывающему обычно известны только id удаляемого.
List<Track> localTracksOf(LibraryState lib, Iterable<String> ids) => [
  for (final id in ids)
    if (lib.tracks[id] case final Track track when isLocalTrack(track)) track,
];

/// Ошибка «файла больше нет»: `content://` протух (файл удалили, карту
/// вынули), копию стёрли мимо приложения.
///
/// Своим типом ради текста: `state.error` показывается человеку как есть, а
/// `StateError` дописал бы к нему «Bad state:».
class LocalFileGone implements Exception {
  const LocalFileGone();

  @override
  String toString() => globalL10n?.ltFileGone ?? 'File is not available';
}
