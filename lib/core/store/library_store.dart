/// Библиотека: треки, любимые, история, плейлисты, подписки.
///
/// Раскладка повторяет десктопную: лайки и подписки — ОТДЕЛЬНЫЕ наборы id, а не
/// флаги на самом треке (у смешанных источников флаг некуда положить), плейлист
/// хранит только id треков, сами треки лежат общим словарём.
///
/// Словарь `tracks` — это ХРАНИЛИЩЕ, а не раздел «Все треки»: там лежит всё, на
/// что кто-то ссылается (лайк, плейлист, история), иначе от лайкнутого трека
/// остался бы один id и заиграть его было бы нечем. Членство в библиотеке —
/// отдельный набор [LibraryState.inLib], как на десктопе: туда трек попадает
/// только явным действием (пункт «В библиотеку», лайк, плейлист, импорт).
/// Прослушивание в библиотеку НЕ кладёт — только в историю.
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

  /// Сколько раз трек слушали — счётчик статистики профиля (десктопный
  /// `HistoryEntry.count`). У записей, сделанных до появления счётчика, он
  /// равен единице.
  final int count;

  const HistoryEntry(this.trackId, this.at, {this.count = 1});

  Map<String, dynamic> toJson() => {'id': trackId, 'at': at, 'n': count};

  static HistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return HistoryEntry(
      id,
      (json['at'] as num?)?.toInt() ?? 0,
      count: (json['n'] as num?)?.toInt() ?? 1,
    );
  }
}

class LibraryState {
  /// Хранилище: все треки, на которые кто-то ссылается. id → трек.
  final Map<String, Track> tracks;

  /// Раздел «Все треки»: id → время добавления. Свежие сверху.
  final Map<String, int> inLib;

  /// id → время лайка. Порядок «Любимого» — по нему, свежие сверху.
  final Map<String, int> favs;

  /// Свежие сверху.
  final List<HistoryEntry> history;
  final List<UserPlaylist> playlists;
  final List<FollowedArtist> follows;

  const LibraryState({
    this.tracks = const {},
    this.inLib = const {},
    this.favs = const {},
    this.history = const [],
    this.playlists = const [],
    this.follows = const [],
  });

  bool isFav(String trackId) => favs.containsKey(trackId);
  bool isInLib(String trackId) => inLib.containsKey(trackId);
  bool isFollowing(String artistId) =>
      follows.any((f) => f.artist.id == artistId);

