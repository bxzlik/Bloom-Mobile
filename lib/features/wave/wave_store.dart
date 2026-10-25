/// Постоянная память волны: дизлайки, пометки «уже показывали», курсоры
/// станций, ротация сидов и выбранная площадка.
///
/// Дизлайки и «уже показывали» — таблицы базы `dislikes` и `wave_shown`, как
/// на ПК (`Taste::setDisliked`, `Wave`): дизлайк знает своё время (список —
/// новые сверху), снимок трека держит `tracks`. Остальное пока лежит картой
/// `wave` в bloom.json.
///
/// Дизлайк ОДИН на все площадки: флага `disliked` у [Track] нет вовсе.
///
/// Сеанс волны сюда же и сохраняется: очередь за нас уже сохраняет снимок
/// «Продолжить» (`resume_store` держит сами треки), а здесь остаётся память
/// подбора — сиды, что уже играло и кого поднимать.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/db/track_store.dart';
import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart' show libraryProvider;
import '../../providers/yandex/ym_auth.dart';
import 'wave_types.dart';

/// Ключ карты волны в bloom.json.
const String kWaveKey = 'wave';

/// Сколько дней трек, показанный волной, не возвращается в выдачу.
const int kShownTtlDays = 14;

/// Насколько шагает курсор станции за одну пачку — ровно на её размер.
const int kStationStep = 20;

const int _kDay = 24 * 3600 * 1000;

class WaveState {
  const WaveState({
    this.source = WaveEngineKind.soundcloud,
    this.dislikes = const [],
    this.dislikedIds = const {},
  });

  /// Чем набирать «Мою волну»: движком по SoundCloud или станцией Яндекса.
  final WaveEngineKind source;

  /// Дизлайкнутые треки, новые сверху.
  final List<Track> dislikes;

  /// Их id — для проверки «дизлайкнут ли» без перебора списка.
  final Set<String> dislikedIds;

  bool isDisliked(String trackId) => dislikedIds.contains(trackId);

  WaveState copyWith({
    WaveEngineKind? source,
    List<Track>? dislikes,
    Set<String>? dislikedIds,
  }) => WaveState(
    source: source ?? this.source,
    dislikes: dislikes ?? this.dislikes,
    dislikedIds: dislikedIds ?? this.dislikedIds,
  );
}

final waveStoreProvider = NotifierProvider<WaveStore, WaveState>(WaveStore.new);

/// Площадка, которой волна набирается ПРЯМО СЕЙЧАС.
///
/// От выбранной отличается одним: вышли из Яндекса — волна не отказывает, а
/// продолжает работать своим движком по SoundCloud. Сам выбор при этом не
/// трогаем: вернётся вход — вернётся и станция.
final effectiveWaveSourceProvider = Provider<WaveEngineKind>((ref) {
  final picked = ref.watch(waveStoreProvider).source;
  if (picked != WaveEngineKind.yandex) return picked;
  return ref.watch(ymAuthProvider).authed
      ? WaveEngineKind.yandex
      : WaveEngineKind.soundcloud;
});

class WaveStore extends Notifier<WaveState> {
  JsonStore get _store => ref.read(jsonStoreProvider);
  BloomDb get _db => ref.read(dbProvider);

  /// SC-id сида → смещение в его станции. Переживает конец сеанса: иначе
  /// каждая новая волна начинала бы с нулевого смещения и предлагала те же
  /// двадцать треков.
  final Map<String, int> _cursors = {};

  /// Счётчик «карусели» сидов: каждая новая волна сдвигает выбор, чтобы не
  /// упираться вечно в одни и те же два трека из топа.
  int _rotation = 0;

  /// Сохранённый сеанс — его подхватывает «Продолжить», когда снимок сессии
  /// оказался волновым.
  WaveSession? _savedSession;

  @override
  WaveState build() {
    final raw = _store.readMap(kWaveKey);

    _rotation = (raw['rotation'] as num?)?.toInt() ?? 0;
    final cursors = raw['cursors'];
    if (cursors is Map) {
      cursors.forEach((k, v) {
        if (k is String && v is num) _cursors[k] = v.toInt();
      });
    }
    _savedSession = WaveSession.fromJson(raw['session']);

    // Показанное раньше двух недель больше не держит трек — как `Wave` ПК.
    _db.exec('DELETE FROM wave_shown WHERE at < ?', [
      BloomDb.now() - kShownTtlDays * _kDay,
    ]);
    // Смена площадки трека ([LibraryController.replaceTrack]) переносит и
    // дизлайк — список перечитываем вслед за библиотекой.
    ref.listen(libraryProvider, (_, _) => _reloadDislikes());

    final dislikes = _readDislikes();
    return WaveState(
      source: raw['source'] == WaveEngineKind.yandex.name
          ? WaveEngineKind.yandex
          : WaveEngineKind.soundcloud,
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

  void _save() {
    _store.write(kWaveKey, {
      'source': state.source.name,
      'rotation': _rotation,
      'cursors': _cursors,
      if (_savedSession != null) 'session': _savedSession!.toJson(),
    });
  }

  // ── Площадка ────────────────────────────────────────────────────────────

  void setSource(WaveEngineKind source) {
    if (state.source == source) return;
    state = state.copyWith(source: source);
    _save();
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

  /// Отметить, что трек побывал в выдаче волны — пачкой.
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
  Set<String> shownIds({int withinDays = kShownTtlDays}) => {
    for (final r in _db.select('SELECT track_id FROM wave_shown WHERE at > ?', [
      BloomDb.now() - withinDays * _kDay,
    ]))
      r['track_id'] as String,
  };

  // ── Курсоры станций ─────────────────────────────────────────────────────

  int cursorOf(String scId) => _cursors[scId] ?? 0;

  Map<String, int> cursorsFor(Iterable<String> scIds) => {
    for (final id in scIds) id: cursorOf(id),
  };

  /// Сдвинуть курсор сида на одну пачку вперёд.
  void advanceCursor(String scId) {
    _cursors[scId] = cursorOf(scId) + kStationStep;
    _save();
  }

  /// Станция кончилась (пустой ответ на ненулевом смещении) — начинаем её
  /// сначала, иначе после долгих сеансов волна упёрлась бы в пустоту навсегда.
  void resetCursor(String scId) {
    if (_cursors.remove(scId) == null) return;
    _save();
  }

  // ── Ротация сидов ───────────────────────────────────────────────────────

  int get rotation => _rotation;

  void bumpRotation() {
    _rotation++;
    _save();
  }

  // ── Сеанс ───────────────────────────────────────────────────────────────

  WaveSession? get savedSession => _savedSession;

  void saveSession(WaveSession? session) {
    _savedSession = session;
    _save();
  }
}
