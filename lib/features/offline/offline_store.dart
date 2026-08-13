/// Офлайн-копии треков — порт десктопной фичи `src/features/offline`.
///
/// Что делает: резолвит у площадки прямую ссылку на ФАЙЛ трека
/// ([MusicProvider.resolveDownload]), качает его в каталог `offline/` внутри
/// данных приложения и помнит связь `id трека → файл`. Дальше плеер играет
/// копию с диска, а не из сети (см. `PlaybackController._load`) — ровно как
/// офлайн-резолвер на ПК, который стоит первым в очереди резолверов.
///
/// Два отличия от десктопа, сделанные осознанно:
/// - в индексе хранится ИМЯ ФАЙЛА, а не абсолютный путь: контейнер приложения
///   на iOS переезжает между запусками, и записанный сегодня путь завтра
///   указывал бы в пустоту (в [initCoverStore] это уже решено так же);
/// - теги в файл не вшиваются. На ПК их пишет Rust (`embed_tags_async`); здесь
///   файл читает только сам Bloom, а метаданные и так лежат в библиотеке.
///
/// Скачанный трек кладётся в библиотеку: иначе `_prune` выбросит его из
/// хранилища треков, и от офлайн-копии остался бы файл без строки.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart';

Directory? _dir;

/// Готовит каталог офлайн-копий. Зовётся из `main()` до первого кадра — дальше
/// путь нужен синхронно, прямо в `build`.
Future<void> initOfflineStore() async {
  final root = await appPrivateDir();
  final dir = Directory('${root.path}/offline');
  try {
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
  } catch (_) {
    // Нет прав на запись — офлайн просто недоступен, приложение работает.
  }
}

/// Ход пакетной загрузки (плейлист целиком) — то, что на ПК показывает
/// `downloadBanner`.
class OfflineBatch {
  /// Чей это пакет — id списка, с которого его запустили (`listId` экрана).
  /// Индикатор один на всё приложение, поэтому без него строка «Сохраняю…»
  /// висела бы на КАЖДОМ плейлисте, а не на том, который качается.
  final String sourceId;
  final int done;
  final int total;
  final int failed;

  const OfflineBatch({
    required this.sourceId,
    required this.done,
    required this.total,
    this.failed = 0,
  });

  OfflineBatch copyWith({int? done, int? failed}) => OfflineBatch(
    sourceId: sourceId,
    done: done ?? this.done,
    total: total,
    failed: failed ?? this.failed,
  );
}

class OfflineState {
  /// id трека → имя файла в каталоге `offline/`.
  final Map<String, String> files;

  /// Что качается прямо сейчас: id трека → доля 0..1 (`-1` — размер неизвестен).
  final Map<String, double> pending;

  /// Пакетная загрузка, если идёт.
  final OfflineBatch? batch;

  const OfflineState({
    this.files = const {},
    this.pending = const {},
    this.batch,
  });

  bool has(String trackId) => files.containsKey(trackId);
  bool isPending(String trackId) => pending.containsKey(trackId);

  /// Доля скачанного (`null` — трек не качается сейчас).
  double? progressOf(String trackId) {
    final p = pending[trackId];
    return (p == null || p < 0) ? null : p;
  }

  OfflineState copyWith({
    Map<String, String>? files,
    Map<String, double>? pending,
    OfflineBatch? batch,
    bool clearBatch = false,
  }) => OfflineState(
    files: files ?? this.files,
    pending: pending ?? this.pending,
    batch: clearBatch ? null : (batch ?? this.batch),
  );
}

final offlineProvider = NotifierProvider<OfflineController, OfflineState>(
  OfflineController.new,
);

/// Сколько треков подряд качаем в пакете, прежде чем перевести дух: у SC при
/// потоке резолвов api-v2 начинает отдавать 401/403 (то же лечение, что в
/// `downloadPlaylistOffline` на десктопе).
const Duration _betweenTracks = Duration(milliseconds: 250);

class OfflineController extends Notifier<OfflineState> {
  JsonStore get _store => ref.read(jsonStoreProvider);

  @override
  OfflineState build() {
    final files = <String, String>{};
    _store.readMap('offline').forEach((id, name) {
      // Записи, чей файл не пережил переустановку или очистку, не показываем —
      // но и сам индекс не переписываем: см. `offline_scan_all` на ПК.
      if (name is String && _fileOf(name)?.existsSync() == true) {
        files[id] = name;
      }
    });
    return OfflineState(files: files);
  }

  static File? _fileOf(String name) {
    final dir = _dir;
    return dir == null ? null : File('${dir.path}/$name');
  }

  /// Путь к офлайн-копии; `null` — трека офлайн нет.
  String? pathOf(String trackId) {
    final name = state.files[trackId];
    return name == null ? null : _fileOf(name)?.path;
  }

