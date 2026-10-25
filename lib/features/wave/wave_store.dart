/// Постоянная память волны — как у `Wave` и `Taste` ПК.
///
/// Дизлайки и «уже показывали» — таблицы `dislikes` и `wave_shown`; где
/// остановилась каждая станция, сдвиг сидов и идущая волна — kv базы под
/// ключами ПК (`wave.cursors`, `wave.rotation`, `wave.session`). Площадка
/// «Моей волны» — настройка (на ПК `waveSource`), лежит картой `wave` в
/// bloom.json.
///
/// Дизлайк ОДИН на все площадки: флага `disliked` у [Track] нет вовсе.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/db/track_store.dart';
import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart' show libraryProvider;
import '../../providers/yandex/ym_auth.dart';
import 'wave_engine.dart' show kWaveShownDays;
import 'wave_types.dart';

/// Ключ карты волны в bloom.json.
const String kWaveKey = 'wave';

const String _kSession = 'wave.session';
const String _kCursors = 'wave.cursors';
const String _kRotation = 'wave.rotation';

/// Столько станций помнят, где остановились; старые забываются первыми.
const int kMaxCursors = 300;

const int _kDay = 24 * 3600 * 1000;

/// Площадки, с которых бывает «Моя волна».
const List<MusicSource> kWaveSources = [
  MusicSource.soundcloud,
  MusicSource.ytmusic,
  MusicSource.yandex,
];

class WaveState {
  const WaveState({
    this.source = MusicSource.soundcloud,
    this.dislikes = const [],
    this.dislikedIds = const {},
  });

  /// С какой площадки «Моя волна».
  final MusicSource source;

  /// Дизлайкнутые треки, новые сверху.
  final List<Track> dislikes;

  /// Их id — для проверки «дизлайкнут ли» без перебора списка.
  final Set<String> dislikedIds;

  bool isDisliked(String trackId) => dislikedIds.contains(trackId);

  WaveState copyWith({
    MusicSource? source,
    List<Track>? dislikes,
    Set<String>? dislikedIds,
  }) => WaveState(
    source: source ?? this.source,
    dislikes: dislikes ?? this.dislikes,
    dislikedIds: dislikedIds ?? this.dislikedIds,
  );
}

final waveStoreProvider = NotifierProvider<WaveStore, WaveState>(WaveStore.new);

/// Площадка, с которой «Моя волна» идёт ПРЯМО СЕЙЧАС: выбран Яндекс, а входа
/// нет — волна не отказывает, а идёт с SoundCloud. Сам выбор не трогаем:
/// вернётся вход — вернётся и станция.
final effectiveWaveSourceProvider = Provider<MusicSource>((ref) {
  final picked = ref.watch(waveStoreProvider).source;
  if (picked != MusicSource.yandex) return picked;
  return ref.watch(ymAuthProvider).authed ? picked : MusicSource.soundcloud;
});

class WaveStore extends Notifier<WaveState> {
  JsonStore get _store => ref.read(jsonStoreProvider);
  BloomDb get _db => ref.read(dbProvider);

  /// Ключ сида → `{c: курсор, at: мс}`: новая волна на тех же сидах слышит то,
  /// что идёт дальше.
  final Map<String, Map<String, Object?>> _cursors = {};

  @override
  WaveState build() {
    _cursors.clear();
    _db.getMap(_kCursors).forEach((k, v) {
      if (v is Map) _cursors[k] = v.cast<String, Object?>();
    });
    // Показанное раньше двух недель больше не держит трек.
    _db.exec('DELETE FROM wave_shown WHERE at < ?', [
      BloomDb.now() - kWaveShownDays * _kDay,
    ]);
    // Смена площадки трека ([LibraryController.replaceTrack]) переносит и
    // дизлайк — список перечитываем вслед за библиотекой.
    ref.listen(libraryProvider, (_, _) => _reloadDislikes());

    final picked = _store.readMap(kWaveKey)['source'];
    final dislikes = _readDislikes();
    return WaveState(
      source: kWaveSources.firstWhere(
        (s) => s.code == picked,
        orElse: () => MusicSource.soundcloud,
      ),
      dislikes: dislikes,
      dislikedIds: {for (final t in dislikes) t.id},
    );
  }