  /// Все треки библиотеки. Порядок — как добавляли, свежие сверху.
  List<Track> get allTracks {
    final entries = inLib.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => tracks[e.key]).whereType<Track>().toList();
  }

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
    Map<String, int>? inLib,
    Map<String, int>? favs,
    List<HistoryEntry>? history,
    List<UserPlaylist>? playlists,
    List<FollowedArtist>? follows,
  }) => LibraryState(
    tracks: tracks ?? this.tracks,
    inLib: inLib ?? this.inLib,
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

    final inLib = <String, int>{};
    if (store.read('lib') == null) {
      // Данные, записанные до разделения хранилища и «Всех треков»: тогда в
      // библиотеке лежало ровно содержимое `tracks`, в порядке добавления.
      var i = 0;
      for (final id in tracks.keys) {
        inLib[id] = i++;
      }
      store.write('lib', inLib);
    } else {
      store.readMap('lib').forEach((id, at) {
        if (at is num) inLib[id] = at.toInt();
      });
    }

    return LibraryState(
      tracks: tracks,
      inLib: inLib,
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
  void _saveLib() => _store.write('lib', state.inLib);
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

  /// Выбросить из хранилища треки, на которые больше никто не ссылается —
  /// иначе прослушанное копилось бы вечно, оставаясь невидимым.
  void _prune() {
    final keep = <String>{
      ...state.inLib.keys,
      ...state.favs.keys,
      ...state.history.map((h) => h.trackId),
      for (final p in state.playlists) ...p.trackIds,
    };
    if (keep.length == state.tracks.length) return;
    final next = <String, Track>{
      for (final e in state.tracks.entries)
        if (keep.contains(e.key)) e.key: e.value,
    };
    state = state.copyWith(tracks: next);
    _saveTracks();
  }

  // ── Библиотека («Все треки») ────────────────────────────────────────────

  /// Положить треки в библиотеку. Идемпотентно: у тех, что уже там, время
  /// добавления не переписывается, иначе повторный импорт перетасовал бы
  /// раздел. Возвращает число реально добавленных.
  int addToLibrary(Iterable<Track> batch) {
    _remember(batch);
    final next = Map<String, int>.from(state.inLib);
    // Время добавления обязано строго расти: два добавления подряд попадают в
    // одну миллисекунду, а сортировка по равным ключам порядок не сохраняет.
    var at = DateTime.now().millisecondsSinceEpoch;
    for (final prev in next.values) {
      if (prev >= at) at = prev + 1;
    }
    var added = 0;
    for (final t in batch) {
      if (next.containsKey(t.id)) continue;
      next[t.id] = at + added; // порядок внутри пачки сохраняем
      added++;
    }
    if (added == 0) return 0;
    state = state.copyWith(inLib: next);
    _saveLib();
    return added;
  }

  /// Удалить трек отовсюду — порт `deleteUploadedTrack` + `cascadePurgeTrackRefs`.
  ///
  /// Именно насквозь, а не только из «Всех треков»: лайк и плейлист сами кладут
  /// трек в библиотеку, так что «в любимых, но не в библиотеке» — состояние,
  /// которого нигде больше не бывает, а оставшийся id висел бы в плейлисте
  /// счётчиком без строки.
  void deleteTrack(String trackId) {
    state = state.copyWith(
      tracks: Map<String, Track>.from(state.tracks)..remove(trackId),
      inLib: Map<String, int>.from(state.inLib)..remove(trackId),
      favs: Map<String, int>.from(state.favs)..remove(trackId),
      history: state.history.where((h) => h.trackId != trackId).toList(),
      playlists: state.playlists
          .map(
            (p) => p.trackIds.contains(trackId)
                ? p.copyWith(
                    trackIds: p.trackIds.where((id) => id != trackId).toList(),
                  )
                : p,
          )
          .toList(),
    );
    _saveTracks();
    _saveLib();
    _saveFavs();
    _saveHistory();
    _savePlaylists();
  }

  /// Правка «Всех треков» целиком: [ids] — новый состав И порядок, первый
  /// сверху. Выпавшее из списка удаляется НАСКВОЗЬ, как [deleteTrack]: трек вне
  /// библиотеки, но в плейлисте — состояние, которого больше нигде не бывает.
  void setLibraryTracks(List<String> ids) {
    final gone = state.inLib.keys.toSet()..removeAll(ids);
    // Порядок раздела держится временем добавления, свежие сверху, — значит
    // первому в списке достаётся наибольшее время.
    final now = DateTime.now().millisecondsSinceEpoch;
    final inLib = <String, int>{
      for (var i = 0; i < ids.length; i++) ids[i]: now - i,
    };
    if (gone.isEmpty) {
      state = state.copyWith(inLib: inLib);
      _saveLib();
      return;
    }
    state = state.copyWith(
      inLib: inLib,
      tracks: Map<String, Track>.from(state.tracks)
        ..removeWhere((id, _) => gone.contains(id)),
      favs: Map<String, int>.from(state.favs)
        ..removeWhere((id, _) => gone.contains(id)),
      history: state.history.where((h) => !gone.contains(h.trackId)).toList(),
      playlists: [
        for (final p in state.playlists)
          p.trackIds.any(gone.contains)
              ? p.copyWith(
                  trackIds: p.trackIds
                      .where((id) => !gone.contains(id))
                      .toList(),
                )
              : p,
      ],
    );
    _saveTracks();
    _saveLib();
    _saveFavs();
    _saveHistory();
    _savePlaylists();
  }

  // ── Любимые ─────────────────────────────────────────────────────────────

  /// Переключить лайк. Лайкнутый трек заодно попадает в библиотеку — как на
  /// десктопе, где fav сперва персистит трек площадки (`saveTrackToLibrary`).
  bool toggleFav(Track track) {
    final favs = Map<String, int>.from(state.favs);
    final on = !favs.containsKey(track.id);
    if (on) {
      favs[track.id] = DateTime.now().millisecondsSinceEpoch;
      addToLibrary([track]);
    } else {
      favs.remove(track.id);
    }
    state = state.copyWith(favs: favs);
    _saveFavs();
    return on;
  }

  /// Правка «Любимых» целиком: [ids] — новый состав И порядок. Снятый лайк из
  /// библиотеки трек не выкидывает — как и [toggleFav], только наоборот.
  void setFavTracks(List<String> ids) {
    final now = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(
      favs: {for (var i = 0; i < ids.length; i++) ids[i]: now - i},
    );
    _saveFavs();
    _prune();
  }

  // ── История ─────────────────────────────────────────────────────────────

  /// Отметить прослушивание: трек уезжает наверх истории без дублей. В
  /// библиотеку он при этом НЕ попадает (как и на десктопе) — только в
  /// хранилище, чтобы историю было чем показать и заиграть.
  void pushHistory(Track track) {
    // Счётчик прослушиваний переезжает вместе с записью наверх: он и есть
    // основа статистики профиля, потерять его при подъёме нельзя.
    final was = state.history.where((h) => h.trackId == track.id).firstOrNull;
    final history = [
      HistoryEntry(
        track.id,
        DateTime.now().millisecondsSinceEpoch,
        count: (was?.count ?? 0) + 1,
      ),
      ...state.history.where((h) => h.trackId != track.id),
    ];
    if (history.length > kHistoryLimit) {
      history.removeRange(kHistoryLimit, history.length);
    }
    _remember([track]);
    state = state.copyWith(history: history);
    _saveHistory();
    _prune();
  }

  /// Правка «Истории» целиком: [ids] — что осталось и в каком порядке. Время
  /// прослушивания у уцелевших записей сохраняется: это их единственный смысл.
  void setHistoryTracks(List<String> ids) {
    final byId = {for (final h in state.history) h.trackId: h};
    state = state.copyWith(history: [for (final id in ids) ?byId[id]]);
    _saveHistory();
    _prune();
  }

  void clearHistory() {
    state = state.copyWith(history: const []);
    _saveHistory();
    _prune();
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
    addToLibrary(tracks);
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

  /// Вернуть удалённый плейлист на его место — «Отменить» в тосте (порт
  /// `PlMenu` с ПК). Восстанавливать нечего, если его уже создали заново с тем
  /// же id, поэтому дубль молча пропускаем.
  void restorePlaylist(int index, UserPlaylist playlist) {
    if (state.playlists.any((p) => p.id == playlist.id)) return;
    final next = [...state.playlists];
    next.insert(
      index < 0 ? next.length : index.clamp(0, next.length),
      playlist,
    );
    state = state.copyWith(playlists: next);
    _savePlaylists();
  }

  /// Новый трек уходит НАВЕРХ плейлиста (как на десктопе), дубли игнорируются.
  void addTrackToPlaylist(String id, Track track) =>
      addTracksToPlaylist(id, [track]);

  /// То же для пачки — выделение из режима правки списка. Порядок внутри пачки
  /// сохраняется, уже лежащие в плейлисте треки пропускаются.
  void addTracksToPlaylist(String id, List<Track> batch) {
    addToLibrary(batch);
    _updatePlaylist(id, (p) {
      final have = p.trackIds.toSet();
      final add = [
        for (final t in batch)
          if (!have.contains(t.id)) t.id,
      ];
      if (add.isEmpty) return p;
      return p.copyWith(trackIds: [...add, ...p.trackIds]);
    });
  }

  void removeTrackFromPlaylist(String id, String trackId) => _updatePlaylist(
    id,
    (p) => p.copyWith(trackIds: p.trackIds.where((t) => t != trackId).toList()),
  );

  /// Правка плейлиста целиком: [trackIds] — новый состав И порядок. В отличие
  /// от [replacePlaylistTracks] сюда приходят только id: треки уже в
  /// хранилище, добавлять нечего, а вот выпавшие из состава могут стать
  /// никому не нужными.
  void setPlaylistTracks(String id, List<String> trackIds) {
    _updatePlaylist(id, (p) => p.copyWith(trackIds: trackIds));
    _prune();
  }

  /// Заменить состав плейлиста целиком — «обновить треки» из источника.
  void replacePlaylistTracks(String id, List<Track> tracks) {
    addToLibrary(tracks);
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
