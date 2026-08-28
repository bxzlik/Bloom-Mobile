/// Сетевой smoke против живого API Яндекс.Музыки (не для CI) — сосед
/// `sc_smoke.dart`. Провайдер это чистый Dart, Flutter-рантайм не нужен.
///
/// Запуск с готовым токеном:
///   `dart run tool/ym_smoke.dart <OAuth-токен>`
///   (или положить его в переменную окружения YM_TOKEN)
///
/// Запуск без токена проходит device-flow: скрипт печатает адрес и код,
/// ждёт подтверждения в браузере и дальше идёт с полученным токеном — им же
/// можно пользоваться в следующих прогонах.
library;

// ignore_for_file: avoid_print — это консольный скрипт, вывод и есть результат.

import 'dart:io';

import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/providers/yandex/ym_provider.dart';
import 'package:bloom/providers/yandex/yandex.dart' as ym;

var failed = 0;

void check(bool cond, String what) {
  if (!cond) {
    failed++;
    stderr.writeln('FAIL: $what');
  }
}

Future<String?> deviceFlow() async {
  final d = await ym.authStart('bloomsmoke0000ff');
  print('Открой ${d.verificationUrl} и введи код: ${d.userCode}');
  final deadline = DateTime.now().add(d.expiresIn);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(d.interval);
    final r = await ym.authPoll(d.deviceCode);
    if (!r.isPending) return r.token;
    stdout.write('.');
  }
  return null;
}

