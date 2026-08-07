/// Библиотека: треки, любимые, история, плейлисты, подписки.
///
/// Раскладка повторяет десктопную: лайки и подписки — ОТДЕЛЬНЫЕ наборы id, а не
/// флаги на самом треке (у смешанных источников флаг некуда положить), плейлист
/// хранит только id треков, сами треки лежат общим словарём.
///
/// Отличие от десктопа: там «все треки» приходят от folder_watcher'а, здесь
/// локальных файлов пока нет, поэтому в библиотеку трек попадает в момент
/// действия — лайк, добавление в плейлист, прослушивание. Иначе от лайкнутого
/// трека остался бы один id, и заиграть его было бы нечем.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entities/entities.dart';
import 'json_store.dart';

/// Сколько записей держим в истории.
const int kHistoryLimit = 200;

class UserPlaylist {
  final String id;
  final String name;
  final List<String> trackIds;
  final String? cover;
  final String? description;

  /// Ссылка, из которой плейлист импортирован — для «обновить треки».
  final String? sourceUrl;

  /// Импортированный альбом. Хранится так же, как плейлист, но вкладка
  /// «Альбомы» показывает только их.
  final bool isAlbum;
  final int createdAt;

  const UserPlaylist({
    required this.id,
    required this.name,
    this.trackIds = const [],
    this.cover,
    this.description,
    this.sourceUrl,
    this.isAlbum = false,
    this.createdAt = 0,
  });

  UserPlaylist copyWith({
    String? name,
    List<String>? trackIds,
    String? cover,
    String? description,
    String? sourceUrl,
  }) => UserPlaylist(
    id: id,
    name: name ?? this.name,
    trackIds: trackIds ?? this.trackIds,
    cover: cover ?? this.cover,
    description: description ?? this.description,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    isAlbum: isAlbum,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'trackIds': trackIds,
    if (cover != null) 'cover': cover,
    if (description != null) 'description': description,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (isAlbum) 'isAlbum': true,
    'createdAt': createdAt,
  };