  bool has(String trackId) => state.has(trackId);

  /// Можно ли вообще сохранить этот трек — спрашиваем у его площадки.
  bool canDownload(Track track) =>
      ref.read(registryProvider).forEntity(track.id)?.canDownload(track) ??
      false;

  void _saveIndex() => _store.write('offline', state.files);

  void _setPending(String id, double value) {
    state = state.copyWith(pending: {...state.pending, id: value});
  }

  void _clearPending(String id) {
    final next = {...state.pending}..remove(id);
    state = state.copyWith(pending: next);
  }

  /// Скачать трек. Возвращает `null` при успехе либо текст ошибки для снекбара.
  ///
  /// Идемпотентна, как `offline_download` на ПК: трек уже в кеше или уже
  /// качается — второй раз не качаем.
  Future<String?> download(Track track) async {
    if (state.has(track.id) || state.isPending(track.id)) return null;
    if (_dir == null) return 'Нет доступа к хранилищу';
    final provider = ref.read(registryProvider).forEntity(track.id);
    if (provider == null || !provider.canDownload(track)) {
      return 'Этот трек нельзя сохранить офлайн';
    }

    _setPending(track.id, -1);
    try {
      final stream = await provider.resolveDownload(track);
      if (stream == null) return 'Этот трек нельзя сохранить офлайн';
      final file = await fetchAudioToFile(
        url: stream.url,
        headers: stream.headers,
        dir: _dir!,
        base: trackFileBase(track),
        onProgress: (p) => _setPending(track.id, p),
      );
      state = state.copyWith(
        files: {...state.files, track.id: file.uri.pathSegments.last},
      );
      _saveIndex();
      // Скачанное обязано быть в библиотеке — иначе трек вычистит `_prune`, и
      // файл останется сиротой, на который никто не ссылается.
      ref.read(libraryProvider.notifier).addToLibrary([track]);
      return null;
    } catch (e) {
      return _readableError(e);
    } finally {
      _clearPending(track.id);
    }
  }

  /// Убрать офлайн-копию: файл + запись индекса. Сам трек в библиотеке
  /// остаётся — как «Убрать из офлайна» на десктопе.
  Future<void> remove(String trackId) async {
    final name = state.files[trackId];
    if (name == null) return;
    state = state.copyWith(files: {...state.files}..remove(trackId));
    _saveIndex();
    try {
      final file = _fileOf(name);
      if (file != null && file.existsSync()) await file.delete();
    } catch (_) {
      // Файл не удалился — индекс уже без него, это просто мусор в каталоге.
    }
  }

  Future<String?> toggle(Track track) async {
    if (state.has(track.id)) {
      await remove(track.id);
      return null;
    }
    return download(track);
  }

  /// Скачать все скачиваемые треки списка. Ссылки резолвятся покадрово, прямо
  /// перед каждым треком: подписанный CDN-URL живёт минуты, и пачка ссылок,
  /// взятая заранее, к концу списка протухла бы.
  ///
  /// Возвращает текст итога для снекбара; `null` — качать было нечего.
  Future<String?> downloadAll(String sourceId, List<Track> tracks) async {
    final pending = tracks
        .where((t) => !state.has(t.id) && canDownload(t))
        .toList();
    if (pending.isEmpty) return null;
    if (!beginBatch(sourceId, pending.length)) return 'Уже качаю другой список';

    var failed = 0;
    for (var i = 0; i < pending.length; i++) {
      final err = await download(pending[i]);
      if (err != null) failed++;
      // Пакет мог быть отменён, пока качался трек.
      if (!advanceBatch(failed: err != null)) break;
      if (i < pending.length - 1) await Future<void>.delayed(_betweenTracks);
    }
    endBatch();
    return batchSummary(pending.length, failed);
  }

  /// Занять индикатор пакета. `false` — другой пакет уже идёт: два счётчика на
  /// один индикатор не налезут, да и площадку душить параллельными резолвами
  /// незачем. Публичный, потому что тем же индикатором пользуется сохранение
  /// списка файлами (см. `file_download.dart`).
  bool beginBatch(String sourceId, int total) {
    if (state.batch != null || total == 0) return false;
    state = state.copyWith(
      batch: OfflineBatch(sourceId: sourceId, done: 0, total: total),
    );
    return true;
  }

  /// Отметить трек обработанным. `false` — пакет отменили, дальше не идём.
  bool advanceBatch({bool failed = false}) {
    final batch = state.batch;
    if (batch == null) return false;
    state = state.copyWith(
      batch: batch.copyWith(
        done: batch.done + 1,
        failed: batch.failed + (failed ? 1 : 0),
      ),
    );
    return true;
  }

