/// SoundCloud как [MusicProvider]: тонкий слой поверх порта api-v2
/// (`soundcloud.dart`), который приводит `ScRaw*` к общим сущностям.
///
/// Вся сетевая логика и её гочи живут этажом ниже — здесь только маппинг и
/// сборка страниц.
library;

import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import 'models.dart';
import 'soundcloud.dart' as sc;

/// Сквозные id: числовой id SoundCloud с префиксом источника.
String scTrackId(int id) => 'sc_$id';
String scArtistId(int id) => 'sc_artist_$id';
String scSetId(int id, {required bool isAlbum}) =>
    isAlbum ? 'sc_album_$id' : 'sc_playlist_$id';

/// Числовой id обратно из сквозного. Небезопасные значения дают 0 — провайдер
/// тогда просто ничего не найдёт, вместо падения.
int scNumericId(String entityId) => int.tryParse(entityId.split('_').last) ?? 0;

String? _blankToNull(String s) => s.isEmpty ? null : s;

Track trackFromSc(ScRawTrack t) => Track(
  id: scTrackId(t.id),
  name: t.title,
  artist: t.artist,
  duration: Duration(milliseconds: t.duration),
  cover: t.artwork,
  source: MusicSource.soundcloud,
  album: _blankToNull(t.album),
  year: _blankToNull(t.year),
  publisher: _blankToNull(t.publisher),
  description: _blankToNull(t.description),
  explicit: t.explicit,
  genres: t.genre == null ? const [] : [t.genre!.toLowerCase()],
  url: t.permalink,
  artistId: t.artistScId == null ? null : scArtistId(t.artistScId!),
  artistAvatar: t.artistAvatar,
  artistVerified: t.artistVerified,
  creditedArtist: _blankToNull(t.creditedArtist),
  playCount: t.playbackCount,
  // Стрим резолвится из `media.transcodings` — держим сырьё при треке.
  sourceData: t.media,
);

Artist artistFromSc(ScRawArtist a) => Artist(
  id: scArtistId(a.id),
  // У SC `title` — это username, а `artist` — full_name.
  name: a.title,
  fullName: _blankToNull(a.artist),
  avatar: a.artwork,
  permalink: a.permalink,
  followers: a.followers,
  source: MusicSource.soundcloud,
);

Playlist setFromSc(ScRawPlaylist p, {required bool isAlbum}) => Playlist(
  id: scSetId(p.id, isAlbum: isAlbum),
  title: p.title,
  cover: p.artwork,
  // У SC отсутствующий счётчик приходит нулём — «0 треков» под альбомом с
  // четырнадцатью хуже, чем ничего.
  trackCount: p.trackCount > 0 ? p.trackCount : null,
  ownerName: _blankToNull(p.artist),
  ownerAvatar: p.artistAvatar,
  year: _blankToNull(p.year),
  duration: p.duration > 0 ? Duration(milliseconds: p.duration) : null,
  sourceUrl: p.permalink,
  isAlbum: isAlbum,
  source: MusicSource.soundcloud,
);

Artist _artistFromUser(ScRawUser u) => Artist(
  id: scArtistId(u.id),
  name: u.username,
  fullName: _blankToNull(u.fullName),
  avatar: u.avatar,
  bannerUrl: u.banner,
  permalink: u.permalink,
  followers: u.followers,
  description: _blankToNull(u.description),
  website: u.website,
  source: MusicSource.soundcloud,
);

class SoundCloudProvider extends MusicProvider {
  const SoundCloudProvider();

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    final sortParam = sort == SearchSort.newest ? 'new' : 'relevance';
    // Четыре эндпоинта параллельно; упавший раздел просто не вносит вклад.
    final results = await Future.wait([
      sc
          .searchTracks(query, limit: 30, sort: sortParam)
          .then<Object?>((v) => v, onError: (_) => null),
      sc
          .searchArtists(query, limit: 12)
          .then<Object?>((v) => v, onError: (_) => null),
      sc
          .searchAlbums(query, limit: 12)
          .then<Object?>((v) => v, onError: (_) => null),
      sc
          .searchPlaylists(query, limit: 12)
          .then<Object?>((v) => v, onError: (_) => null),
    ]);

