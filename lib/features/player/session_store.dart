/// Сессия плеера — как `Session` ПК: очередь (`queue`) и её порядок до
/// перемешки (`orig`) — строками `session_tracks`, снимки треков — в `tracks`;
/// где стоим и режимы — kv `session` того же вида:
/// `{index, id, pos (с), source, shuffle, repeat (0/1/2), ended, playing, at,
/// cleared}`.
///
/// Из неё же «Продолжить» на главной и в меню. Мобильное сверх ПК: список
/// `full` — очередь до очистки («очистить» оставляет один играющий трек, а
/// «Продолжить» возвращает всё), и ключ `smartShuffle`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/db/track_store.dart';
import '../../core/entities/entities.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/library_store.dart' show libraryProvider;
import 'play_source.dart';
import 'player_controller.dart' show PlayerRepeat;

const String kSessionKey = 'session';

@immutable
class SessionData {
  const SessionData({
    required this.queue,
    required this.index,
    required this.position,
    required this.savedAt,
    this.orig = const [],
    this.full = const [],
    this.source,
    this.shuffle = false,
    this.smartShuffle = false,
    this.repeat = PlayerRepeat.off,
    this.ended = false,
    this.playing = false,
    this.cleared = false,
  });

  /// Не пустая — иначе сессии нет вовсе.
  final List<Track> queue;

  /// Порядок до перемешки; пуст, когда перемешки нет.
  final List<Track> orig;

  /// Очередь до очистки; пуста, если не очищали.
  final List<Track> full;

  final int index;
  final Duration position;
  final DateTime savedAt;
  final PlaySource? source;
  final bool shuffle;
  final bool smartShuffle;
  final PlayerRepeat repeat;

  /// Очередь доиграла без повтора — стоим в начале последнего трека.
  final bool ended;
  final bool playing;

  /// Очередь убрали целиком: при запуске в плеер не поднимаем, «Продолжить»
  /// остаётся.
  final bool cleared;

  Track get track => queue[index];

  /// Для «Продолжить»: очередь до очистки, если она была, на том же треке.
  /// Трека в ней нет — с начала и без позиции: позиция была у другого.
  SessionData forContinue() {
    if (full.isEmpty) return this;
    final at = full.indexWhere((t) => t.id == track.id);
    return SessionData(
      queue: full,
      index: at < 0 ? 0 : at,
      position: at < 0 ? Duration.zero : position,
      savedAt: savedAt,
      source: source,
      shuffle: shuffle,
      smartShuffle: smartShuffle,
      repeat: repeat,
    );
  }
}

final sessionProvider = NotifierProvider<SessionStore, SessionData?>(
  SessionStore.new,
);

/// Запись и чтение сессии. Состояние — последняя записанная сессия; карточка
/// «Продолжить» слушает его, только пока живого трека нет.
class SessionStore extends Notifier<SessionData?> {
  BloomDb get _db => ref.read(dbProvider);

  /// Id, чьи снимки уже лежат в `tracks` с этого запуска: очередь пишется
  /// заново на каждую правку, а снимок — только новым трекам.
  final Set<String> _stored = {};

  List<Track> _queue = const [], _orig = const [], _full = const [];

  @override
  SessionData? build() {
    _stored.clear();
    final ids = <String, List<String>>{'queue': [], 'orig': [], 'full': []};
    for (final r in _db.select(
      'SELECT list, track_id FROM session_tracks ORDER BY list, pos',
    )) {
      ids[r['list'] as String]?.add(r['track_id'] as String);
    }
    final store = TrackStore(_db);
    // Два id, слитые в один (смена площадки), оставляют повтор.
    List<Track> load(String list) => store.get(ids[list]!.toSet().toList());
    _queue = load('queue');
    _orig = load('orig');
    _full = load('full');
    for (final list in ids.values) {
      _stored.addAll(list);
    }
    return _read(_db.getMap(kSessionKey));
  }

