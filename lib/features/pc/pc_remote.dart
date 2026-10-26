/// Телефон — пульт ПК (Connect): пока ПК в сети и играл позже телефона, на
/// экране то, что играет там, и все кнопки жмут там. Звук остаётся на том
/// устройстве, где играло последним, — как в Spotify; перенести его — «Играть
/// на».
///
/// Своё состояние телефона (очередь, сессия) при этом не трогается: связь
/// пропала — телефон снова показывает своё. Сторона ПК — `ConnectHost`
/// (`src/devices/ConnectHost.cpp`) и поток событий API.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/entities/entities.dart';
import '../../core/log/bloom_log.dart';
import '../../core/sync/pc_client.dart';
import '../../providers/yandex/ym_provider.dart' show ymNumericId;
import '../player/play_source.dart';
import '../player/player_controller.dart';
import '../player/session_store.dart' show SessionData;

/// Когда на этом устройстве последний раз шёл звук, мс — та же отметка, что
/// `connect.played` ПК. Пишет плеер.
const String kConnectPlayed = 'connect.played';

/// Что играет на ПК.
@immutable
class PcPlayback {
  const PcPlayback({
    required this.playback,
    required this.playing,
    required this.position,
    required this.positionAt,
    required this.duration,
    required this.liked,
  });

  /// Очередь, номер, режимы, источник — в том виде, что у своего плеера.
  final PlaybackState playback;
  final bool playing;

  /// Позиция, сказанная ПК, и когда это было: дальше она идёт сама.
  final Duration position;
  final DateTime positionAt;
  final Duration duration;
  final bool liked;

  Playhead playheadAt(DateTime now) {
    var p = position;
    if (playing) p += now.difference(positionAt);
    if (duration > Duration.zero && p > duration) p = duration;
    return (position: p, total: duration);
  }
}

/// `null` — телефон не пульт: играет своё.
final pcRemoteProvider = NotifierProvider<PcRemoteController, PcPlayback?>(
  PcRemoteController.new,
);

class PcRemoteController extends Notifier<PcPlayback?> {
  BloomDb get _db => ref.read(dbProvider);

  PcClient? _client;

  /// Последнее, что сказал ПК; `null` — ещё не спрашивали.
  _Pc? _pc;
  StreamSubscription<bool>? _ownPlaying;
  Timer? _refetch;

  /// Звук забрали сюда («Играть на телефоне»): телефон не пульт, пока ПК сам
  /// снова не заиграет.
  bool _pinned = false;
  int _pinnedAt = 0;

  @override
  PcPlayback? build() {
    ref.onDispose(() {
      _refetch?.cancel();
      _ownPlaying?.cancel();
    });
    return null;
  }

  // ── Связь (её держит PcController) ─────────────────────────────────────

  /// Открылся поток событий ПК.
  void attach(PcClient client) {
    _client = client;
    _ownPlaying ??= ref
        .read(audioPlayerProvider)
        .playingStream
        .listen((_) => _decide());
    unawaited(_fetch());
  }

  /// Поток оборвался: телефон снова сам по себе.
  void detach() {
    _client = null;
    _pc = null;
    _pinned = false;
    _refetch?.cancel();
    _ownPlaying?.cancel();
    _ownPlaying = null;
    if (state != null) logInfo('connect', 'телефон больше не пульт ПК');
    state = null;
  }

  void onEvent(PcEvent e) {
    final d = e.data;
    // Звук двигают с ПК: двигает всё равно телефон, он знает обе очереди.
    if (e.name == 'connect') {
      switch (d['do']) {
        case 'take':
          unawaited(playHere());
        case 'give':
          unawaited(playOnPc());
      }
      return;
    }
    final pc = _pc;
    if (pc == null) return;
    switch (e.name) {
      case 'player':
        pc.playing = d['playing'] == true;
        pc.liked = d['liked'] == true;
        pc.shuffle = d['shuffle'] == true;
        pc.repeat = _repeat(d['repeat']);
        pc.source = PlaySource.fromJson(d['source']);
        _setPosition(pc, d);
        final index = _int(d['index'], -1);
        final id = (d['track'] as Map?)?['id'];
        // Очередь поменялась не нашим событием — берём её целиком заново.
        if (_int(d['queueLength'], 0) != pc.tracks.length ||
            index < 0 ||
            index >= pc.tracks.length ||
            pc.tracks[index].id != id) {
          _fetchSoon();
        } else {
          pc.index = index;
        }
      case 'position':
        pc.playing = d['playing'] == true;
        _setPosition(pc, d);
      case 'queue':
        _fetchSoon();
      default:
        return;
    }
    if (pc.playing) pc.at = BloomDb.now();
    _decide();
  }