    final tracks = results[0] as ScPage<ScRawTrack>?;
    final artists = results[1] as ScPage<ScRawArtist>?;
    final albums = results[2] as ScPage<ScRawPlaylist>?;
    final playlists = results[3] as ScPage<ScRawPlaylist>?;

    return SearchResults(
      tracks: tracks?.items.map(trackFromSc).toList() ?? const [],
      artists: artists?.items.map(artistFromSc).toList() ?? const [],
      albums:
          albums?.items.map((p) => setFromSc(p, isAlbum: true)).toList() ??
          const [],
      playlists:
          playlists?.items.map((p) => setFromSc(p, isAlbum: false)).toList() ??
          const [],
      tracksHasMore: tracks?.hasMore ?? false,
    );
  }

  @override
  Future<TrackPage?> loadMoreTracks(
    String query,
    int offset, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    final page = await sc.searchTracks(
      query,
      limit: 30,
      offset: offset,
      sort: sort == SearchSort.newest ? 'new' : 'relevance',
    );
    return TrackPage(
      tracks: page.items.map(trackFromSc).toList(),
      hasMore: page.hasMore,
    );
  }

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    // Чужую ссылку отдаём дальше по реестру, не гоняя через SC `/resolve`:
    // площадки опрашиваются по очереди, и лишний запрос — это лишние секунды
    // ожидания перед той, что ссылку действительно понимает.
    final u = url.trim().toLowerCase();
    if (!u.contains('soundcloud.com') && !u.contains('snd.sc')) return null;
    final r = await sc.resolveUrl(url);
    if (r == null) return null;
    switch (r.kind) {
      case 'track':
        return ResolvedTrack(trackFromSc(r.track!));
      case 'artist':
        // Ссылка на аккаунт (`/username`) — не одинокая карточка артиста, а
        // профиль: шапка, плейлисты аккаунта и лайки. Так же на десктопе.
        return ResolvedProfile(await _profile(r.artist!));
      case 'album':
        return ResolvedSet(setFromSc(r.playlist!, isAlbum: true));
      case 'playlist':
        return ResolvedSet(setFromSc(r.playlist!, isAlbum: false));
      default:
        return null;
    }
  }

  /// Профиль аккаунта: артист, обогащённый `getUser`, его плейлисты и лайки.
  /// Три эндпоинта параллельно; каждый гасит свою ошибку в пустоту, поэтому
  /// недоступные лайки не уносят с собой всю шапку.
  Future<ProfileData> _profile(ScRawArtist raw) async {
    final userId = '${raw.id}';
    final parts = await Future.wait([
      sc.getUser(userId).then<Object?>((v) => v, onError: (_) => null),
      sc.userPlaylists(userId).then<Object?>((v) => v, onError: (_) => null),
      sc.userLikes(userId).then<Object?>((v) => v, onError: (_) => null),
    ]);
    final user = parts[0] as ScRawUser?;
    final playlists = (parts[1] as List<ScRawPlaylist>?) ?? const [];
    final likes = (parts[2] as List<ScRawTrack>?) ?? const [];

    return ProfileData(
      artist: user == null ? artistFromSc(raw) : _artistFromUser(user),
      playlists: playlists.map((p) => setFromSc(p, isAlbum: false)).toList(),
      likes: likes.map(trackFromSc).toList(),
    );
  }

  @override
  Future<Track?> resolveTrackById(String id) async {
    final raw = await sc.trackById(scNumericId(id));
    return raw == null ? null : trackFromSc(raw);
  }

  @override
  Future<ArtistPageData?> getArtist(String id) async {
    final userId = '${scNumericId(id)}';
    // Всё параллельно: страница артиста собирается из шести разных эндпоинтов,
    // последовательно это заняло бы секунды. Каждый уже гасит свои ошибки в
    // пустоту, кроме getUser — без него страницу рисовать нечем.
    final parts = await Future.wait([
      sc.getUser(userId).then<Object?>((v) => v, onError: (_) => null),
      sc.artistTopTracks(userId).then<Object?>((v) => v, onError: (_) => null),
      sc.artistData(userId).then<Object?>((v) => v, onError: (_) => null),
      sc.relatedArtists(userId).then<Object?>((v) => v, onError: (_) => null),
      sc.userPlaylists(userId).then<Object?>((v) => v, onError: (_) => null),
      sc.artistReposts(userId).then<Object?>((v) => v, onError: (_) => null),
    ]);

    final user = parts[0] as ScRawUser?;
    if (user == null) return null;
    final top = (parts[1] as List<ScRawTrack>?) ?? const [];
    final data = parts[2] as ScArtistData?;
    final related = (parts[3] as List<ScRawArtist>?) ?? const [];
    final playlists = (parts[4] as List<ScRawPlaylist>?) ?? const [];
    final reposts = parts[5] as ScRepostsPage?;

    return ArtistPageData(
      artist: _artistFromUser(user),
      topTracks: top.map(trackFromSc).toList(),
      tracks: data?.tracks.map(trackFromSc).toList() ?? const [],
      albums:
          data?.albums.map((p) => setFromSc(p, isAlbum: true)).toList() ??
          const [],
      playlists: playlists.map((p) => setFromSc(p, isAlbum: false)).toList(),
      reposts: reposts?.items.map(_repostFromSc).toList() ?? const [],
      similarArtists: related.map(artistFromSc).toList(),
      tracksCursor: data?.tracksNext,
      repostsCursor: reposts?.next,
    );
  }

  @override
  Future<SetContent?> getAlbum(String id) => _getSet(id, isAlbum: true);

  @override
  Future<SetContent?> getPlaylist(String id) => _getSet(id, isAlbum: false);

  Future<SetContent?> _getSet(String id, {required bool isAlbum}) async {
    final full = await sc.playlistById(scNumericId(id));
    final tracks = full.tracks.map(trackFromSc).toList();
    return SetContent(
      playlist: Playlist(
        id: id,
        title: full.title,
        cover: full.cover,
        trackCount: full.trackCount > 0 ? full.trackCount : tracks.length,
        ownerName: _blankToNull(full.ownerName),
        ownerAvatar: full.ownerAvatar,
        year: _blankToNull(full.year),
        isAlbum: isAlbum,
        source: MusicSource.soundcloud,
      ),
      tracks: tracks,
    );
  }

  @override
  Future<TrackPage?> getArtistTracksPage(String cursor) async {
    final page = await sc.artistTracksPage(cursor);
    return TrackPage(
      tracks: page.tracks.map(trackFromSc).toList(),
      hasMore: page.next != null,
      cursor: page.next,
    );
  }

  @override
  Future<RepostPage?> getArtistRepostsPage(String cursor) async {
    final page = await sc.artistRepostsPage(cursor);
    return RepostPage(
      reposts: page.items.map(_repostFromSc).toList(),
      cursor: page.next,
    );
  }

  @override
  Future<PlayableStream?> resolveStream(Track track) async {
    final stream = await sc.streamUrl(track.sourceData);
    return PlayableStream(url: stream.url, isHls: stream.isHls);
  }

  /// Скачать можно всё, у чего осталось сырьё площадки: есть ли среди
  /// транскодингов progressive — выяснится только при резолве.
  @override
  bool canDownload(Track track) => track.sourceData != null;

  @override
  Future<PlayableStream?> resolveDownload(Track track) async {
    final stream = await sc.streamUrl(track.sourceData, progressiveOnly: true);
    return PlayableStream(url: stream.url, isHls: stream.isHls);
  }
}

RepostItem _repostFromSc(ScRepostItem item) => item.kind == 'track'
    ? RepostTrack(trackFromSc(item.track!))
    : RepostSet(setFromSc(item.playlist!, isAlbum: item.kind == 'album'));