  List<Track> _readDislikes() => TrackStore(_db).get([
    for (final r in _db.select(
      'SELECT track_id FROM dislikes ORDER BY at DESC',
    ))
      r['track_id'] as String,
  ]);

  void _reloadDislikes() {
    final list = _readDislikes();
    state = state.copyWith(
      dislikes: list,
      dislikedIds: {for (final t in list) t.id},
    );
  }

  // ── Площадка ────────────────────────────────────────────────────────────

  void setSource(MusicSource source) {
    if (state.source == source || !kWaveSources.contains(source)) return;
    state = state.copyWith(source: source);
    _store.write(kWaveKey, {'source': source.code});
  }

  // ── Дизлайки ────────────────────────────────────────────────────────────

  /// Поставить/снять дизлайк. Возвращает новое состояние — вызывающему нужно
  /// это для тоста.
  bool toggleDislike(Track track) {
    final on = !state.isDisliked(track.id);
    _db.tx(() {
      if (on) {
        // Снимок — чтобы список дизлайков было чем показать и потом.
        TrackStore(_db).put([track]);
        _db.exec(
          'INSERT OR REPLACE INTO dislikes (track_id, at) VALUES (?, ?)',
          [track.id, BloomDb.now()],
        );
      } else {
        _db.exec('DELETE FROM dislikes WHERE track_id = ?', [track.id]);
      }
    });
    _reloadDislikes();
    return on;
  }

  void undislike(String trackId) {
    if (!state.isDisliked(trackId)) return;
    _db.exec('DELETE FROM dislikes WHERE track_id = ?', [trackId]);
    _reloadDislikes();
  }

  void clearDislikes() {
    if (state.dislikes.isEmpty) return;
    _db.exec('DELETE FROM dislikes');
    _reloadDislikes();
  }

  // ── «Уже показывали» ────────────────────────────────────────────────────

  /// Отметить, что треки побывали в выдаче волны, — пачкой.
  void markShown(Iterable<String> trackIds) {
    final ids = trackIds.toList();
    if (ids.isEmpty) return;
    final now = BloomDb.now();
    _db.tx(() {
      for (final id in ids) {
        _db.exec(
          'INSERT OR REPLACE INTO wave_shown (track_id, at) VALUES (?, ?)',
          [id, now],
        );
      }
    });
  }

  /// Что волна показывала за последние [withinDays] дней — одним запросом на
  /// пачку, а не по запросу на каждого кандидата.
  Set<String> shownIds({int withinDays = kWaveShownDays}) => {
    for (final r in _db.select(
      'SELECT track_id FROM wave_shown WHERE at >= ?',
      [BloomDb.now() - withinDays * _kDay],
    ))
      r['track_id'] as String,
  };

  // ── Курсоры станций ─────────────────────────────────────────────────────

  String cursorOf(WaveSeed seed) => _cursors[seed.key]?['c'] as String? ?? '';

  /// Запомнить, где станции продолжать, — пачкой за один опрос сидов.
  void saveCursors(Map<WaveSeed, String> next) {
    if (next.isEmpty) return;
    final now = BloomDb.now();
    next.forEach((seed, c) => _cursors[seed.key] = {'c': c, 'at': now});
    if (_cursors.length > kMaxCursors) {
      final byAge = _cursors.entries.toList()
        ..sort(
          (a, b) => ((a.value['at'] as num?) ?? 0).compareTo(
            (b.value['at'] as num?) ?? 0,
          ),
        );
      for (final e in byAge.take(_cursors.length - kMaxCursors)) {
        _cursors.remove(e.key);
      }
    }
    _db.set(_kCursors, _cursors);
  }

  // ── Сдвиг сидов «Моей волны» ────────────────────────────────────────────

  int get rotation => (_db.get(_kRotation, 0) as num?)?.toInt() ?? 0;

  /// Текущий сдвиг, а следующей волне — следующий.
  int takeRotation() {
    final r = rotation;
    _db.set(_kRotation, r + 1);
    return r;
  }

  // ── Идущая волна ────────────────────────────────────────────────────────

  WaveRun? get savedRun => WaveRun.fromJson(_db.get(_kSession));

  void saveRun(WaveRun? run) => _db.set(_kSession, run?.toJson());
}