  void endBatch() => state = state.copyWith(clearBatch: true);

  /// Прервать пакетную загрузку. Трек, который качается сейчас, дойдёт до
  /// конца — рвать запись файла на середине незачем.
  void cancelBatch() => endBatch();

  /// Убрать из офлайна все треки списка.
  Future<int> removeAll(List<Track> tracks) async {
    var n = 0;
    for (final t in tracks) {
      if (!state.has(t.id)) continue;
      await remove(t.id);
      n++;
    }
    return n;
  }

  /// Сколько треков и байт лежит в кеше — для раздела «Хранилище».
  Future<({int count, int bytes})> stats() async {
    var count = 0;
    var bytes = 0;
    for (final name in state.files.values) {
      final file = _fileOf(name);
      if (file == null || !file.existsSync()) continue;
      count++;
      try {
        bytes += await file.length();
      } catch (_) {
        // Файл исчез между проверкой и чтением — просто не считаем его.
      }
    }
    return (count: count, bytes: bytes);
  }

  /// Стереть весь кеш. Возвращает число удалённых файлов.
  Future<int> clearAll() async {
    final names = state.files.values.toList();
    state = state.copyWith(files: const {});
    _saveIndex();
    var deleted = 0;
    for (final name in names) {
      try {
        final file = _fileOf(name);
        if (file != null && file.existsSync()) {
          await file.delete();
          deleted++;
        }
      } catch (_) {
        // Не удалился — остальные всё равно чистим.
      }
    }
    return deleted;
  }
}

/// Качает трек по прямой ссылке в [dir] и возвращает получившийся файл.
///
/// Пишем потоком во временный `.part`: трек это мегабайты, держать их целиком
/// в памяти незачем, а оборванная загрузка не должна оставить огрызок, который
/// сойдёт за готовый файл. Общая для обоих скачиваний — офлайн-копии и
/// сохранения файлом в память телефона.
Future<File> fetchAudioToFile({
  required String url,
  required Map<String, String> headers,
  required Directory dir,
  required String base,
  void Function(double)? onProgress,
}) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = true
      ..headers.addAll(headers);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('CDN ответил ${response.statusCode}');
    }

    final part = File(
      '${dir.path}/.part_${DateTime.now().microsecondsSinceEpoch}',
    );
    final sink = part.openWrite();
    final total = response.contentLength ?? 0;
    var received = 0;
    // Расширение — по первым байтам, как `audio_ext` на ПК: SoundCloud отдаёт
    // и mp3, и m4a, а по URL этого не понять.
    String? ext;
    try {
      await for (final chunk in response.stream) {
        if (ext == null && chunk.length >= 8) ext = _audioExt(chunk);
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : -1);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received == 0) {
      await part.delete();
      throw const HttpException('пустой ответ');
    }

    final name = _uniqueName(dir, base, ext ?? 'mp3');
    return part.rename('${dir.path}/$name');
  } finally {
    client.close();
  }
}

/// Итог пакетной загрузки для снекбара — общий для обоих скачиваний.
String batchSummary(int total, int failed) {
  final ok = total - failed;
  if (failed == 0) return 'Скачано треков: $ok';
  if (ok == 0) return 'Не удалось скачать ни одного трека';
  return 'Скачано $ok из $total, не вышло: $failed';
}

/// «Артист - Название» — то же имя файла, что даёт `trackFileBase` на ПК.
String trackFileBase(Track track) {
  final raw = (track.artist.isEmpty ? '' : '${track.artist} - ') + track.name;
  final safe = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return safe.isEmpty ? 'track' : safe;
}

/// m4a у файлов с боксом `ftyp` в начале, иначе mp3 — порт `audio_ext`.
String _audioExt(List<int> bytes) {
  if (bytes.length > 8 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    return 'm4a';
  }
  return 'mp3';
}

/// Свободное имя вида `База.ext`, `База (2).ext`, … — два разных трека могут
/// называться одинаково.
String _uniqueName(Directory dir, String base, String ext) {
  var name = '$base.$ext';
  var i = 2;
  while (File('${dir.path}/$name').existsSync()) {
    name = '$base ($i).$ext';
    i++;
  }
  return name;
}

/// Коды площадки понятны только разработчику — в снекбар идёт человеческий
/// текст (порт соответствующих строк `dict.ts`).
String _readableError(Object e) {
  final msg = e is Exception ? e.toString() : '$e';
  if (msg.contains('hlsOnly')) {
    return 'Этот трек отдаётся только потоком — сохранить нельзя';
  }
  if (msg.contains('drm')) return 'Трек защищён DRM';
  if (msg.contains('noStream')) return 'Площадка не отдала ссылку на файл';
  if (e is SocketException) return 'Нет соединения';
  return 'Не удалось сохранить: $msg';
}