  // ── «Играть на» ────────────────────────────────────────────────────────

  /// Звук — сюда: очередь ПК с той же секунды играет на телефоне, ПК замолкает.
  Future<void> playHere() async {
    final client = _client;
    if (client == null) return;
    try {
      final d = await client.json('GET', '/v1/connect');
      List<Track> tracks(Object? list) => [
        for (final t in (list as List?) ?? const []) ?Track.fromJson(t),
      ];
      final queue = tracks(d['tracks']);
      final index = _int(d['index'], -1);
      if (index < 0 || index >= queue.length) return;
      final position = d['position'] is num
          ? Duration(milliseconds: ((d['position'] as num) * 1000).round())
          : Duration.zero;
      _pinned = true;
      _pinnedAt = BloomDb.now();
      state = null;
      logInfo('connect', 'звук — на телефон');
      await ref
          .read(playbackProvider.notifier)
          .resumeSession(
            SessionData(
              queue: queue,
              orig: tracks(d['orig']),
              index: index,
              position: position,
              savedAt: DateTime.now(),
              source: PlaySource.fromJson(d['source']),
              shuffle: d['shuffle'] == true,
              repeat: _repeat(d['repeat']),
            ),
          );
      await client.json('POST', '/v1/connect/took', body: const {});
    } catch (e) {
      logWarn('connect', 'звук с ПК не забран: $e');
    }
  }

  /// Звук — на ПК: своя сессия с той же секунды играет там, телефон замолкает
  /// и становится пультом.
  Future<void> playOnPc() async {
    final client = _client;
    final playback = ref.read(playbackProvider.notifier);
    final own = playback.localSession();
    if (client == null || own == null) return;
    try {
      await client.json(
        'POST',
        '/v1/connect/take',
        body: {
          'tracks': [for (final t in own.queue) t.toJson()],
          'orig': [for (final t in own.orig) t.toJson()],
          'index': own.index,
          'position': own.position.inMilliseconds / 1000,
          'shuffle': own.shuffle,
          'repeat': own.repeat.name,
          'source': own.source?.toJson() ?? const {},
        },
      );
      logInfo('connect', 'звук — на ПК');
      _pinned = false;
      await playback.pauseLocal();
      _pc?.playing = true;
      _pc?.at = BloomDb.now();
      _decide();
    } catch (e) {
      logWarn('connect', 'звук на ПК не ушёл: $e');
    }
  }

  // ── Команды ────────────────────────────────────────────────────────────

  Future<void> toggle() {
    _pc?.playing = !(_pc?.playing ?? false);
    _decide();
    return _post('/v1/player/toggle');
  }

  Future<void> play() => _post('/v1/player/play');
  Future<void> pause() => _post('/v1/player/pause');
  Future<void> next() => _post('/v1/player/next');
  Future<void> prev() => _post('/v1/player/prev');

  Future<void> seek(Duration to) {
    final pc = _pc;
    if (pc != null) {
      pc.position = to;
      pc.positionAt = DateTime.now();
      _decide();
    }
    return _post('/v1/player/seek', {'position': to.inMilliseconds / 1000});
  }

  Future<void> jumpTo(int index) => _post('/v1/queue/jump', {'index': index});
  Future<void> removeAt(int index) =>
      _post('/v1/queue/remove', {'index': index});

  /// Индексы — как у своего [PlaybackController.reorder] (`to` до изъятия).
  Future<void> reorder(int from, int to) =>
      _post('/v1/queue/move', {'from': from, 'to': to > from ? to - 1 : to});

  Future<void> cycleRepeat() => _post('/v1/player/repeat');
  Future<void> toggleShuffle() => _post('/v1/player/shuffle');
  Future<void> clearExceptCurrent() => _post('/v1/connect/clear');

  Future<void> playQueue(
    List<Track> tracks,
    int index, {
    PlaySource? source,
    bool shuffle = false,
  }) => _post('/v1/connect/play', {
    'tracks': [for (final t in tracks) t.toJson()],
    'index': index,
    'source': source?.toJson() ?? const {},
    'shuffle': shuffle,
  });

  /// Сколько встанет — заранее не знаем: ПК сам отсеет стоящие в очереди.
  int enqueue(List<Track> tracks, {bool next = false, PlaySource? source}) {
    if (tracks.isEmpty) return 0;
    unawaited(
      _post('/v1/connect/enqueue', {
        'tracks': [for (final t in tracks) t.toJson()],
        'next': next,
        'source': source?.toJson() ?? const {},
      }),
    );
    return tracks.length;
  }

