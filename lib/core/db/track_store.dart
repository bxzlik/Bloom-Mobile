/// Снимки треков в таблице `tracks` — порт `TrackStore` ПК.
///
/// Всё, что показывает трек потом (списки, история, сеанс, дизлайки), берёт
/// его отсюда. Запись — «слить с тем, что есть»: пустое поле не затирает
/// заполненное, `extra` сливается (`json_patch`), а трек, теги которого правили
/// руками (`extra.edited`, правка с ПК), своё название, артиста, альбом и
/// обложку сохраняет.
library;

import 'dart:convert';

import '../entities/entities.dart';
import '../sync/sync_log.dart';
import 'db.dart';

/// SQLite принимает до 32766 параметров; пачки поменьше держат запрос дешёвым.
const int _chunk = 500;

String _marks(int n) => List.filled(n, '?').join(',');

class TrackStore {
  const TrackStore(this.db);

  final BloomDb db;

  void put(Iterable<Track> tracks) {
    final list = tracks.where((t) => t.id.isNotEmpty).toList();
    if (list.isEmpty) return;
    db.tx(() {
      final now = BloomDb.now();
      final upsert = db.prepare(
        '''INSERT INTO tracks (id, provider, title, artist, album, cover, duration, extra, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                provider = excluded.provider,
                title = CASE WHEN extra ->> '\$.edited' OR excluded.title = '' THEN title ELSE excluded.title END,
                artist = CASE WHEN extra ->> '\$.edited' OR excluded.artist = '' THEN artist ELSE excluded.artist END,
                album = CASE WHEN extra ->> '\$.edited' OR excluded.album = '' THEN album ELSE excluded.album END,
                cover = CASE WHEN extra ->> '\$.edited' OR excluded.cover = '' THEN cover ELSE excluded.cover END,
                duration = CASE WHEN excluded.duration > 0 THEN excluded.duration ELSE duration END,
                extra = CASE WHEN extra ->> '\$.edited'
                    THEN json_patch(json_patch(extra, excluded.extra),
                                    json_object('year', extra -> '\$.year', 'genres', extra -> '\$.genres', 'publisher', extra -> '\$.publisher'))
                    ELSE json_patch(extra, excluded.extra) END,
                updated_at = excluded.updated_at''',
      );
      try {
        for (final t in list) {
          final m = t.toJson();
          upsert.execute([
            m['id'],
            m['provider'],
            m['title'],
            m['artist'],
            m['album'],
            m['cover'],
            m['duration'],
            jsonEncode(m['extra']),
            now,
          ]);
        }
      } finally {
        upsert.close();
      }
    });
  }

  Track? getOne(String id) {
    final one = get([id]);
    return one.isEmpty ? null : one.first;
  }

  /// Треки в порядке [ids]; неизвестных id в ответе нет.
  List<Track> get(List<String> ids) {
    final found = <String, Track>{};
    for (var at = 0; at < ids.length; at += _chunk) {
      final part = ids.sublist(at, (at + _chunk).clamp(0, ids.length));
      for (final row in db.select(
        'SELECT id, provider, title, artist, album, cover, duration, extra FROM tracks WHERE id IN (${_marks(part.length)})',
        part,
      )) {
        final t = trackOfRow(row);
        if (t != null) found[t.id] = t;
      }
    }
    return [for (final id in ids) ?found[id]];
  }

  /// Трек из строки `tracks` (колонки — как в запросе [get]).
  static Track? trackOfRow(Map<String, Object?> row) {
    Object? extra;
    try {
      extra = jsonDecode(row['extra'] as String? ?? '{}');
    } catch (_) {
      extra = const {};
    }
    return Track.fromJson({...row, 'extra': extra});
  }

  /// Трек сменил id (смена площадки): все ссылки едут за ним. Если новый id
  /// уже известен — места в списках сливаются (раньшее место), прослушивания
  /// складываются.
  bool rekey(String from, String to) {
    if (from.isEmpty || to.isEmpty || from == to) return false;
    db.tx(() {
      if (db.value('SELECT 1 FROM tracks WHERE id = ?', [to]) == null) {
        // Сливать не с чем: каскады несут каждую ссылку сами.
        db.exec('UPDATE tracks SET id = ? WHERE id = ?', [to, from]);
      } else {
        db.exec(
          '''UPDATE list_tracks SET pos = min(pos, (SELECT o.pos FROM list_tracks o WHERE o.list_id = list_tracks.list_id AND o.track_id = ?)),
                added_at = min(added_at, (SELECT o.added_at FROM list_tracks o WHERE o.list_id = list_tracks.list_id AND o.track_id = ?))
            WHERE track_id = ? AND list_id IN (SELECT list_id FROM list_tracks WHERE track_id = ?)''',
          [from, from, to, from],
        );
        db.exec(
          'UPDATE OR IGNORE list_tracks SET track_id = ? WHERE track_id = ?',
          [to, from],
        );
        db.exec('UPDATE plays SET track_id = ? WHERE track_id = ?', [to, from]);
        db.exec('UPDATE files SET track_id = ? WHERE track_id = ?', [to, from]);
        db.exec('UPDATE session_tracks SET track_id = ? WHERE track_id = ?', [
          to,
          from,
        ]);
        db.exec(
          'UPDATE OR IGNORE dislikes SET track_id = ? WHERE track_id = ?',
          [to, from],
        );
        // Остальное уходит каскадом, офлайн-копия тоже: в ней звук другого трека.
        db.exec('DELETE FROM tracks WHERE id = ?', [from]);
      }
      db.exec('UPDATE OR IGNORE loudness SET track_id = ? WHERE track_id = ?', [
        to,
        from,
      ]);
      db.exec('DELETE FROM loudness WHERE track_id = ?', [from]);
      // Другие устройства переносят свои прослушивания и места тоже.
      SyncLog(db).markRekey(from, to);
    });
    return true;
  }

  /// Выбросить треки, на которые больше никто не ссылается. Возвращает сколько.
  int prune() => db.tx(() {
    db.exec(
      '''DELETE FROM tracks WHERE
        NOT EXISTS (SELECT 1 FROM list_tracks WHERE track_id = tracks.id) AND
        NOT EXISTS (SELECT 1 FROM plays WHERE track_id = tracks.id) AND
        NOT EXISTS (SELECT 1 FROM session_tracks WHERE track_id = tracks.id) AND
        NOT EXISTS (SELECT 1 FROM dislikes WHERE track_id = tracks.id) AND
        NOT EXISTS (SELECT 1 FROM files WHERE track_id = tracks.id AND folder IS NOT NULL)''',
    );
    return db.changes;
  });
}
