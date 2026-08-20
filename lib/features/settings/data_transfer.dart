/// Перенос плейлистов файлом `.bloomplaylist` — «Настройки → Система →
/// Импорт/экспорт».
///
/// Порт десктопного `features/library/lib/playlistTransfer.ts`: тот же формат
/// файла `{version, exported_at, playlists, tracks}` и то же правило импорта —
/// плейлисты создаются с НОВЫМИ id, чтобы не столкнуться с уже существующими,
/// а треки восстанавливаются в хранилище библиотеки.
///
/// Отличие от ПК одно и оно от формата самих треков: снимок трека здесь —
/// наш [Track.toJson] (с `sourceData`, из которого резолвится стрим), а на
/// десктопе свой. Поэтому файл с ПК откроется, но играть его треки будет
/// нечем — на импорте они просто отсеются. Совместимость по именам полей мы
/// всё же держим (`trs`/`desc` с ПК читаются наравне с нашими): плейлисты и их
/// состав из десктопного файла достанутся хотя бы теми треками, что уже есть в
/// библиотеке.
library;

import 'dart:convert';

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';

/// Расширение файла переноса — то же, что на ПК.
const String kPlaylistExt = 'bloomplaylist';

/// Версия формата. Как и на десктопе, пока единственная.
const int kBundleVersion = 1;

/// Сколько всего перенеслось — счётчики для тоста.
class ImportResult {
  const ImportResult({required this.playlists, required this.tracks});

  final int playlists;
  final int tracks;
}

/// Все плейлисты плюс метаданные их треков — текст файла для выгрузки.
String buildExportAllBundle(LibraryState lib, {DateTime? at}) =>
    _bundle(lib.playlists, lib, at);

/// Один плейлист — «Экспорт плейлиста» из его меню (десктопный
/// `buildExportBundle`). Формат тот же, что у выгрузки всей библиотеки: файл на
/// один плейлист читается тем же импортом, отдельного разбора ему не нужно.
String buildExportBundle(
  UserPlaylist playlist,
  LibraryState lib, {
  DateTime? at,
}) => _bundle([playlist], lib, at);

/// Треки собираем ТОЛЬКО те, на которые ссылаются [playlists]: файл переноса —
/// про плейлисты, а не про всю библиотеку (десктопный `buildExportAllBundle`
/// делает ровно так же).
String _bundle(List<UserPlaylist> playlists, LibraryState lib, DateTime? at) {
  final used = <String>{};
  for (final pl in playlists) {
    used.addAll(pl.trackIds);
  }
  final tracks = [
    for (final id in used)
      if (lib.tracks[id] != null) lib.tracks[id]!.toJson(),
  ];
  return const JsonEncoder.withIndent('  ').convert({
    'version': kBundleVersion,
    'exported_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
    'playlists': [for (final pl in playlists) pl.toJson()],
    'tracks': tracks,
  });
}

/// Имя файла для выгрузки одного плейлиста. Символы, которых файловые системы
/// не терпят, заменяем подчёркиванием — как `safe` в десктопном `PlMenu`;
/// плейлист без названия уходит под общим именем, безымянного файла быть не
/// должно.
String playlistFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return '${safe.isEmpty ? 'bloom-playlist' : safe}.$kPlaylistExt';
}

/// Разобрать файл и создать плейлисты. `null` — файл не наш (не разобрался как
/// JSON-объект); пустой результат — плейлистов внутри нет.
///
/// Плейлисты создаются заново, а не сливаются с одноимёнными: у файла и у
/// библиотеки свои истории правок, и «дополнить существующий» значило бы молча
/// перемешать два состава. Так же и на десктопе.
ImportResult? importPlaylistBundle(
  String content,
  LibraryState lib,
  LibraryController library,
) {
  Object? parsed;
  try {
    parsed = jsonDecode(content);
  } catch (_) {
    return null;
  }
  if (parsed is! Map) return null;
  final rawPlaylists = parsed['playlists'];
  if (rawPlaylists is! List) return null;
  if (rawPlaylists.isEmpty) {
    return const ImportResult(playlists: 0, tracks: 0);
  }

  // Снимки треков из файла: id → трек. Тем, что уже лежат в библиотеке,
  // предпочитаем СВОИ — у них свежее `sourceData`, а у файла оно может быть
  // годовой давности.
  final have = lib.tracks;
  final fromFile = <String, Track>{};
  for (final raw in (parsed['tracks'] as List?) ?? const []) {
    final track = Track.fromJson(raw);
    if (track == null || have.containsKey(track.id)) continue;
    fromFile[track.id] = track;
  }

  var playlists = 0;
  final restored = <String>{};
  for (final raw in rawPlaylists) {
    if (raw is! Map) continue;
    final name = raw['name'];
    if (name is! String) continue;
    // `trackIds` — наш ключ, `trs` — десктопный.
    final ids =
        (raw['trackIds'] as List?)?.whereType<String>().toList() ??
        (raw['trs'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final tracks = <Track>[];
    for (final id in ids) {
      final track = have[id] ?? fromFile[id];
      // Трека нет ни в библиотеке, ни в файле — в плейлист попал бы id без
      // строки. Пропускаем, как `whereType` в остальных списках.
      if (track == null) continue;
      tracks.add(track);
      if (fromFile.containsKey(id)) restored.add(id);
    }
    library.createPlaylist(
      name,
      tracks: tracks,
      cover: raw['cover'] as String?,
      isAlbum: raw['isAlbum'] == true,
    );
    playlists++;
  }

  return ImportResult(playlists: playlists, tracks: restored.length);
}