  static UserPlaylist? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    return UserPlaylist(
      id: id,
      name: name,
      trackIds:
          (json['trackIds'] as List?)?.whereType<String>().toList() ?? const [],
      cover: json['cover'] as String?,
      description: json['description'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      isAlbum: json['isAlbum'] == true,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class FollowedArtist {
  final Artist artist;
  final int followedAt;
  const FollowedArtist({required this.artist, required this.followedAt});

  Map<String, dynamic> toJson() => {
    ...artist.toJson(),
    'followedAt': followedAt,
  };

  static FollowedArtist? fromJson(Object? json) {
    final artist = Artist.fromJson(json);
    if (artist == null) return null;
    return FollowedArtist(
      artist: artist,
      followedAt: ((json as Map)['followedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class HistoryEntry {
  final String trackId;
  final int at;
  const HistoryEntry(this.trackId, this.at);

  Map<String, dynamic> toJson() => {'id': trackId, 'at': at};

  static HistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return HistoryEntry(id, (json['at'] as num?)?.toInt() ?? 0);
  }
}

class LibraryState {
  /// Все известные библиотеке треки: id → трек.
  final Map<String, Track> tracks;

  /// id → время лайка. Порядок «Любимого» — по нему, свежие сверху.
  final Map<String, int> favs;

  /// Свежие сверху.
  final List<HistoryEntry> history;
  final List<UserPlaylist> playlists;
  final List<FollowedArtist> follows;

  const LibraryState({
    this.tracks = const {},
    this.favs = const {},
    this.history = const [],
    this.playlists = const [],
    this.follows = const [],
  });

  bool isFav(String trackId) => favs.containsKey(trackId);
  bool isFollowing(String artistId) =>
      follows.any((f) => f.artist.id == artistId);

  /// Все треки библиотеки. Порядок — как добавляли, свежие сверху.
  List<Track> get allTracks => tracks.values.toList().reversed.toList();

  List<Track> get favTracks {
    final entries = favs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => tracks[e.key]).whereType<Track>().toList();
  }

  List<Track> get historyTracks =>
      history.map((h) => tracks[h.trackId]).whereType<Track>().toList();

  List<Track> tracksOf(UserPlaylist pl) =>
      pl.trackIds.map((id) => tracks[id]).whereType<Track>().toList();

  LibraryState copyWith({
    Map<String, Track>? tracks,
    Map<String, int>? favs,
    List<HistoryEntry>? history,
    List<UserPlaylist>? playlists,
    List<FollowedArtist>? follows,
  }) => LibraryState(
    tracks: tracks ?? this.tracks,
    favs: favs ?? this.favs,
    history: history ?? this.history,
    playlists: playlists ?? this.playlists,
    follows: follows ?? this.follows,
  );
}

/// Файловое хранилище. Подменяется в `main()` реальным (и в тестах — памятью).
final jsonStoreProvider = Provider<JsonStore>(
  (ref) =>
      throw UnimplementedError('jsonStoreProvider должен быть переопределён'),
);

final libraryProvider = NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

class LibraryController extends Notifier<LibraryState> {
  JsonStore get _store => ref.read(jsonStoreProvider);

  @override
  LibraryState build() {
    final store = ref.read(jsonStoreProvider);
    final tracks = <String, Track>{};
    for (final raw in store.readList('tracks')) {
      final t = Track.fromJson(raw);
      if (t != null) tracks[t.id] = t;
    }
    final favs = <String, int>{};
    store.readMap('favs').forEach((id, at) {
      if (at is num) favs[id] = at.toInt();
    });
    return LibraryState(
      tracks: tracks,
      favs: favs,
      history: store
          .readList('history')
          .map(HistoryEntry.fromJson)
          .whereType<HistoryEntry>()
          .toList(),
      playlists: store
          .readList('playlists')
          .map(UserPlaylist.fromJson)
          .whereType<UserPlaylist>()
          .toList(),
      follows: store
          .readList('follows')
          .map(FollowedArtist.fromJson)
          .whereType<FollowedArtist>()
          .toList(),
    );
  }

  void _saveTracks() => _store.write(
    'tracks',
    state.tracks.values.map((t) => t.toJson()).toList(),
  );
  void _saveFavs() => _store.write('favs', state.favs);
  void _saveHistory() =>
      _store.write('history', state.history.map((h) => h.toJson()).toList());
  void _savePlaylists() => _store.write(
    'playlists',
    state.playlists.map((p) => p.toJson()).toList(),
  );
  void _saveFollows() =>
      _store.write('follows', state.follows.map((f) => f.toJson()).toList());

  /// Положить треки в общий словарь (merge по id).
  void _remember(Iterable<Track> batch) {
    if (batch.isEmpty) return;
    final next = Map<String, Track>.from(state.tracks);
    for (final t in batch) {
      next[t.id] = t;
    }
    state = state.copyWith(tracks: next);
    _saveTracks();
  }

  void addTracks(Iterable<Track> batch) => _remember(batch);

  // ── Любимые ─────────────────────────────────────────────────────────────

  /// Переключить лайк. Трек кладём в библиотеку целиком: от одного id в
  /// «Любимом» толку нет — его нечем ни показать, ни заиграть.
  bool toggleFav(Track track) {
    final favs = Map<String, int>.from(state.favs);
    final on = !favs.containsKey(track.id);
    if (on) {
      favs[track.id] = DateTime.now().millisecondsSinceEpoch;
      _remember([track]);
    } else {
      favs.remove(track.id);
    }
    state = state.copyWith(favs: favs);
    _saveFavs();
    return on;
  }

  // ── История ─────────────────────────────────────────────────────────────

  /// Отметить прослушивание: трек уезжает наверх истории без дублей.
  void pushHistory(Track track) {
    final history = [
      HistoryEntry(track.id, DateTime.now().millisecondsSinceEpoch),
      ...state.history.where((h) => h.trackId != track.id),
    ];
    if (history.length > kHistoryLimit) {
      history.removeRange(kHistoryLimit, history.length);
    }
    _remember([track]);
    state = state.copyWith(history: history);
    _saveHistory();
  }

  void clearHistory() {
    state = state.copyWith(history: const []);
    _saveHistory();
  }

  // ── Плейлисты ───────────────────────────────────────────────────────────

  UserPlaylist createPlaylist(
    String name, {
    List<Track> tracks = const [],
    String? cover,
    String? sourceUrl,
    bool isAlbum = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pl = UserPlaylist(
      id: 'pl_$now',
      name: name.trim().isEmpty ? 'Новый плейлист' : name.trim(),
      trackIds: tracks.map((t) => t.id).toList(),
      cover: cover ?? (tracks.isEmpty ? null : tracks.first.cover),
      sourceUrl: sourceUrl,
      isAlbum: isAlbum,
      createdAt: now,
    );
    _remember(tracks);
    state = state.copyWith(playlists: [...state.playlists, pl]);
    _savePlaylists();
    return pl;
  }

  void renamePlaylist(String id, String name) => _updatePlaylist(
    id,
    (p) => p.copyWith(name: name.trim().isEmpty ? p.name : name.trim()),
  );

  /// Поставить/снять обложку. Не через `copyWith`: там `cover ?? this.cover`,
  /// и снять обложку было бы нечем.
  void setPlaylistCover(String id, String? cover) => _updatePlaylist(
    id,
    (p) => UserPlaylist(
      id: p.id,
      name: p.name,
      trackIds: p.trackIds,
      cover: cover,
      description: p.description,
      sourceUrl: p.sourceUrl,
      isAlbum: p.isAlbum,
      createdAt: p.createdAt,
    ),
  );

  void deletePlaylist(String id) {
    state = state.copyWith(
      playlists: state.playlists.where((p) => p.id != id).toList(),
    );
    _savePlaylists();
  }

  /// Новый трек уходит НАВЕРХ плейлиста (как на десктопе), дубли игнорируются.
  void addTrackToPlaylist(String id, Track track) {
    _remember([track]);
    _updatePlaylist(id, (p) {
      if (p.trackIds.contains(track.id)) return p;
      return p.copyWith(trackIds: [track.id, ...p.trackIds]);
    });
  }

  void removeTrackFromPlaylist(String id, String trackId) => _updatePlaylist(
    id,
    (p) => p.copyWith(trackIds: p.trackIds.where((t) => t != trackId).toList()),
  );

  /// Заменить состав плейлиста целиком — «обновить треки» из источника.
  void replacePlaylistTracks(String id, List<Track> tracks) {
    _remember(tracks);
    _updatePlaylist(
      id,
      (p) => p.copyWith(trackIds: tracks.map((t) => t.id).toList()),
    );
  }

  void _updatePlaylist(String id, UserPlaylist Function(UserPlaylist) f) {
    state = state.copyWith(
      playlists: state.playlists.map((p) => p.id == id ? f(p) : p).toList(),
    );
    _savePlaylists();
  }

  // ── Подписки ────────────────────────────────────────────────────────────

  bool toggleFollow(Artist artist) {
    final on = !state.isFollowing(artist.id);
    state = state.copyWith(
      follows: on
          ? [
              ...state.follows,
              FollowedArtist(
                artist: artist,
                followedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            ]
          : state.follows.where((f) => f.artist.id != artist.id).toList(),
    );
    _saveFollows();
    return on;
  }
}