Future<void> main(List<String> args) async {
  final token =
      args.firstOrNull ??
      Platform.environment['YM_TOKEN'] ??
      await deviceFlow();
  if (token == null || token.isEmpty) {
    stderr.writeln('нет токена — авторизация не завершилась');
    exit(1);
  }
  ym.setToken(token);
  print('token: ${token.substring(0, 6)}… (сохрани в YM_TOKEN)');

  const provider = YandexProvider();
  check(provider.isEnabled, 'провайдер выключен при живом токене');

  // Подписка: без Плюса стрим отдаст 403, и это ожидаемый исход прогона.
  final plus = await ym.hasPlus();
  print('Яндекс Плюс: $plus');

  // Поиск — все четыре раздела одним запросом.
  final found = await provider.search('земфира');
  print(
    'search: ${found.tracks.length} треков, ${found.artists.length} артистов, '
    '${found.albums.length} альбомов, ${found.playlists.length} плейлистов',
  );
  check(found.tracks.isNotEmpty, 'пустая выдача поиска');
  check(found.artists.isNotEmpty, 'поиск без артистов');

  // Вторая страница: свой пейджер, а не offset общего стора.
  final more = await provider.loadMoreTracks('земфира', 24);
  print('loadMoreTracks: ещё ${more?.tracks.length ?? 0} треков');
  check((more?.tracks.length ?? 0) > 0, 'вторая страница пуста');
  final firstIds = found.tracks.map((t) => t.id).toSet();
  check(
    (more?.tracks.any((t) => !firstIds.contains(t.id)) ?? false),
    'вторая страница целиком повторяет первую',
  );

  // Стрим: подписанная ссылка + реальные байты range-GET, как это сделает
  // плеер.
  final track = found.tracks.firstWhere(
    (t) => t.sourceData?['available'] != false,
    orElse: () => found.tracks.first,
  );
  try {
    final stream = await provider.resolveStream(track);
    check(stream != null && stream.url.contains('/get-mp3/'), 'стрим не mp3');
    print('stream: ${stream?.url.substring(0, 60)}…');

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(stream!.url));
    req.headers.add('Range', 'bytes=0-1023');
    final resp = await req.close();
    final bytes = await resp.fold<int>(0, (n, ch) => n + ch.length);
    check(
      resp.statusCode == 200 || resp.statusCode == 206,
      'CDN status ${resp.statusCode}',
    );
    check(bytes > 0, 'CDN отдал 0 байт');
    print('bytes: $bytes (status ${resp.statusCode})');
    client.close();
  } catch (e) {
    // Без Плюса это штатный исход — трек просто не играет.
    check(plus == false, 'стрим упал при активном Плюсе: $e');
    print('stream: недоступен ($e)');
  }

  // Страница артиста: «Популярные» + дискография + альбомы + похожие.
  final artistPage = await provider.getArtist(found.artists.first.id);
  print(
    'getArtist ${artistPage?.artist.name}: '
    '${artistPage?.topTracks.length} популярных, ${artistPage?.tracks.length} треков, '
    '${artistPage?.albums.length} альбомов, ${artistPage?.similarArtists.length} похожих',
  );
  check(
    (artistPage?.topTracks.length ?? 0) > 0,
    'у артиста пусто в популярных',
  );
  check(
    artistPage?.topTracks.every((t) => t.name.isNotEmpty) ?? false,
    'популярные без названий — brief-info отдал голые id, добор не сработал',
  );

  // Альбом: треки собираются из всех volumes.
  final albums = artistPage?.albums ?? const [];
  if (albums.isNotEmpty) {
    final album = await provider.getAlbum(albums.first.id);
    print('getAlbum ${album?.playlist.title}: ${album?.tracks.length} треков');
    check((album?.tracks.length ?? 0) > 0, 'альбом без треков');
    check(
      album?.playlist.ownerName?.isNotEmpty ?? false,
      'у альбома нет исполнителя в шапке',
    );
  }

  // Плейлист из выдачи — старый формат /users/<owner>/playlists/<kind>.
  if (found.playlists.isNotEmpty) {
    final pl = await provider.getPlaylist(found.playlists.first.id);
    print('getPlaylist ${pl?.playlist.title}: ${pl?.tracks.length} треков');
    check((pl?.tracks.length ?? 0) > 0, 'плейлист без треков');
  }

  // Ссылки: трек, альбом, артист. Id берётся из живой выдачи, а не прибит.
  final trackNum = ymNumericId(track.id);
  final resolvedTrack = await provider.resolveUrl(
    'https://music.yandex.ru/track/$trackNum',
  );
  check(resolvedTrack is ResolvedTrack, 'ссылка на трек не дала трек');

  if (albums.isNotEmpty) {
    final albumNum = ymNumericId(albums.first.id);
    final resolvedAlbum = await provider.resolveUrl(
      'https://music.yandex.ru/album/$albumNum',
    );
    check(
      resolvedAlbum is ResolvedSet && resolvedAlbum.playlist.isAlbum,
      'ссылка на альбом не дала альбом',
    );
    // Ссылка «трек внутри альбома» обязана открыть ТРЕК, а не альбом.
    final inAlbum = await provider.resolveUrl(
      'https://music.yandex.ru/album/$albumNum/track/$trackNum',
    );
    check(inAlbum is ResolvedTrack, 'ссылка album/track открыла не трек');
  }

  final artistNum = ymNumericId(found.artists.first.id);
  final resolvedArtist = await provider.resolveUrl(
    'https://music.yandex.ru/artist/$artistNum',
  );
  check(resolvedArtist is ResolvedArtist, 'ссылка на артиста не дала артиста');

  // Чужая ссылка уходит дальше по реестру, без запроса к Яндексу.
  check(
    await provider.resolveUrl('https://soundcloud.com/x/y') == null,
    'Яндекс взялся резолвить чужую ссылку',
  );

  // Витрины главной (UI под них ещё нет — проверяем, что данные приходят).
  final charts = await provider.getCharts();
  print('getCharts: ${charts?.length} треков');
  check((charts?.length ?? 0) > 0, 'чарт пуст');

  final releases = await provider.getNewReleases();
  final newCount = releases is NewAlbums ? releases.albums.length : 0;
  print('getNewReleases: $newCount альбомов');
  check(newCount > 0, 'новинки пусты');

  print(failed == 0 ? '\nВСЁ ОК' : '\nПРОВАЛОВ: $failed');
  exit(failed == 0 ? 0 : 1);
}
