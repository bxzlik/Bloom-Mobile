/// Библиотека: «Все треки», любимые, плейлисты, подписки — поверх таблиц
/// `lists`/`list_tracks`/`follows` базы (порт `Library` + `Lists` ПК).
///
/// Раскладка та же, что на ПК: «Все треки» (`lib`), любимые (`fav`) и плейлисты
/// — одна таблица упорядоченных списков. У каждой строки списка своё место
/// (`pos`) и своё время добавления (`added_at`): перетаскивание меняет только
/// место, «свежие лайки» по-прежнему знают, когда их поставили.
///
/// Инвариант ПК: трек в плейлисте или в любимых — трек в библиотеке
/// ([_addTo] кладёт его и туда), а убранный из библиотеки убирается отовсюду.
///
/// [LibraryState] — снимок для экранов: читается синхронно, обновляется после
/// каждой правки. Сами треки в нём — только те, что стоят в каком-то списке;
/// снимок любого слышанного трека лежит в `tracks` базы (см. [TrackStore]).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../db/track_store.dart';
import '../entities/entities.dart';
import '../l10n/l10n.dart';

/// id служебных списков — те же, что на ПК (`Lists::kLibrary/kFavorites`).
const String kLibList = 'lib';
const String kFavList = 'fav';

/// Источник «Обновить треки»: привязанная к плейлисту внешняя коллекция —
/// плейлист, альбом или профиль (лайки) любой площадки. Их может быть сколько
/// угодно и с разных площадок, как на ПК.
class PlSourceRef {
  const PlSourceRef({required this.url, this.title});

  final String url;

  /// Название коллекции на момент привязки — только для строки в списке.
  final String? title;

  Map<String, dynamic> toJson() => {
    'url': url,
    if (title != null) 'title': title,
  };

  static PlSourceRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    return PlSourceRef(url: url, title: json['title'] as String?);
  }
}

class UserPlaylist {
  final String id;
  final String name;

  /// Состав по местам, первый сверху.
  final List<String> trackIds;
  final String? cover;
  final String? description;

  /// Откуда «Обновить треки» тянет новые треки. Пусто — плейлист свой, и
  /// обновлять его неоткуда.
  final List<PlSourceRef> sources;
  final int createdAt;

  /// Место карточки на экране библиотеки (`side_pos`); 0 — ещё не стояла.
  final int sidePos;

  const UserPlaylist({
    required this.id,
    required this.name,
    this.trackIds = const [],
    this.cover,
    this.description,
    this.sources = const [],
    this.createdAt = 0,
    this.sidePos = 0,
  });

  UserPlaylist copyWith({List<String>? trackIds}) => UserPlaylist(
    id: id,
    name: name,
    trackIds: trackIds ?? this.trackIds,
    cover: cover,
    description: description,
    sources: sources,
    createdAt: createdAt,
    sidePos: sidePos,
  );
}

class FollowedArtist {
  final Artist artist;
  final int followedAt;
  const FollowedArtist({required this.artist, required this.followedAt});
}

class LibraryState {
  /// Треки, стоящие хоть в одном списке. id → трек.
  final Map<String, Track> tracks;

  /// «Все треки» по местам, первый сверху.
  final List<String> libIds;

  /// id → когда трек попал в библиотеку.
  final Map<String, int> inLib;

  /// Любимые по местам, первый сверху.
  final List<String> favIds;

  /// id → когда поставлен лайк.
  final Map<String, int> favs;

  final List<UserPlaylist> playlists;
  final List<FollowedArtist> follows;

  const LibraryState({
    this.tracks = const {},
    this.libIds = const [],
    this.inLib = const {},
    this.favIds = const [],
    this.favs = const {},
    this.playlists = const [],
    this.follows = const [],
  });

  bool isFav(String trackId) => favs.containsKey(trackId);
  bool isInLib(String trackId) => inLib.containsKey(trackId);
  bool isFollowing(String artistId) =>
      follows.any((f) => f.artist.id == artistId);

  List<Track> get allTracks => [for (final id in libIds) ?tracks[id]];

  List<Track> get favTracks => [for (final id in favIds) ?tracks[id]];

