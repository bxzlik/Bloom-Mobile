/// С чего волна стартует — `personalSeeds` и `queueSeeds` ПК.
///
/// Чистые функции над снимком библиотеки ([WaveLibrary]): на чём волна
/// строится, целиком решает то, что человек слушал и лайкал, — и проверять это
/// удобнее списком. Прослушивания — свои, из журнала ([PlayStats]).
library;

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import 'wave_engine.dart' show spreadSeeds;
import 'wave_types.dart';

/// Снимок библиотеки, каким его видит подбор.
class WaveLibrary {
  WaveLibrary({
    required this.lib,
    required this.disliked,
    required this.seedOf,
    PlayStats? stats,
    this.recent = const [],
    Iterable<Track> extras = const [],
  }) : stats = stats ?? PlayStats.empty,
       _extras = {for (final t in extras) t.id: t};

  final LibraryState lib;

  /// Журнал прослушиваний целиком.
  final PlayStats stats;

  /// id из «Истории», свежие сверху.
  final List<String> recent;

  /// id дизлайкнутых треков — сидами они не бывают.
  final Set<String> disliked;

  /// Радио трека у его площадки; `null` — радио нет (свой файл, Яндекс без
  /// входа).
  final WaveSeed? Function(Track) seedOf;

  /// Треки вне библиотеки, которые тоже бывают сидами: очередь, страница
  /// артиста.
  final Map<String, Track> _extras;

  /// Треки библиотеки без дизлайкнутых. Порядок — как в «Все треки».
  late final List<Track> tracks = [
    for (final t in lib.allTracks)
      if (!disliked.contains(t.id)) t,
  ];

  int playCount(String trackId) => stats.playCount(trackId);

  Track? byId(String trackId) => _extras[trackId] ?? lib.tracks[trackId];
}

/// Сиды из списка (очередь, треки артиста): по одному на радио, без
/// дизлайкнутых, поровну по списку ([spreadSeeds]).
List<WaveSeed> queueSeeds(List<Track> tracks, WaveLibrary view) {
  final all = <WaveSeed>[];
  final seen = <WaveSeed>{};
  for (final t in tracks) {
    if (view.disliked.contains(t.id)) continue;
    final s = view.seedOf(t);
    if (s != null && seen.add(s)) all.add(s);
  }
  return spreadSeeds(all);
}

/// «Моя волна» с площадки [provider] (код базы): два самых слушаемых, два
/// самых свежих лайка и ещё один из них же. [rotation] сдвигает выбор на
/// каждой новой волне — иначе она вечно стояла бы на тех же двух из топа.
List<WaveSeed> personalSeeds(
  WaveLibrary view,
  String provider,
  int rotation,
) {
  bool usable(Track t) =>
      t.source.code == provider &&
      !view.disliked.contains(t.id) &&
      view.seedOf(t) != null;
  final lib = [
    for (final t in view.lib.allTracks)
      if (usable(t)) t,
  ];
  if (lib.isEmpty) return const [];

  final byPlays = _byPlays(view, lib);
  final favs = [
    for (final t in _newest(view.lib.favTracks, view.lib.favs))
      if (usable(t)) t,
  ];

  final picked = <Track>[];
  bool take(List<Track> from, int i) {
    if (from.isEmpty) return false;
    final t = from[i % from.length];
    if (picked.any((x) => x.id == t.id)) return false;
    picked.add(t);
    return true;
  }

  take(byPlays, rotation * 2);
  take(byPlays, rotation * 2 + 1);
  take(favs, rotation * 2);
  take(favs, rotation * 2 + 1);
  if (!take(byPlays, rotation * 2 + 2)) take(favs, rotation * 2 + 2);
  // Ничего не слушали и не лайкали: самое свежее в библиотеке.
  if (picked.isEmpty) picked.addAll(_newest(lib, view.lib.inLib).take(3));
  return [for (final t in picked) ?view.seedOf(t)];
}

/// Кольцо «Моей волны» на главной: из чего брать обложки. Те же источники в
/// том же порядке, но БЕЗ сдвига ротации — отрисовка главной не должна
/// прокручивать сиды настоящей волны. С запасом: у части не будет обложки.
List<String> pickDisplaySeeds(
  WaveLibrary view,
  int rotation, {
  int limit = 24,
}) {
  final lib = view.tracks;
  if (lib.isEmpty) return const [];

  final out = <String>[];
  final seen = <String>{};
  void push(String? id) {
    if (id == null || out.length >= limit) return;
    if (seen.add(id)) out.add(id);
  }

  final byPlays = _byPlays(view, lib);
  final favs = [
    for (final t in _newest(view.lib.favTracks, view.lib.favs))
      if (!view.disliked.contains(t.id)) t,
  ];
  for (final t in _rotate(byPlays, rotation * 2).take(4)) {
    push(t.id);
  }
  for (final t in _rotate(favs, rotation * 2).take(4)) {
    push(t.id);
  }
  // Добивка: остаток топа → остаток лайков → недавнее → свежее в библиотеке.
  for (final t in byPlays) {
    push(t.id);
  }
  for (final t in favs) {
    push(t.id);
  }
  for (final id in view.recent) {
    if (view.disliked.contains(id)) continue;
    push(id);
  }
  for (final t in lib) {
    push(t.id);
  }
  return out;
}

/// Слушанные, самые слушаемые сверху (порядок при равенстве — как пришли).
List<Track> _byPlays(WaveLibrary view, List<Track> lib) {
  final scored = [
    for (var i = 0; i < lib.length; i++)
      if (view.playCount(lib[i].id) case final n when n > 0) (lib[i], n, i),
  ]..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
  return [for (final x in scored) x.$1];
}

/// Свежие сверху по времени добавления [at] — `Taste::newestIn` ПК.
List<Track> _newest(List<Track> list, Map<String, int> at) {
  final rows = [for (var i = 0; i < list.length; i++) (list[i], i)]
    ..sort((a, b) {
      final c = (at[b.$1.id] ?? 0).compareTo(at[a.$1.id] ?? 0);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
  return [for (final x in rows) x.$1];
}

/// Список, прокрученный на [by] позиций.
List<T> _rotate<T>(List<T> items, int by) {
  if (items.length < 2) return items;
  final k = by % items.length;
  return [...items.skip(k), ...items.take(k)];
}
