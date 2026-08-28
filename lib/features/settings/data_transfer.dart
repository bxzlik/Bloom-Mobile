/// Перенос плейлистов файлом `.bloomplaylist` — «Настройки → Система →
/// Импорт/экспорт».
///
/// Порт десктопного `features/library/lib/playlistTransfer.ts`: тот же формат
/// файла `{version, exported_at, playlists, tracks}` и то же правило импорта —
/// плейлисты создаются с НОВЫМИ id, чтобы не столкнуться с уже существующими,
/// а треки восстанавливаются в хранилище библиотеки.
///
/// Файл ходит в обе стороны, и обе обеспечены здесь:
///
/// - **с ПК к нам** — десктопный снимок трека разбирается отдельно
///   ([_trackFromDesktop]): расходятся ровно три поля, а сквозные id
///   (`sc_`/`ym_`/`ytm_`) на обеих сторонах одни и те же, и по ним трек
///   узнаётся целиком. Десктопные имена полей плейлиста (`trs`/`desc`)
///   читаются наравне с нашими;
/// - **от нас на ПК** — в выгрузку дописываются те же десктопные имена и
///   флаги площадки ([_trackToBundle]), которыми там выбирается резолвер
///   стрима. Десктоп при этом не трогали: файл просто несёт оба набора полей.
///
/// Что не переносится ни в какую сторону — локальные треки: файла на другой
/// стороне нет и взяться ему неоткуда.
library;

import 'dart:convert';

import '../../core/entities/entities.dart';
import '../../core/store/cover_store.dart';
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
///
/// Асинхронный ровно из-за обложек: свои картинки читаются с диска, чтобы
/// уехать в файл целиком (см. [_playlistToBundle]).
Future<String> buildExportAllBundle(LibraryState lib, {DateTime? at}) =>
    _bundle(lib.playlists, lib, at);

/// Один плейлист — «Экспорт плейлиста» из его меню (десктопный
/// `buildExportBundle`). Формат тот же, что у выгрузки всей библиотеки: файл на
/// один плейлист читается тем же импортом, отдельного разбора ему не нужно.
Future<String> buildExportBundle(
  UserPlaylist playlist,
  LibraryState lib, {
  DateTime? at,
}) => _bundle([playlist], lib, at);

/// Треки собираем ТОЛЬКО те, на которые ссылаются [playlists]: файл переноса —
/// про плейлисты, а не про всю библиотеку (десктопный `buildExportAllBundle`
/// делает ровно так же).
Future<String> _bundle(
  List<UserPlaylist> playlists,
  LibraryState lib,
  DateTime? at,
) async {
  final used = <String>{};
  for (final pl in playlists) {
    used.addAll(pl.trackIds);
  }
  final tracks = [
    for (final id in used)
      if (lib.tracks[id] != null) _trackToBundle(lib.tracks[id]!),
  ];
  return const JsonEncoder.withIndent('  ').convert({
    'version': kBundleVersion,
    'exported_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
    'playlists': [for (final pl in playlists) await _playlistToBundle(pl)],
    'tracks': tracks,
  });
}

/// Плейлист для файла: наши поля плюс десктопные имена тех же данных. Состав
/// ПК берёт из `trs`, описание — из `desc`; без них плейлист приехал бы туда
/// пустым и безымянным по содержимому.
///
/// Своя обложка разворачивается в `data:`, как картинки в выгрузке пресетов:
/// имя файла из `covers/` на чужом устройстве не значит ничего, а на ПК
/// обложка плейлиста и хранится ровно такой строкой. Файл от этого тяжелеет
/// (наши обложки — jpeg до 1024px, ~0,2 МБ на плейлист), но обложка, которая
/// не переносится, — не обложка.
Future<Map<String, dynamic>> _playlistToBundle(UserPlaylist playlist) async {
  final json = playlist.toJson();
  if (isLocalCover(playlist.cover)) {
    final data = await encodeLocalImage(playlist.cover);
    // Файла уже нет — уезжаем без обложки: имя из `covers/` там всё равно
    // никому ни о чём не скажет.
    if (data != null) {
      json['cover'] = data;
    } else {
      json.remove('cover');
    }
  }
  return {
    ...json,
    'trs': playlist.trackIds,
    if (playlist.description != null) 'desc': playlist.description,
  };
}