  List<Track> tracksOf(UserPlaylist pl) => [
    for (final id in pl.trackIds) ?tracks[id],
  ];
}

final libraryProvider = NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

class LibraryController extends Notifier<LibraryState> {
  BloomDb get _db => ref.read(dbProvider);
  TrackStore get _store => TrackStore(_db);

  @override
  LibraryState build() => _read(const {});

  /// Перечитать списки из базы. Треки, уже лежащие в [known], не читаются
  /// заново — правка трогает пару строк, а не всю библиотеку.
  LibraryState _read(Map<String, Track> known) {
    final members = <String, List<String>>{};
    final added = <String, Map<String, int>>{};
    for (final r in _db.select(
      'SELECT list_id, track_id, added_at FROM list_tracks ORDER BY list_id, pos',
    )) {
      final list = r['list_id'] as String;
      final id = r['track_id'] as String;
      (members[list] ??= []).add(id);
      (added[list] ??= {})[id] = r['added_at'] as int;
    }

    final ids = {for (final m in members.values) ...m};
    final tracks = <String, Track>{for (final id in ids) id: ?known[id]};
    final missing = [
      for (final id in ids)
        if (!tracks.containsKey(id)) id,
    ];
    for (final t in _store.get(missing)) {
      tracks[t.id] = t;
    }

    final playlists = [
      for (final r in _db.select(
        "SELECT id, name, description, cover, sources, created_at, side_pos FROM lists WHERE kind = 'playlist' ORDER BY pinned DESC, side_pos, created_at",
      ))
        UserPlaylist(
          id: r['id'] as String,
          name: r['name'] as String,
          description: _text(r['description']),
          cover: _text(r['cover']),
          sources: _sources(r['sources'] as String?),
          createdAt: r['created_at'] as int,
          sidePos: r['side_pos'] as int,
          trackIds: members[r['id']] ?? const [],
        ),
    ];

    final follows = [
      for (final r in _db.select(
        'SELECT id, name, avatar, extra, at FROM follows ORDER BY pinned DESC, side_pos, at',
      ))
        FollowedArtist(artist: _artistOfRow(r), followedAt: r['at'] as int),
    ];

    return LibraryState(
      tracks: tracks,
      libIds: members[kLibList] ?? const [],
      inLib: added[kLibList] ?? const {},
      favIds: members[kFavList] ?? const [],
      favs: added[kFavList] ?? const {},
      playlists: playlists,
      follows: follows,
    );
  }

  void _refresh() => state = _read(state.tracks);

  static String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;

