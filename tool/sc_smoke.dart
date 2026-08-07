/// Сетевой smoke против живого api-v2 (не для CI) — порт `sc_smoke` из
/// десктопного `soundcloud.rs`. Запуск: `dart run tool/sc_smoke.dart`.
///
/// Не требует Flutter-рантайма: провайдер — чистый Dart.
library;

// ignore_for_file: avoid_print — это консольный скрипт, вывод и есть результат.

import 'dart:io';

import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/providers/soundcloud/sc_provider.dart';
import 'package:bloom/providers/soundcloud/soundcloud.dart';

Future<void> main() async {
  var failed = 0;
  void check(bool cond, String what) {
    if (!cond) {
      failed++;
      stderr.writeln('FAIL: $what');
    }
  }

  // Поиск треков + маппинг.
  final page = await searchTracks('daft punk', limit: 5);
  check(page.items.isNotEmpty, 'пустая выдача поиска');
  final t = page.items.first;
  check(t.id > 0 && t.title.isNotEmpty, 'трек без id/названия');
  print(
    'track: ${t.artist} — ${t.title} (id ${t.id}, media: ${t.media != null})',
  );
  print('client_id: ${activeClientId()}');

  // Резолв стрима из media.transcodings.
  final stream = await streamUrl(t.media);
  check(stream.url.startsWith('http'), 'стрим не url');
  final head = stream.url.substring(0, stream.url.length.clamp(0, 60));
  print('stream: hls=${stream.isHls} url=$head…');

  // Байты реально отдаются (range-GET, как это сделает плеер).
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(stream.url));
  req.headers.add('Range', 'bytes=0-1023');
  final resp = await req.close();
  final bytes = await resp.fold<int>(0, (n, ch) => n + ch.length);
  check(
    resp.statusCode == 200 || resp.statusCode == 206,
    'CDN status ${resp.statusCode}',
  );
  print('cdn: status ${resp.statusCode}, $bytes байт');
  client.close();

  // Артист: поиск → профиль.
  final arts = await searchArtists('skrillex', limit: 3);
  check(arts.items.isNotEmpty, 'пустая выдача артистов');
  final a = arts.items.first;
  final user = await getUser('${a.id}');
  check(user != null && user.id == a.id, 'get_user не сошёлся');
  print('artist: ${user?.username} (followers ${user?.followers})');

  // Топ-треки и данные артиста.
  final top = await artistTopTracks('${a.id}', artistName: a.title);
  print('top tracks: ${top.length}');
  final data = await artistData('${a.id}', artistName: a.title);
  print(
    'artist data: ${data.tracks.length} треков, ${data.albums.length} альбомов',
  );
  final rel = await relatedArtists('${a.id}');
  print('related: ${rel.length}');

  // Резолв permalink-ссылки трека.
  final resolved = await resolveUrl(t.permalink!);
  check(resolved?.kind == 'track', 'resolve не распознал трек');
  print('resolve ok');

  // ── Контракт провайдера поверх того же порта ───────────────────────────
  print('\n— провайдер —');
  final registry = ProviderRegistry()..register(const SoundCloudProvider());

  final results = await registry.searchAll('daft punk');
  check(results.tracks.isNotEmpty, 'пустая выдача через реестр');
  print(
    'searchAll: ${results.tracks.length} треков, ${results.artists.length} артистов, '
    '${results.albums.length} альбомов, ${results.playlists.length} плейлистов',
  );

  final entity = results.tracks.first;
  check(entity.id.startsWith('sc_'), 'id без префикса источника: ${entity.id}');
  check(entity.duration > Duration.zero, 'нулевая длительность');

  // Плеер ходит именно так: провайдер по префиксу id → стрим.
  final provider = registry.forEntity(entity.id);
  check(provider != null, 'реестр не нашёл провайдера по id трека');
  final playable = await provider!.resolveStream(entity);
  check(
    playable != null && playable.url.startsWith('http'),
    'стрим не резолвится',
  );
  print('resolveStream: hls=${playable?.isHls}');

  // Страница артиста — шесть эндпоинтов параллельно.
  final artistEntity = results.artists.isNotEmpty
      ? results.artists.first
      : (await registry.searchAll('skrillex')).artists.first;
  final artistPage = await provider.getArtist(artistEntity.id);
  check(artistPage != null, 'страница артиста не собралась');
  print(
    'getArtist ${artistPage?.artist.name}: топ ${artistPage?.topTracks.length}, '
    'треков ${artistPage?.tracks.length}, альбомов ${artistPage?.albums.length}, '
    'плейлистов ${artistPage?.playlists.length}, '
    'похожих ${artistPage?.similarArtists.length}, '
    'репостов ${artistPage?.reposts.length}',
  );
  check(
    (artistPage?.topTracks.length ?? 0) > 0,
    'у артиста пусто в популярных',
  );

  // Альбом артиста открывается по своему сквозному id.
  final albums = artistPage?.albums ?? const [];
  final album = albums.isEmpty
      ? null
      : await provider.getAlbum(albums.first.id);
  if (album != null) {
    print('getAlbum ${album.playlist.title}: ${album.tracks.length} треков');
    check(album.tracks.isNotEmpty, 'альбом без треков');
  }

  print(failed == 0 ? '\nВСЁ ОК' : '\nПРОВАЛОВ: $failed');
  exit(failed == 0 ? 0 : 1);
}
