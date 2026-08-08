/// Контракт музыкального провайдера — порт
/// `src/features/providers/model/types.ts` из десктопного Bloom.
///
/// Единственное, что реализует площадка. Провайдер маппит свою выдачу в общие
/// [Track]/[Artist]/[Playlist]; весь UX (поиск, страницы, плеер) общий и о
/// площадке не знает.
///
/// Необязательных методов в Dart нет, поэтому «не поддерживаю» выражается
/// возвратом `null` из базовой реализации — вызывающий проверяет результат, а
/// не наличие метода (как `p.getArtist?` на десктопе).
library;

import '../entities/entities.dart';

enum SearchSort {
  /// По релевантности (по умолчанию).
  relevance,

  /// Сначала новые — у SoundCloud это `&sort=created_at`.
  newest,
}

/// Нормализованная поисковая выдача. Все провайдеры приводят ответы к ней,
/// поэтому UI поиска один на всех. Альбомы — тот же [Playlist], их рисует та же
/// карточка.
class SearchResults {
  final List<Artist> artists;
  final List<Playlist> playlists;
  final List<Playlist> albums;
  final List<Track> tracks;

  /// Есть ли ещё треки (для «загрузить ещё»).
  final bool tracksHasMore;

  const SearchResults({
    this.artists = const [],
    this.playlists = const [],
    this.albums = const [],
    this.tracks = const [],
    this.tracksHasMore = false,
  });

  static const empty = SearchResults();

  bool get isEmpty =>
      artists.isEmpty && playlists.isEmpty && albums.isEmpty && tracks.isEmpty;
}

/// Профиль (ссылка на `/username`): артист + его плейлисты + лайки.
class ProfileData {
  final Artist artist;
  final List<Playlist> playlists;
  final List<Track> likes;

  const ProfileData({
    required this.artist,
    this.playlists = const [],
    this.likes = const [],
  });
}

/// Элемент ленты репостов артиста — трек ИЛИ плейлист/альбом. Лента смешанная и
/// порядок важен, поэтому union, а не раздельные списки.
sealed class RepostItem {
  const RepostItem();
}

class RepostTrack extends RepostItem {
  final Track track;
  const RepostTrack(this.track);
}

class RepostSet extends RepostItem {
  final Playlist playlist;
  const RepostSet(this.playlist);
}

/// Результат резолва вставленной ссылки.
sealed class ResolvedUrl {
  const ResolvedUrl();
}

class ResolvedTrack extends ResolvedUrl {
  final Track track;
  const ResolvedTrack(this.track);
}

class ResolvedArtist extends ResolvedUrl {
  final Artist artist;
  const ResolvedArtist(this.artist);
}

class ResolvedSet extends ResolvedUrl {
  final Playlist playlist;
  const ResolvedSet(this.playlist);
}

class ResolvedProfile extends ResolvedUrl {
  final ProfileData profile;
  const ResolvedProfile(this.profile);
}

/// Новинки площадки. У Яндекса/YTM это свежие альбомы, у SoundCloud — треки
/// «New & Hot»: глобальной ленты альбомов у него нет. Поэтому union — блок сам
/// решает, чем рендерить.
sealed class NewReleases {
  const NewReleases();
}

class NewAlbums extends NewReleases {
  final List<Playlist> albums;
  const NewAlbums(this.albums);
}

class NewTracks extends NewReleases {
  final List<Track> tracks;
  const NewTracks(this.tracks);
}

/// Контент страницы артиста.
class ArtistPageData {
  /// Артист, обогащённый followers/description/website/bannerUrl.
  final Artist artist;

  /// Секция «Популярные».
  final List<Track> topTracks;

  /// Все треки артиста (секция «Треки» с «загрузить ещё»).
  final List<Track> tracks;
  final List<Playlist> albums;
  final List<Playlist> playlists;

  /// Репосты; пусто у площадок без них.
  final List<RepostItem> reposts;