  SessionData? _read(Map<String, dynamic> s) {
    if (s.isEmpty || _queue.isEmpty) return null;
    final id = s['id'];
    final saved = (s['index'] as num?)?.toInt() ?? 0;
    var index = saved >= 0 && saved < _queue.length && _queue[saved].id == id
        ? saved
        : _queue.indexWhere((t) => t.id == id);
    // Трека больше нет: место в очереди остаётся, позиция — нет.
    final found = index >= 0;
    if (!found) index = saved.clamp(0, _queue.length - 1);
    final shuffle = s['shuffle'] == true;
    return SessionData(
      queue: _queue,
      orig: _orig,
      full: _full,
      index: index,
      position: found
          ? Duration(
              milliseconds: (((s['pos'] as num?) ?? 0) * 1000).round(),
            )
          : Duration.zero,
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        (s['at'] as num?)?.toInt() ?? 0,
      ),
      source: PlaySource.fromJson(s['source']),
      shuffle: shuffle,
      // Умная перемешка — подвид обычной и без неё не живёт.
      smartShuffle: shuffle && s['smartShuffle'] == true,
      repeat:
          PlayerRepeat.values.elementAtOrNull(
            (s['repeat'] as num?)?.toInt() ?? 0,
          ) ??
          PlayerRepeat.off,
      ended: found && s['ended'] == true,
      playing: s['playing'] == true,
      cleared: s['cleared'] == true,
    );
  }

  /// Записать очередь. Пустая не пишется: строки остаются для «Продолжить».
  void saveQueue(List<Track> queue, List<Track>? orig, List<Track>? full) {
    if (queue.isEmpty) return;
    _queue = queue;
    _orig = orig ?? const [];
    _full = full ?? const [];
    final lists = {'queue': _queue, 'orig': _orig, 'full': _full};
    // Снимок мог пропасть с тех пор (трек удалили из библиотеки) — тогда
    // запись откатывается, и второй заход пишет снимки всех.
    if (_write(lists)) return;
    _stored.clear();
    _write(lists);
  }

  bool _write(Map<String, List<Track>> lists) {
    final fresh = [
      for (final list in lists.values)
        for (final t in list)
          if (_stored.add(t.id)) t,
    ];
    try {
      _db.tx(() {
        TrackStore(_db).put(fresh);
        _db.exec('DELETE FROM session_tracks');
        final ins = _db.prepare(
          'INSERT INTO session_tracks (list, pos, track_id) VALUES (?, ?, ?)',
        );
        try {
          lists.forEach((list, tracks) {
            for (var i = 0; i < tracks.length; i++) {
              ins.execute([list, i, tracks[i].id]);
            }
          });
        } finally {
          ins.close();
        }
      });
    } on Object catch (e) {
      logWarn('session', 'очередь не записана: $e');
    }
    return _db.value('SELECT count(*) FROM session_tracks WHERE list = ?', [
          'queue',
        ]) ==
        lists['queue']!.length;
  }

  /// Записать, где стоим. Очередь должна быть уже записана [saveQueue].
  void saveState({
    required int index,
    required Duration position,
    required PlaySource? source,
    required bool shuffle,
    required bool smartShuffle,
    required PlayerRepeat repeat,
    required bool ended,
    required bool playing,
  }) {
    if (index < 0 || index >= _queue.length) return;
    _db.set(kSessionKey, {
      'index': index,
      'id': _queue[index].id,
      'pos': (position.inMilliseconds / 100).round() / 10,
      'source': source == null ? <String, dynamic>{} : _sourceJson(source),
      'shuffle': shuffle,
      if (smartShuffle) 'smartShuffle': true,
      'repeat': repeat.index,
      'ended': ended,
      'playing': playing,
      'at': BloomDb.now(),
    });
    state = _read(_db.getMap(kSessionKey));
  }

  /// Очередь убрали целиком (смахнули последний трек): при запуске её не
  /// поднимаем, строки и «Продолжить» остаются.
  void markCleared() {
    final s = _db.getMap(kSessionKey);
    if (s.isEmpty || s['cleared'] == true) return;
    _db.set(kSessionKey, {...s, 'cleared': true});
    state = _read(_db.getMap(kSessionKey));
  }

  /// Свой список называется в карте именем и картинкой с карточки, как
  /// `ListCtx.sourceOf` ПК: другое устройство библиотеку не спросит.
  Map<String, dynamic> _sourceJson(PlaySource source) {
    final m = source.toJson();
    if (source is! LibSource) return m;
    final lib = ref.read(libraryProvider);
    for (final p in lib.playlists) {
      if (p.id != source.listId) continue;
      return {
        ...m,
        'name': p.name,
        'cover': p.cover ?? '',
        'covers': [
          for (final t in lib.tracksOf(p).take(4))
            if (t.cover != null) t.cover,
        ],
      };
    }
    return m;
  }
}
