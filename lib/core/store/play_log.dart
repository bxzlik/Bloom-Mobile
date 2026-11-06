/// Play log, the only store of what was played when: the `plays` table. One row
/// per counted play; history, profile stats, wave seeds and Wrapped all derive
/// from it, with no counters elsewhere.
///
/// A track's snapshot (title, cover, duration) lies in the database's `tracks`:
/// it's needed a year on, when the track has long left the library.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../db/track_store.dart';
import '../entities/entities.dart';

/// The log's clock, for tests.
final playLogClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

const Set<String> _kWords = {
  'wave', 'library', 'favorites', 'playlist', 'folder', 'collection', //
  'artist', 'search', 'forYou', 'home', 'chart', 'releases', 'history',
  'wrapped', 'stats', 'files', 'queue', 'other',
};

/// Where a track was started from, one word of a fixed set, so the numbers
/// add up on every device: wave, library, favorites, playlist, folder,
/// collection, artist, search, forYou, home, chart, releases, history,
/// wrapped, stats, files, queue, other. Takes a queue source as its map
/// (`kind`, `id`); `from` in the map overrides the kind.
String sourceWord(Map<String, Object?>? source) {
  if (source == null) return 'other';
  final from = source['from'];
  if (from is String && _kWords.contains(from)) return from;
  final kind = source['kind'] is String ? source['kind'] as String : '';
  final id = source['id'] is String ? source['id'] as String : '';
  switch (kind) {
    case 'playlist':
      return switch (id) {
        'lib' => 'library',
        'fav' => 'favorites',
        _ when id.startsWith('folder:') => 'folder',
        _ => 'playlist',
      };
    case 'discover':
      return id == 'discover:charts' ? 'chart' : 'home';
    case 'similarTo':
      return 'home';
    case 'recent':
      return 'history';
  }
  // A lone track without a word on where it came from tells nothing.
  return kind != 'track' && _kWords.contains(kind) ? kind : 'other';
}

/// One counted play.
@immutable
class PlayEvent {
  const PlayEvent(this.ts, this.id);

  /// When the play was counted (90% of the track or its end).
  final int ts;
  final String id;
}

@immutable
class PlayLog {
  const PlayLog({this.events = const [], this.tracks = const {}});

  /// All events, by ascending `ts`.
  final List<PlayEvent> events;

  /// Snapshots of all tracks ever played.
  final Map<String, Track> tracks;

  bool get isEmpty => events.isEmpty;
}

final playLogProvider = NotifierProvider<PlayLogController, PlayLog>(
  PlayLogController.new,
);

class PlayLogController extends Notifier<PlayLog> {
  BloomDb get _db => ref.read(dbProvider);

  @override
  PlayLog build() => _read();

  PlayLog _read() {
    final events = [
      for (final r in _db.select('SELECT ts, track_id FROM plays ORDER BY ts'))
        PlayEvent(r['ts'] as int, r['track_id'] as String),
    ];
    final ids = {for (final e in events) e.id}.toList();
    return PlayLog(
      events: events,
      tracks: {for (final t in TrackStore(_db).get(ids)) t.id: t},
    );
  }

  /// Records a play. Called from the player, the one point in the app. [source]
  /// is a [sourceWord]; [heardMs] what sounded so far, the full figure comes
  /// with [setHeard] once the track is left. Returns the play's row, 0 if none.
  int log(Track track, {String source = '', int heardMs = 0}) {
    if (track.id.isEmpty) return 0;
    final ts = ref.read(playLogClockProvider)().millisecondsSinceEpoch;
    var row = 0;
    _db.tx(() {
      TrackStore(_db).put([track]);
      _db.exec(
        'INSERT INTO plays (ts, track_id, source, heard_ms) VALUES (?, ?, ?, ?)',
        [ts, track.id, source, max(0, heardMs)],
      );
      row = _db.value('SELECT last_insert_rowid()') as int;
    });
    state = PlayLog(
      events: [...state.events, PlayEvent(ts, track.id)],
      tracks: {...state.tracks, track.id: track},
    );
    return _db.committed ? row : 0;
  }

  /// A counted play's sounded time once the track is left. The play moves to
  /// a new row, returned: other devices read plays by their row, and this one
  /// may have gone out already with what had sounded by then.
  int setHeard(int row, int heardMs) {
    if (row <= 0) return 0;
    var now = 0;
    _db.tx(() {
      _db.exec(
        "INSERT INTO plays (ts, track_id, device, heard_ms, source) SELECT ts, track_id, device, ?, source FROM plays WHERE id = ? AND device = ''",
        [max(0, heardMs), row],
      );
      if (_db.changes != 1) return; // gone meanwhile (statistics cleared)
      now = _db.value('SELECT last_insert_rowid()') as int;
      _db.exec('DELETE FROM plays WHERE id = ?', [row]);
    });
    return _db.committed ? now : 0;
  }

  /// A track the listener moved away from before it counted: [heardMs]
  /// sounded, left at [posMs]. Not a play: the log's events stay as they are.
  void skip(
    Track track, {
    required int heardMs,
    required int posMs,
    String source = '',
  }) {
    if (track.id.isEmpty) return;
    final ts = ref.read(playLogClockProvider)().millisecondsSinceEpoch;
    _db.tx(() {
      TrackStore(_db).put([track]);
      _db.exec(
        'INSERT INTO skips (ts, track_id, heard_ms, pos_ms, source) VALUES (?, ?, ?, ?, ?)',
        [ts, track.id, max(0, heardMs), max(0, posMs), source],
      );
    });
  }

  /// Re-reads the log after a platform switch: its plays already moved to the
  /// new id in the database ([TrackStore.rekey]).
  void reload() => state = _read();

  /// Clears the log and the skips, part of clearing stats.
  void clear() {
    _db.tx(() {
      _db.exec('DELETE FROM plays');
      _db.exec('DELETE FROM skips');
      TrackStore(_db).prune();
    });
    state = const PlayLog();
  }
}