  /// Похожие исполнители; пусто у площадок, которые их не отдают.
  final List<Artist> similarArtists;

  /// Непрозрачный курсор следующей страницы треков (null — больше нет).
  final String? tracksCursor;
  final String? repostsCursor;

  const ArtistPageData({
    required this.artist,
    this.topTracks = const [],
    this.tracks = const [],
    this.albums = const [],
    this.playlists = const [],
    this.reposts = const [],
    this.similarArtists = const [],
    this.tracksCursor,
    this.repostsCursor,
  });
}

/// Порция треков + курсор/флаг продолжения.
class TrackPage {
  final List<Track> tracks;
  final bool hasMore;

  /// Непрозрачный курсор, если площадка листает им, а не смещением.
  final String? cursor;

  const TrackPage({this.tracks = const [], this.hasMore = false, this.cursor});
}

class RepostPage {
  final List<RepostItem> reposts;
  final String? cursor;
  const RepostPage({this.reposts = const [], this.cursor});
}

/// Содержимое альбома или плейлиста.
class SetContent {
  final Playlist playlist;
  final List<Track> tracks;
  const SetContent({required this.playlist, this.tracks = const []});
}

/// Играбельный поток трека.
class PlayableStream {
  final String url;

  /// HLS требует от плеера другого обращения, чем progressive-файл.
  final bool isHls;

  /// Заголовки, без которых CDN не отдаст байты (у SoundCloud не нужны).
  final Map<String, String> headers;

  const PlayableStream({
    required this.url,
    this.isHls = false,
    this.headers = const {},
  });
}

abstract class MusicProvider {
  const MusicProvider();

  MusicSource get source;

  /// Технический id (`source.id`); отдельный геттер — чтобы реестр не зависел
  /// от enum, когда появятся площадки вне него.
  String get id => source.id;

  String get label => source.label;

  /// Включён ли провайдер прямо сейчас (Яндекс — только после логина).
  bool get isEnabled => true;

  /// Поиск. Возвращает выдачу целиком; отсутствующие разделы просто пустые.
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  });

  /// Догрузить ещё треки. `offset` — сколько уже показано. `null` —
  /// пагинации нет.
  Future<TrackPage?> loadMoreTracks(
    String query,
    int offset, {
    SearchSort sort = SearchSort.relevance,
  }) async => null;

  /// Резолв вставленной ссылки этого источника.
  Future<ResolvedUrl?> resolveUrl(String url) async => null;

  /// Ре-резолв одного трека по сквозному id — для проигрывания из «недавних»
  /// после рестарта, когда трека уже нет в памяти.
  Future<Track?> resolveTrackById(String id) async => null;

  Future<ArtistPageData?> getArtist(String id) async => null;

  Future<SetContent?> getAlbum(String id) async => null;

  Future<SetContent?> getPlaylist(String id) async => null;

  /// Догрузка треков артиста по курсору из [ArtistPageData.tracksCursor].
  Future<TrackPage?> getArtistTracksPage(String cursor) async => null;

  Future<RepostPage?> getArtistRepostsPage(String cursor) async => null;

  /// Витрина на главной: чарт площадки. `null` — не участвует.
  Future<List<Track>?> getCharts() async => null;

  Future<NewReleases?> getNewReleases() async => null;

  /// Играбельный URL трека этой площадки.
  Future<PlayableStream?> resolveStream(Track track) async => null;

  /// Умеет ли площадка отдавать трек ФАЙЛОМ — порт `isDownloadable` с
  /// десктопа. Отдельно от [resolveStream]: играть можно и HLS, а сохранить
  /// на диск — нет.
  bool canDownload(Track track) => false;

  /// Ссылка на файл трека для офлайн-копии. Отличается от [resolveStream] тем,
  /// что обязана вернуть цельный файл (progressive), а не плейлист кусков;
  /// бросает, если у трека такого варианта нет.
  Future<PlayableStream?> resolveDownload(Track track) async => null;
}