  static List<PlSourceRef> _sources(String? raw) {
    try {
      final list = jsonDecode(raw ?? '[]');
      return [
        if (list is List)
          for (final s in list) ?PlSourceRef.fromJson(s),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Artist _artistOfRow(Map<String, Object?> r) {
    final id = r['id'] as String;
    Map<String, dynamic> x;
    try {
      x = (jsonDecode(r['extra'] as String? ?? '{}') as Map)
          .cast<String, dynamic>();
    } catch (_) {
      x = const {};
    }
    return Artist(
      id: id,
      name: r['name'] as String? ?? '',
      avatar: _text(r['avatar']),
      source: MusicSource.fromId(id),
      permalink: _text(x['permalink']),
      fullName: _text(x['fullName']),
      verified: x['verified'] == true,
    );
  }

  // ── Списки (порт `Lists`) ──────────────────────────────────────────────

  /// Следующее место карточки на экране библиотеки — общее у плейлистов,
  /// папок и подписок, как на ПК.
  int _nextSidePos() =>
      (_db.value('''SELECT max(coalesce((SELECT max(side_pos) FROM lists), 0),
          coalesce((SELECT max(side_pos) FROM folders), 0),
          coalesce((SELECT max(side_pos) FROM follows), 0)) + 1''')
          as int?) ??
      1;

  bool _listExists(String list) =>
      _db.value('SELECT 1 FROM lists WHERE id = ?', [list]) != null;

  /// Положить треки в список — те, которых там ещё нет; всегда наверх, в
  /// порядке пачки (пустой список так и получает их как есть). Возвращает,
  /// сколько прибавилось. Трек в списке — трек в библиотеке: новые встают в
  /// начало «Всех треков».
  int _addTo(String list, List<Track> tracks) {
    if (!_listExists(list)) return 0;
    return _db.tx(() {
      _store.put(tracks);
      final have = {
        for (final r in _db.select(
          'SELECT track_id FROM list_tracks WHERE list_id = ?',
          [list],
        ))
          r['track_id'] as String,
      };
      final fresh = [
        for (final t in tracks)
          if (t.id.isNotEmpty && have.add(t.id)) t,
      ];
      if (fresh.isEmpty) return 0;
      final now = BloomDb.now();
      var pos =
          (_db.value(
                'SELECT coalesce(min(pos), 0) FROM list_tracks WHERE list_id = ?',
                [list],
              )
              as int) -
          fresh.length;
      final insert = _db.prepare(
        'INSERT INTO list_tracks (list_id, track_id, pos, added_at) VALUES (?, ?, ?, ?)',
      );
      try {
        for (final t in fresh) {
          insert.execute([list, t.id, pos++, now]);
        }
      } finally {
        insert.close();
      }
      _touch(list);
      if (list != kLibList) _addTo(kLibList, fresh);
      return fresh.length;
    });
  }

  /// Убрать треки из списка; из библиотеки — значит отовсюду.
  void _removeFrom(String list, Iterable<String> trackIds) {
    _db.tx(() {
      for (final id in trackIds) {
        _db.exec('DELETE FROM list_tracks WHERE list_id = ? AND track_id = ?', [
          list,
          id,
        ]);
        if (list == kLibList) {
          _db.exec('DELETE FROM list_tracks WHERE track_id = ?', [id]);
        }
      }
      _touch(list);
    });
  }

  /// Новый порядок списка: [ids] по местам 0…n-1; чего в [ids] нет — уходит
  /// из списка ([_removeFrom]). Время добавления не трогается.
  void _setOrder(String list, List<String> ids) {
    _db.tx(() {
      final was = {
        for (final r in _db.select(
          'SELECT track_id FROM list_tracks WHERE list_id = ?',
          [list],
        ))
          r['track_id'] as String,
      };
      _removeFrom(list, was.difference(ids.toSet()));
      final set = _db.prepare(
        'UPDATE list_tracks SET pos = ? WHERE list_id = ? AND track_id = ?',
      );
      try {
        for (var i = 0; i < ids.length; i++) {
          set.execute([i, list, ids[i]]);
        }
      } finally {
        set.close();
      }
      _touch(list);
    });
  }

  void _touch(String list) => _db.exec(
    'UPDATE lists SET updated_at = ? WHERE id = ?',
    [BloomDb.now(), list],
  );

  void _updateList(String id, Map<String, Object?> columns) {
    if (columns.isEmpty) return;
    final sets = [for (final c in columns.keys) '$c = ?', 'updated_at = ?'];
    _db.exec('UPDATE lists SET ${sets.join(', ')} WHERE id = ?', [
      ...columns.values,
      BloomDb.now(),
      id,
    ]);
    _refresh();
  }

  // ── Библиотека («Все треки») ────────────────────────────────────────────

  /// Положить треки в библиотеку, новые наверх; уже лежащие остаются на своём
  /// месте. Возвращает число реально добавленных.
  int addToLibrary(Iterable<Track> batch) {
    final n = _addTo(kLibList, batch.toList());
    _refresh();
    return n;
  }

  /// Удалить трек отовсюду: из библиотеки, лайков и всех плейлистов. Журнал
  /// прослушиваний не трогается — «этот трек тогда-то играл» остаётся правдой,
  /// снимок трека для истории держит сама база.
  void deleteTrack(String trackId) {
    _db.tx(() {
      _removeFrom(kLibList, [trackId]);
      _store.prune();
    });
    _refresh();
  }

  /// Заменить трек версией с другой площадки: у новой версии другой id, и все
  /// ссылки — места в списках, лайк, прослушивания, дизлайк — едут за ним
  /// ([TrackStore.rekey]), со своими местами и временем добавления.
  void replaceTrack(String oldId, Track next) {
    if (oldId == next.id) return;
    _db.tx(() {
      _store.rekey(oldId, next.id);
      _store.put([next]);
    });
    state = _read({
      for (final e in state.tracks.entries)
        if (e.key != oldId) e.key: e.value,
      next.id: next,
    });
  }

  /// Снимок библиотеки целиком — для «Отменить» после удаления смахиванием.
  LibraryState snapshot() => state;

  /// Вернуть списки, как они были в [snap]: состав, места и время добавления.
  /// Плейлисты, которых с тех пор не стало, возвращаются тоже.
  void restoreSnapshot(LibraryState snap) {
    _db.tx(() {
      _store.put(snap.tracks.values);
      void put(String list, List<String> ids, Map<String, int> added) {
        _db.exec('DELETE FROM list_tracks WHERE list_id = ?', [list]);
        final now = BloomDb.now();
        for (var i = 0; i < ids.length; i++) {
          if (!snap.tracks.containsKey(ids[i])) continue;
          _db.exec(
            'INSERT INTO list_tracks (list_id, track_id, pos, added_at) VALUES (?, ?, ?, ?)',
            [list, ids[i], i, added[ids[i]] ?? now],
          );
        }
      }

      put(kLibList, snap.libIds, snap.inLib);
      put(kFavList, snap.favIds, snap.favs);
      for (final pl in snap.playlists) {
        if (!_listExists(pl.id)) _insertPlaylist(pl);
        put(pl.id, pl.trackIds, const {});
      }
    });
    _refresh();
  }

  /// Правка «Всех треков» целиком: [ids] — новый состав И порядок, первый
  /// сверху. Выпавшее удаляется насквозь, как [deleteTrack].
  void setLibraryTracks(List<String> ids) {
    _db.tx(() {
      _setOrder(kLibList, ids);
      _store.prune();
    });
    _refresh();
  }

  // ── Любимые ─────────────────────────────────────────────────────────────

  /// Переключить лайк. Новый лайк — наверх любимых и в библиотеку.
  bool toggleFav(Track track) {
    final on = !state.isFav(track.id);
    if (on) {
      _addTo(kFavList, [track]);
    } else {
      _removeFrom(kFavList, [track.id]);
    }
    _refresh();
    return on;
  }

  /// Лайкнуть пачку разом (импорт ссылки в любимые): наверх, в порядке пачки.
  /// Возвращает, сколько лайков прибавилось.
  int addToFavorites(List<Track> batch) {
    final n = _addTo(kFavList, batch);
    _refresh();
    return n;
  }

  /// Правка «Любимых» целиком: [ids] — новый состав И порядок. Снятый лайк из
  /// библиотеки трек не выкидывает.
  void setFavTracks(List<String> ids) {
    _setOrder(kFavList, ids);
    _refresh();
  }

  // ── Плейлисты ───────────────────────────────────────────────────────────

  UserPlaylist createPlaylist(
    String name, {
    List<Track> tracks = const [],
    String? cover,
    String? description,
    String? sourceUrl,
    String? sourceTitle,
  }) {
    final pl = UserPlaylist(
      description: description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      id: _freeId(BloomDb.now()),
      // Имя плейлиста — данные, а не интерфейс: как назвали при создании,
      // так и останется. Поэтому дефолт берётся на языке, который стоял в
      // этот момент, и потом уже не переводится.
      name: name.trim().isEmpty
          ? (globalL10n?.commonNewPlaylist ?? 'New playlist')
          : name.trim(),
      cover: cover ?? (tracks.isEmpty ? null : tracks.first.cover),
      // Ссылка, из которой плейлист завели, сразу становится его первым
      // источником обновления — остальные привязывают уже руками, в редакторе.
      sources: [
        if (sourceUrl != null && sourceUrl.trim().isNotEmpty)
          PlSourceRef(url: sourceUrl.trim(), title: sourceTitle),
      ],
      createdAt: BloomDb.now(),
    );
    _db.tx(() {
      _insertPlaylist(pl);
      _addTo(pl.id, tracks);
    });
    _refresh();
    return state.playlists.firstWhere((p) => p.id == pl.id);
  }

  void _insertPlaylist(UserPlaylist pl) {
    final now = BloomDb.now();
    _db.exec(
      "INSERT INTO lists (id, kind, name, description, cover, sources, created_at, updated_at, side_pos) VALUES (?, 'playlist', ?, ?, ?, ?, ?, ?, ?)",
      [
        pl.id,
        pl.name,
        pl.description ?? '',
        pl.cover ?? '',
        jsonEncode([for (final s in pl.sources) s.toJson()]),
        pl.createdAt == 0 ? now : pl.createdAt,
        now,
        // Возвращённый («Отменить») встаёт на своё прежнее место.
        pl.sidePos > 0 ? pl.sidePos : _nextSidePos(),
      ],
    );
  }

  /// Свободный id плейлиста — как на ПК: `pl` + время в base36, а если такой
  /// уже занят (несколько плейлистов в одну миллисекунду — импорт файла) —
  /// следующее число.
  String _freeId(int at) {
    var n = at;
    while (_listExists('pl${n.toRadixString(36)}')) {
      n++;
    }
    return 'pl${n.toRadixString(36)}';
  }

  void renamePlaylist(String id, String name) {
    if (name.trim().isEmpty) return;
    _updateList(id, {'name': name.trim()});
  }

  /// Поставить/снять обложку (`null` — снять).
  void setPlaylistCover(String id, String? cover) =>
      _updateList(id, {'cover': cover ?? ''});

  /// Привязки «Обновить треки» целиком — их правит редактор плейлиста.
  void setPlaylistSources(String id, List<PlSourceRef> sources) =>
      _updateList(id, {
        'sources': jsonEncode([for (final s in sources) s.toJson()]),
      });

  /// Удалить плейлист; его треки остаются в библиотеке.
  void deletePlaylist(String id) {
    if (id == kLibList || id == kFavList) return;
    _db.exec("DELETE FROM lists WHERE id = ? AND kind = 'playlist'", [id]);
    _refresh();
  }

  /// Вернуть удалённый плейлист — «Отменить» в тосте. Если его уже создали
  /// заново с тем же id, возвращать нечего.
  void restorePlaylist(UserPlaylist playlist) {
    if (_listExists(playlist.id)) return;
    _db.tx(() {
      _insertPlaylist(playlist);
      _addTo(playlist.id, [
        for (final id in playlist.trackIds) ?state.tracks[id],
      ]);
    });
    _refresh();
  }

  /// Положить треки в плейлист — наверх, в порядке пачки; уже лежащие
  /// пропускаются. Возвращает, сколько прибавилось: «Обновить треки» считает
  /// новинки именно так.
  int addTracksToPlaylist(String id, List<Track> batch) {
    final n = _addTo(id, batch);
    _refresh();
    return n;
  }

  void addTrackToPlaylist(String id, Track track) =>
      addTracksToPlaylist(id, [track]);

  void removeTrackFromPlaylist(String id, String trackId) {
    _removeFrom(id, [trackId]);
    _refresh();
  }

  /// Правка плейлиста целиком: [trackIds] — новый состав И порядок.
  void setPlaylistTracks(String id, List<String> trackIds) {
    _setOrder(id, trackIds);
    _refresh();
  }

  // ── Подписки ────────────────────────────────────────────────────────────

  bool toggleFollow(Artist artist) {
    final on = !state.isFollowing(artist.id);
    if (on) {
      _db.exec(
        'INSERT OR IGNORE INTO follows (id, provider, name, avatar, extra, at, side_pos) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          artist.id,
          artist.source.code,
          artist.name,
          artist.avatar ?? '',
          jsonEncode({
            if (artist.permalink != null) 'permalink': artist.permalink,
            if (artist.fullName != null) 'fullName': artist.fullName,
            if (artist.verified) 'verified': true,
          }),
          BloomDb.now(),
          _nextSidePos(),
        ],
      );
    } else {
      _db.exec('DELETE FROM follows WHERE id = ?', [artist.id]);
    }
    _refresh();
    return on;
  }
}
