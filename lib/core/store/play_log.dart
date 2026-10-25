/// Журнал прослушиваний — единственное хранилище «что и когда слушали»:
/// таблица `plays` базы (порт `PlayLog` ПК). Одна строка на засчитанное
/// прослушивание; из журнала выводятся «История», статистика профиля, сиды
/// волны и «Итоги» — своих счётчиков больше нет нигде.
///
/// Снимок трека (название, обложка, длительность) лежит в `tracks` базы: он
/// нужен и через год, когда самого трека давно нет в библиотеке.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../db/track_store.dart';
import '../entities/entities.dart';

/// Часы журнала — ради тестов (тот же приём, что у `notifClockProvider`).
final playLogClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Одно засчитанное прослушивание.
@immutable
class PlayEvent {
  const PlayEvent(this.ts, this.id);

  /// Момент, когда прослушивание засчитано (90% трека или его конец).
  final int ts;
  final String id;
}

@immutable
class PlayLog {
  const PlayLog({this.events = const [], this.tracks = const {}});

  /// Все события, по возрастанию `ts`.
  final List<PlayEvent> events;

  /// Снимки всех когда-либо игранных треков.
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

  /// Записать прослушивание. Зовётся из плеера — одна точка на всё приложение.
  void log(Track track) {
    if (track.id.isEmpty) return;
    final ts = ref.read(playLogClockProvider)().millisecondsSinceEpoch;
    _db.tx(() {
      TrackStore(_db).put([track]);
      _db.exec('INSERT INTO plays (ts, track_id) VALUES (?, ?)', [
        ts,
        track.id,
      ]);
    });
    state = PlayLog(
      events: [...state.events, PlayEvent(ts, track.id)],
      tracks: {...state.tracks, track.id: track},
    );
  }

  /// Перечитать журнал — после смены площадки трека: его прослушивания уже
  /// переехали на новый id в самой базе ([TrackStore.rekey]).
  void reload() => state = _read();

  /// Очистить журнал — часть «Очистить статистику» в профиле.
  void clear() {
    _db.tx(() {
      _db.exec('DELETE FROM plays');
      TrackStore(_db).prune();
    });
    state = const PlayLog();
  }
}
