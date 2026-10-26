/// «Лица волны» — обложки для кольца на главной.
///
/// Это НЕ библиотека: в кольце стоит то, что реально зазвучало бы в волне
/// ВЫБРАННОЙ площадки, поэтому выбор площадки меняет и кольцо:
///   • SoundCloud, YouTube Music — радио нескольких личных сидов (то же, из
///     чего волна собирает пачку);
///   • Яндекс — порция станции `user:onyourwave` (та же станция, что и «Моя
///     волна»).
///
/// Витрина НЕ трогает состояние настоящей волны: ни курсоров станций, ни
/// пометок «показано», ни отзывов станции — только первые порции радио.
///
/// Плитка несёт сам [Track], а не id с обложкой: по одному id волну потом было
/// бы не с чего запустить.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/store/history_store.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import '../../providers/yandex/models.dart' show YmRawTrack;
import '../../providers/yandex/ym_provider.dart' show trackFromYm;
import '../../providers/yandex/yandex.dart' as ym;
import 'wave_controller.dart';
import 'wave_seeds.dart';
import 'wave_store.dart';
import 'wave_types.dart';

/// Сколько личных сидов раскрываем через радио. Каждый — отдельный запрос.
const int _kSeeds = 3;

const Duration _ttl = Duration(minutes: 20);

class _Entry {
  _Entry(this.at, this.faces);
  final DateTime at;
  final List<Track> faces;
}

final Map<MusicSource, _Entry> _cache = {};
final Map<MusicSource, Future<List<Track>>> _inflight = {};

/// Сбросить кэш — после смены аккаунта Яндекса или выбора площадки.
void resetWaveFaces() => _cache.clear();

/// Снимок библиотеки для витрины: дизлайкнутое в кольцо не идёт.
WaveLibrary _view(Ref ref) => WaveLibrary(
  lib: ref.read(libraryProvider),
  disliked: ref.read(waveStoreProvider).dislikedIds,
  stats: ref.read(playStatsProvider),
  recent: [for (final row in ref.read(historyRowsProvider)) row.id],
  seedOf: ref.read(waveProvider.notifier).seedOf,
);

/// Обложки кольца площадки. Пустой список — получить не вышло (нет сети, не
/// вошли в аккаунт, у сидов нет радио): интерфейс покажет запасные.
///
/// Библиотеку читаем через `ref.read`, а не `watch`: прослушивание меняет
/// историю каждые три минуты, и на `watch` кольцо перезапрашивало бы площадку
/// прямо во время музыки. Свежесть держит срок кэша.
final waveFacesProvider = FutureProvider.family<List<Track>, MusicSource>((
  ref,
  source,
) {
  final hit = _cache[source];
  if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
    return Future.value(hit.faces);
  }
  final running = _inflight[source];
  if (running != null) return running;

  final rotation = ref.read(waveStoreProvider.notifier).rotation;
  final future =
      (source == MusicSource.yandex
              ? _yandexFaces(8)
              : _radioFaces(ref, source, rotation, 8))
          .catchError((_) => const <Track>[])
          .then((faces) {
            // Пустоту не кэшируем: почти всегда это сеть, а не «показать
            // нечего», — иначе кольцо застряло бы пустым на весь срок.
            if (faces.isNotEmpty) {
              _cache[source] = _Entry(DateTime.now(), faces);
            }
            _inflight.remove(source);
            return faces;
          });
  _inflight[source] = future;
  return future;
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

// ── SoundCloud, YouTube Music ───────────────────────────────────────────────

Future<List<Track>> _radioFaces(
  Ref ref,
  MusicSource source,
  int rotation,
  int limit,
) async {
  final provider = ref.read(registryProvider).byId(source.id);
  if (provider == null) return const [];
  final view = _view(ref);
  final seeds = <WaveSeed>[];
  for (final id in pickDisplaySeeds(view, rotation)) {
    final t = view.byId(id);
    if (t == null || t.source != source) continue;
    final s = view.seedOf(t);
    if (s != null && !seeds.contains(s)) seeds.add(s);
    if (seeds.length == _kSeeds) break;
  }
  if (seeds.isEmpty) return const [];

  final pages = await Future.wait([
    for (final s in seeds) provider.station(s.station, ''),
  ]);

  // Сиды по кругу: иначе всё кольцо собралось бы из похожих на один трек.
  final out = <Track>[];
  final seen = _Seen();
  final deepest = pages.fold(
    0,
    (m, p) => p.tracks.length > m ? p.tracks.length : m,
  );
  for (var i = 0; i < deepest && out.length < limit; i++) {
    for (final page in pages) {
      if (i >= page.tracks.length) continue;
      final track = page.tracks[i];
      if (view.disliked.contains(track.id) || !seen.add(track)) continue;
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

/// Потолок порций на одно кольцо. Rotor отдаёт ~5 треков за раз, а после
/// отсева по обложке (у треков одного релиза она общая) на плитки остаётся и
/// того меньше. Цепочку продолжаем `queue=<последний id>` — тот же GET, что у
/// волны, только мимо провайдера: batch-id и отзывы остаются настоящей волне.
const int _kYmBatches = 4;

Future<List<Track>> _yandexFaces(int limit) async {
  if (ym.activeToken() == null) return const [];
  final out = <Track>[];
  final seen = _Seen();
  var lastId = '';
  for (var b = 0; b < _kYmBatches && out.length < limit; b++) {
    // Упавший дозапрос не роняет уже собранное: кольцо добьётся библиотекой.
    final List<YmRawTrack> raws;
    try {
      raws = (await ym.waveTracks(ym.kWaveStation, lastId: lastId)).tracks;
    } catch (_) {
      break;
    }
    if (raws.isEmpty) break;
    final before = out.length;
    for (final raw in raws) {
      final track = trackFromYm(raw);
      if (!seen.add(track)) continue;
      out.add(track);
      if (out.length >= limit) break;
    }
    // Станция пошла по кругу — дальше будут те же треки.
    if (out.length == before) break;
    lastId = raws.last.id;
  }
  return out;
}
