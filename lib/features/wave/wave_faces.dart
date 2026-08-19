/// «Лица волны» — обложки для кольца на главной. Порт `src/wave/faces.ts`.
///
/// Это НЕ библиотека: в кольце стоит то, что реально зазвучало бы в волне
/// ВЫБРАННОЙ площадки, поэтому переключатель SoundCloud/Яндекс меняет и
/// содержимое кольца:
///   • SoundCloud — похожие на несколько личных сидов (тот же источник, из
///     которого движок собирает пачку);
///   • Яндекс — батч станции `user:onyourwave` (та же станция, что и «Моя
///     волна»).
///
/// Витрина НЕ трогает состояние настоящей волны: ни сеанса, ни курсоров
/// станций, ни пометок «показано» — только кэшируемые запросы. Поэтому здесь и
/// не используется [WaveEngine]: ему нужен живой сеанс, и он двигает курсоры.
///
/// Отличие от десктопа: плитка несёт сам [Track], а не id с обложкой. Реестра
/// треков в памяти у нас нет — по одному id волну потом было бы не с чего
/// запустить.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../providers/soundcloud/sc_provider.dart' show trackFromSc;
import '../../providers/yandex/ym_provider.dart' show trackFromYm;
import '../../providers/yandex/yandex.dart' as ym;
import 'wave_seeds.dart';
import 'wave_sources.dart';
import 'wave_store.dart';
import 'wave_types.dart';

/// Сколько личных сидов раскрываем через «похожие». Каждый — отдельный запрос.
const int _kScSeeds = 3;

const Duration _ttl = Duration(minutes: 20);

class _Entry {
  _Entry(this.at, this.faces);
  final DateTime at;
  final List<Track> faces;
}

final Map<WaveEngineKind, _Entry> _cache = {};
final Map<WaveEngineKind, Future<List<Track>>> _inflight = {};

/// Обложки для кольца выбранной площадки. Пустой список — получить не вышло
/// (нет сети, не вошли в аккаунт, у сидов нет похожих): интерфейс сам решит,
/// что показать вместо них.
Future<List<Track>> fetchWaveFaces(
  WaveEngineKind source, {
  required WaveLibrary view,
  required int rotation,
  int limit = 8,
}) {
  final hit = _cache[source];
  if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
    return Future.value(hit.faces);
  }
  final running = _inflight[source];
  if (running != null) return running;

  final future =
      (source == WaveEngineKind.yandex
              ? _yandexFaces(limit)
              : _soundcloudFaces(view, rotation, limit))
          .catchError((_) => const <Track>[])
          .then((faces) {
            // Пустой результат не кэшируем: почти всегда это сеть, а не
            // «показать нечего», — иначе кольцо застряло бы пустым на весь срок.
            if (faces.isNotEmpty) {
              _cache[source] = _Entry(DateTime.now(), faces);
            }
            _inflight.remove(source);
            return faces;
          });
  _inflight[source] = future;
  return future;
}

/// Сбросить кэш — после смены аккаунта Яндекса или по «потянуть-обновить».
void resetWaveFaces() => _cache.clear();

/// Снимок библиотеки для витрины: дизлайкнутое в кольцо не идёт.
WaveLibrary _view(Ref ref) => WaveLibrary(
  lib: ref.read(libraryProvider),
  disliked: ref.read(waveStoreProvider).dislikes.keys.toSet(),
);

/// Обложки кольца выбранной площадки.
///
/// Библиотеку читаем через `ref.read`, а не `watch`: прослушивание меняет
/// историю каждые три минуты, и на `watch` кольцо перезапрашивало бы площадку
/// прямо во время музыки. Свежесть держит срок кэша.
final waveFacesProvider = FutureProvider.family<List<Track>, WaveEngineKind>((
  ref,
  source,
) {
  final store = ref.read(waveStoreProvider.notifier);
  return fetchWaveFaces(
    source,
    view: _view(ref),
    rotation: store.rotation,
    limit: 8,
  );
});

/// Запасные плитки — обложки прямо из библиотеки. Показываются, когда площадка
/// ничего не отдала (нет сети, не вошли в аккаунт).
///
/// Здесь `watch` уместен: запрос никуда не идёт, а свежедобавленный трек должен
/// появиться в кольце сразу.
final waveRingFallbackProvider = Provider<List<Track>>((ref) {
  ref.watch(libraryProvider);
  ref.watch(waveStoreProvider);
  final view = _view(ref);
  final rotation = ref.read(waveStoreProvider.notifier).rotation;
  final out = <Track>[];
  final seen = _Seen();
  for (final id in pickDisplaySeeds(view, rotation, limit: 32)) {
    final track = view.byId(id);
    if (track == null || !seen.add(track)) continue;
    out.add(track);
    if (out.length == 8) break;
  }
  return out;
});

// ── SoundCloud ──────────────────────────────────────────────────────────────

Future<List<Track>> _soundcloudFaces(
  WaveLibrary view,
  int rotation,
  int limit,
) async {
  final seeds = <String>[];
  for (final id in pickDisplaySeeds(view, rotation)) {
    final scId = scIdOf(view.byId(id));
    if (scId != null && !seeds.contains(scId)) seeds.add(scId);
    if (seeds.length == _kScSeeds) break;
  }
  if (seeds.isEmpty) return const [];

  final batches = await Future.wait([for (final s in seeds) waveRelated(s)]);

  // Чередуем сиды по кругу: иначе всё кольцо соберётся из похожих на один трек.
  final out = <Track>[];
  final seen = _Seen();
  final deepest = batches.fold(0, (m, b) => b.length > m ? b.length : m);
  for (var i = 0; i < deepest && out.length < limit; i++) {
    for (final batch in batches) {
      if (i >= batch.length) continue;
      final track = trackFromSc(batch[i]);
      if (!seen.add(track)) continue;
      out.add(track);
      if (out.length >= limit) break;
    }
  }
  return out;
}

/// Отсев повторов для кольца: по id И ПО ОБЛОЖКЕ.
///
/// Одной проверки id мало: у разных треков одного релиза обложка — буквально
/// та же ссылка, и кольцо собиралось из двух-трёх картинок, повторённых по
/// кругу.
class _Seen {
  final Set<String> _ids = {};
  final Set<String> _covers = {};

  bool add(Track track) {
    final cover = track.cover;
    if (cover == null || cover.isEmpty) return false;
    if (!_ids.add(track.id)) return false;
    return _covers.add(cover);
  }
}

// ── Яндекс ──────────────────────────────────────────────────────────────────

Future<List<Track>> _yandexFaces(int limit) async {
  if (ym.activeToken() == null) return const [];
  final batch = await ym.waveTracks(ym.kWaveStation);
  final out = <Track>[];
  final seen = _Seen();
  for (final raw in batch.tracks) {
    final track = trackFromYm(raw);
    if (!seen.add(track)) continue;
    out.add(track);
    if (out.length >= limit) break;
  }
  return out;
}