/// Трек для файла: наш снимок плюс те десктопные поля, по которым ПК заведёт
/// стрим. Дублирование дешевле развилки «в какой формат выгружаем»: файл
/// остаётся один и открывается на обеих сторонах.
Map<String, dynamic> _trackToBundle(Track track) {
  final bare = track.id.substring(track.source.prefix.length);
  return {
    ...track.toJson(),
    'dur': _clock(track.duration),
    // Резолвер стрима на ПК выбирается по флагу `_sc`/`_ym`/`_ytm`, а не по
    // префиксу id, поэтому флаг обязателен. Транскодинги десктоп умеет
    // дотянуть по `scId` и сам, но со своими заиграет без единого запроса.
    ...switch (track.source) {
      MusicSource.soundcloud => {
        '_sc': true,
        'scId': int.tryParse(bare) ?? bare,
        if (track.sourceData != null) 'scMedia': track.sourceData,
        if (track.playCount != null) 'scPlaybackCount': track.playCount,
      },
      MusicSource.yandex => {
        '_ym': true,
        'ymTrackId': bare,
        if (track.sourceData?['available'] == false) 'ymAvailable': false,
      },
      MusicSource.ytmusic => {'_ytm': true, 'ytmVideoId': bare},
      // Свой файл с телефона: на ПК его нет и взяться неоткуда — уезжает
      // одними метаданными, ровно как десктопный локальный трек к нам.
      MusicSource.local => const <String, dynamic>{},
    },
  };
}

