/// Постоянная память волны: дизлайки, пометки «уже показывали», курсоры
/// станций, ротация сидов и выбранная площадка.
///
/// На десктопе это четыре отдельных ключа localStorage (`bloom_wave_shown`,
/// `bloom_wave_station_offsets`, `bloom_wave_seed_rotation`,
/// `bloom_wave_source`) плюс стор дизлайков; здесь всё лежит одной картой
/// `wave` в bloom.json — файл общий, и плодить в нём ключи под каждый счётчик
/// незачем.
///
/// Дизлайк у нас ОДИН на все площадки, без деления на «библиотечный флаг» и
/// «гостевой стор», как на ПК: флага `disliked` у [Track] нет вовсе (у
/// смешанных источников его некуда положить — ровно та же причина, по которой
/// лайки живут отдельным набором id, см. `library_store`).
///
/// Сеанс волны сюда же и сохраняется: очередь за нас уже сохраняет снимок
/// «Продолжить» (`resume_store` держит сами треки), а здесь остаётся память
/// подбора — сиды, что уже играло и кого поднимать.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;
import '../../providers/yandex/ym_auth.dart';
import 'wave_types.dart';

/// Ключ карты волны в bloom.json.
const String kWaveKey = 'wave';

/// Сколько дней трек, показанный волной, не возвращается в выдачу.
const int kShownTtlDays = 14;

/// Потолок пометок «показано». Дальше вытесняем самые старые: карта растёт по
/// двадцать записей на каждую пачку и без предела съела бы файл.
const int kShownLimit = 1000;

/// Насколько шагает курсор станции за одну пачку — ровно на её размер.
const int kStationStep = 20;

class WaveState {
  const WaveState({
    this.source = WaveEngineKind.soundcloud,
    this.dislikes = const {},
  });

  /// Чем набирать «Мою волну»: движком по SoundCloud или станцией Яндекса.
  final WaveEngineKind source;

  /// Дизлайкнутые треки: id → снимок трека (список дизлайков надо чем-то
  /// показывать и после перезапуска).
  final Map<String, Track> dislikes;

  bool isDisliked(String trackId) => dislikes.containsKey(trackId);

  WaveState copyWith({WaveEngineKind? source, Map<String, Track>? dislikes}) =>
      WaveState(
        source: source ?? this.source,
        dislikes: dislikes ?? this.dislikes,
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

  /// SC-id сида → смещение в его станции. Переживает конец сеанса: иначе
  /// каждая новая волна начинала бы с нулевого смещения и предлагала те же
  /// двадцать треков.
  final Map<String, int> _cursors = {};

  /// id трека → когда его показала волна.
  final Map<String, int> _shown = {};

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
    final shown = raw['shown'];
    if (shown is Map) {
      shown.forEach((k, v) {
        if (k is String && v is num) _shown[k] = v.toInt();
      });
    }
    _savedSession = WaveSession.fromJson(raw['session']);

    final dislikes = <String, Track>{};
    for (final item in (raw['dislikes'] as List?) ?? const []) {
      final t = Track.fromJson(item);
      if (t != null) dislikes[t.id] = t;
    }
    return WaveState(
      source: raw['source'] == WaveEngineKind.yandex.name
          ? WaveEngineKind.yandex
          : WaveEngineKind.soundcloud,
      dislikes: dislikes,
    );
  }

  void _save() {
    _store.write(kWaveKey, {
      'source': state.source.name,
      'rotation': _rotation,
      'cursors': _cursors,
      'shown': _shown,
      'dislikes': [for (final t in state.dislikes.values) t.toJson()],
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
    final next = Map<String, Track>.from(state.dislikes);
    final on = !next.containsKey(track.id);
    if (on) {
      next[track.id] = track;
    } else {
      next.remove(track.id);
    }
    state = state.copyWith(dislikes: next);
    _save();
    return on;
  }

  void undislike(String trackId) {
    if (!state.dislikes.containsKey(trackId)) return;
    state = state.copyWith(
      dislikes: Map<String, Track>.from(state.dislikes)..remove(trackId),
    );
    _save();
  }

  void clearDislikes() {
    if (state.dislikes.isEmpty) return;
    state = state.copyWith(dislikes: const {});
    _save();
  }

  // ── «Уже показывали» ────────────────────────────────────────────────────

  /// Отметить, что трек побывал в выдаче волны. Пачками, а не по одному:
  /// запись файла отложенная, но перебирать карту двадцать раз подряд незачем.
  void markShown(Iterable<String> trackIds) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var touched = false;
    for (final id in trackIds) {
      _shown[id] = now;
      touched = true;
    }
    if (!touched) return;
    _pruneShown(now);
    _save();
  }

  bool wasShown(String trackId, {int withinDays = kShownTtlDays}) {
    final at = _shown[trackId];
    if (at == null) return false;
    return DateTime.now().millisecondsSinceEpoch - at <
        withinDays * 24 * 3600 * 1000;
  }

  void _pruneShown(int now) {
    final cutoff = now - kShownTtlDays * 24 * 3600 * 1000;
    _shown.removeWhere((_, at) => at < cutoff);
    if (_shown.length <= kShownLimit) return;
    // Держим самые свежие: старые всё равно вот-вот истекут по сроку.
    final byAge = _shown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _shown
      ..clear()
      ..addEntries(byAge.take(kShownLimit));
  }

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