  Future<void> wavePersonal() =>
      _post('/v1/connect/wave', {'from': 'personal'});
  Future<void> waveQueue() => _post('/v1/connect/wave', {'from': 'queue'});
  Future<void> waveTrack(Track track) =>
      _post('/v1/connect/wave', {'from': 'track', 'track': track.toJson()});
  Future<void> waveArtist(Artist artist, List<Track> tracks) =>
      _post('/v1/connect/wave', {
        'from': 'artist',
        'artist': {
          'id': artist.id,
          'name': artist.name,
          'provider': artist.source.code,
          'extra': {'ymId': ymNumericId(artist.id)},
        },
        'tracks': [for (final t in tracks) t.toJson()],
      });

  Future<void> _post(String path, [Map<String, Object?>? body]) async {
    final client = _client;
    if (client == null) return;
    _pc?.at = BloomDb.now(); // что нажали здесь — играло на ПК
    try {
      await client.json(
        'POST',
        path,
        body: body ?? const {},
        timeout: const Duration(seconds: 8),
      );
    } catch (e) {
      logWarn('connect', '$path не дошло до ПК: $e');
    }
  }

  // ── Внутреннее ─────────────────────────────────────────────────────────

  void _fetchSoon() {
    _refetch?.cancel();
    _refetch = Timer(const Duration(milliseconds: 120), _fetch);
  }

  Future<void> _fetch() async {
    final client = _client;
    if (client == null) return;
    try {
      final d = await client.json('GET', '/v1/connect');
      if (!identical(client, _client)) return;
      final pc = _pc ?? _Pc();
      pc
        ..tracks = [
          for (final t in (d['tracks'] as List?) ?? const [])
            ?Track.fromJson(t),
        ]
        ..index = _int(d['index'], -1)
        ..playing = d['playing'] == true
        ..shuffle = d['shuffle'] == true
        ..repeat = _repeat(d['repeat'])
        ..liked = d['liked'] == true
        ..source = PlaySource.fromJson(d['source']);
      _setPosition(pc, d);
      if (_pc == null) pc.at = _int(d['at'], 0);
      if (pc.playing) pc.at = BloomDb.now();
      _pc = pc;
      _decide();
    } catch (e) {
      logWarn('connect', 'состояние ПК не получено: $e');
    }
  }

  /// Пульт ли телефон. Своё играет — нет: не обрываем то, что в ушах. Иначе —
  /// если ПК играет или играл позже. Став пультом, телефон им и остаётся, пока
  /// жива связь: всё, что жмут здесь, играет там.
  void _decide() {
    final pc = _pc;
    if (pc == null || _client == null) {
      state = null;
      return;
    }
    final ownPlaying = ref.read(audioPlayerProvider).playing;
    // Забрали сюда — пока ПК сам не заиграет, звук тут.
    // Пару секунд после переноса ПК ещё доигрывает — это не «заиграл сам».
    if (_pinned &&
        pc.playing &&
        !ownPlaying &&
        BloomDb.now() - _pinnedAt > 3000) {
      _pinned = false;
    }
    if (_pinned) {
      state = null;
      return;
    }
    final ownAt = _int(_db.get(kConnectPlayed), 0);
    final remote =
        !ownPlaying && (state != null || pc.playing || pc.at >= ownAt);
    if (!remote) {
      state = null;
      return;
    }
    if (state == null) logInfo('connect', 'телефон — пульт ПК');
    state = PcPlayback(
      playback: PlaybackState(
        queue: pc.tracks,
        index: pc.index,
        shuffle: pc.shuffle,
        repeat: pc.repeat,
        source: pc.source,
      ),
      playing: pc.playing,
      position: pc.position,
      positionAt: pc.positionAt,
      duration: pc.duration,
      liked: pc.liked,
    );
  }

  static void _setPosition(_Pc pc, Map<String, Object?> d) {
    if (d['position'] is num) {
      pc.position = Duration(
        milliseconds: ((d['position'] as num) * 1000).round(),
      );
      pc.positionAt = DateTime.now();
    }
    if (d['duration'] is num) {
      pc.duration = Duration(
        milliseconds: ((d['duration'] as num) * 1000).round(),
      );
    }
  }

  static PlayerRepeat _repeat(Object? v) => switch (v) {
    'all' => PlayerRepeat.all,
    'one' => PlayerRepeat.one,
    _ => PlayerRepeat.off,
  };

  static int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;
}

/// Изменчивое состояние ПК внутри контроллера; наружу — [PcPlayback].
class _Pc {
  List<Track> tracks = const [];
  int index = -1;
  bool playing = false;
  bool shuffle = false;
  bool liked = false;
  PlayerRepeat repeat = PlayerRepeat.off;
  PlaySource? source;
  Duration position = Duration.zero;
  DateTime positionAt = DateTime.now();
  Duration duration = Duration.zero;

  /// Когда на ПК играло последним, мс.
  int at = 0;
}