/// Длительность в десктопном виде — «м:сс» или «ч:мм:сс», как `formatTime` на
/// ПК. Обратное преобразование — [_parseClock].
String _clock(Duration duration) {
  final total = duration.inSeconds;
  final seconds = (total % 60).toString().padLeft(2, '0');
  final minutes = total ~/ 60 % 60;
  if (total < 3600) return '$minutes:$seconds';
  return '${total ~/ 3600}:${minutes.toString().padLeft(2, '0')}:$seconds';
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
Future<ImportResult?> importPlaylistBundle(
  String content,
  LibraryState lib,
  LibraryController library,
) async {
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
  // id из файла → наш сквозной. Обычно это одно и то же, но у треков, которые
  // на ПК завели импортом по ссылке, id свой (см. [_identify]), а состав
  // плейлиста ссылается именно на него.
  final alias = <String, String>{};
  for (final raw in (parsed['tracks'] as List?) ?? const []) {
    final track = trackFromBundle(raw);
    if (track == null) continue;
    final rawId = raw is Map ? raw['id'] : null;
    if (rawId is String && rawId != track.id) alias[rawId] = track.id;
    if (have.containsKey(track.id)) continue;
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
    final seen = <String>{};
    for (final rawId in ids) {
      final id = alias[rawId] ?? rawId;
      final track = have[id] ?? fromFile[id];
      // Трека нет ни в библиотеке, ни в файле — в плейлист попал бы id без
      // строки. Пропускаем, как `whereType` в остальных списках.
      if (track == null) continue;
      // Один трек мог попасть в файл дважды — своим id и импортированным по
      // ссылке; после [_identify] это один и тот же наш id. Состав у нас без
      // повторов (`addTracksToPlaylist`), поэтому второй раз не берём.
      if (!seen.add(id)) continue;
      tracks.add(track);
      if (fromFile.containsKey(id)) restored.add(id);
    }
    library.createPlaylist(
      name,
      tracks: tracks,
      cover: await _coverFromBundle(raw['cover']),
      isAlbum: raw['isAlbum'] == true,
    );
    playlists++;
  }

  return ImportResult(playlists: playlists, tracks: restored.length);
}

/// Обложка плейлиста из файла. Картинка внутри файла (`data:` — так её везёт
/// и ПК, и наша выгрузка) ложится своим файлом в `covers/`; ссылка и наше
/// собственное `local:` остаются как есть — второе значит, что файл вернулся
/// на тот же телефон и картинка на месте.
///
/// `null` вместо картинки — не беда: плейлист просто нарисуется заглушкой из
/// обложек своих треков.
Future<String?> _coverFromBundle(Object? raw) async {
  if (raw is! String || raw.isEmpty) return null;
  final decoded = decodeDataUrl(raw);
  if (decoded == null) return raw;
  return saveLocalImage(decoded.bytes, prefix: 'cover', ext: decoded.ext);
}

/// Снимок трека из файла переноса. Свой узнаёт сам [Track.fromJson];
/// десктопный виден по `dur` вместо `durationMs` и разбирается отдельно.
Track? trackFromBundle(Object? raw) {
  if (raw is! Map) return null;
  return raw['durationMs'] == null && raw['dur'] is String
      ? _trackFromDesktop(raw)
      : Track.fromJson(raw);
}

/// Десктопный снимок → наш трек.
///
/// Расходятся ровно три поля: длительность там строка «м:сс», сырьё площадки
/// разложено по `scMedia`/`ymAvailable`, а `playCount` занят СВОИМ счётчиком
/// прослушиваний (глобальное число лежит в `scPlaybackCount`) — у нас это поле
/// про глобальное, поэтому десктопное не берём вовсе. Остальное совпадает по
/// именам, включая сквозной id, из которого резолвится стрим у Яндекса и YTM.
Track? _trackFromDesktop(Map raw) {
  final rawId = raw['id'];
  if (rawId is! String) return null;
  final found = _identify(raw, rawId);
  // Локальный трек с ПК: файла на телефоне нет и взяться ему неоткуда —
  // площадки за ним не стоит, а `resolveTrackById` спрашивать некого. В
  // плейлист он попал бы строкой, которая молчит на нажатие.
  if (found == null) return null;
  final (source, id) = found;
  return Track(
    id: id,
    name: raw['name'] as String? ?? '',
    artist: raw['artist'] as String? ?? '',
    duration: _parseClock(raw['dur'] as String?),
    source: source,
    cover: raw['cover'] as String?,
    album: raw['album'] as String?,
    year: raw['year'] as String?,
    publisher: raw['publisher'] as String?,
    description: raw['description'] as String?,
    explicit: raw['explicit'] == true,
    genres: (raw['genres'] as List?)?.whereType<String>().toList() ?? const [],
    url: raw['url'] as String?,
    artistId: raw['artistId'] as String?,
    artistAvatar: raw['artistAvatar'] as String?,
    artistVerified: raw['artistVerified'] == true,
    creditedArtist: raw['creditedArtist'] as String?,
    playCount: (raw['scPlaybackCount'] as num?)?.toInt(),
    sourceData: _sourceDataFromDesktop(raw, source),
  );
}

/// Площадка и сквозной id десктопного снимка — `null`, если трек и правда
/// локальный.
///
/// Одного префикса id мало. Треки, заведённые на ПК импортом по ссылке, лежат
/// там под СВОИМ id вида `tr<время><хвост>`: по нашим правилам это «локальный»,
/// хотя играет он с площадки — и такой плейлист приезжал к нам почти пустым.
/// Десктоп и сам выбирает резолвер стрима по флагу `_sc`/`_ym`/`_ytm`, а не по
/// префиксу (ровно поэтому флаг обязателен и в нашей выгрузке — см.
/// [_trackToBundle]), так что идём тем же путём: флаг даёт площадку, её поле
/// (`scId`/`ymTrackId`/`ytmVideoId`) — id, из которого собирается наш сквозной.
(MusicSource, String)? _identify(Map raw, String id) {
  final byPrefix = MusicSource.fromId(id);
  if (byPrefix != MusicSource.local) return (byPrefix, id);
  final source = raw['_sc'] == true
      ? MusicSource.soundcloud
      : raw['_ym'] == true
      ? MusicSource.yandex
      : raw['_ytm'] == true
      ? MusicSource.ytmusic
      : MusicSource.local;
  final bare = switch (source) {
    MusicSource.soundcloud => raw['scId'] ?? raw['scTrackId'],
    MusicSource.yandex => raw['ymTrackId'],
    MusicSource.ytmusic => raw['ytmVideoId'],
    MusicSource.local => null,
  };
  final key = switch (bare) {
    final num n => '${n.toInt()}',
    final String s => s.trim(),
    _ => '',
  };
  // Флаг площадки есть, а её id нет — играть нечем: стрим у всех троих
  // резолвится ровно по нему.
  if (key.isEmpty) return null;
  return (source, '${source.prefix}$key');
}

/// Сырьё площадки из десктопных полей. У SoundCloud это транскодинги, из
/// которых резолвится стрим (`scMedia` — тот же `media` из API, что кладём в
/// `sourceData` мы); у Яндекса — единственная отметка «трек недоступен»;
/// YouTube Music играет по одному id, сырьё ему не нужно.
Map<String, dynamic>? _sourceDataFromDesktop(Map raw, MusicSource source) =>
    switch (source) {
      MusicSource.soundcloud =>
        (raw['scMedia'] as Map?)?.cast<String, dynamic>(),
      MusicSource.yandex when raw['ymAvailable'] == false => const {
        'available': false,
      },
      _ => null,
    };

/// «3:45» или «1:02:03» → длительность. Мусор и пропуск дают ноль: длительность
/// нужна подписи под названием, а не воспроизведению.
Duration _parseClock(String? value) {
  final parts = (value ?? '').split(':');
  if (parts.length < 2 || parts.length > 3) return Duration.zero;
  final nums = [for (final part in parts) int.tryParse(part.trim())];
  if (nums.any((n) => n == null || n < 0)) return Duration.zero;
  return Duration(
    hours: parts.length == 3 ? nums[0]! : 0,
    minutes: nums[parts.length - 2]!,
    seconds: nums.last!,
  );
}
