/// С чего волна стартует — `personalSeeds` и `queueSeeds` ПК.
///
/// Чистые функции над снимком библиотеки ([WaveLibrary]): на чём волна
/// строится, целиком решает то, что человек слушал и лайкал, — и проверять это
/// удобнее списком. Прослушивания — свои, из журнала ([PlayStats]).
library;

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import '../../shared/util/taste.dart';
import 'wave_engine.dart' show spreadSeeds;
import 'wave_types.dart';

/// Снимок библиотеки, каким его видит подбор.
class WaveLibrary {
  WaveLibrary({
    required this.lib,
    required this.disliked,
    required this.seedOf,
    PlayStats? stats,
    Iterable<Track> extras = const [],
  }) : stats = stats ?? PlayStats.empty,
       _extras = {for (final t in extras) t.id: t};

  final LibraryState lib;

  /// Журнал прослушиваний целиком.
  final PlayStats stats;

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
List<WaveSeed> personalSeeds(WaveLibrary view, String provider, int rotation) {
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
    for (final t in newestFirst(view.lib.favTracks, view.lib.favs))
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
  if (picked.isEmpty) picked.addAll(newestFirst(lib, view.lib.inLib).take(3));
  return [for (final t in picked) ?view.seedOf(t)];
}

/// Слушанные, самые слушаемые сверху (порядок при равенстве — как пришли).
List<Track> _byPlays(WaveLibrary view, List<Track> lib) {
  final scored = [
    for (var i = 0; i < lib.length; i++)
      if (view.playCount(lib[i].id) case final n when n > 0) (lib[i], n, i),
  ]..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
  return [for (final x in scored) x.$1];
}

/// What a wave started from an artist or a track is about: the pick that
/// started the wave on now is lit by it.
String waveAboutArtist(String name) => 'artist:${artistKey(name)}';
String waveAboutTrack(String trackId) => 'track:$trackId';

enum WaveOptionKind { artist, track, back, shake }

/// A wave to turn to from My Wave's stage.
class WaveOption {
  const WaveOption.artist(this.name, Track this.track)
    : kind = WaveOptionKind.artist;
  const WaveOption.track(Track this.track)
    : kind = WaveOptionKind.track,
      name = '';
  const WaveOption.action(this.kind) : name = '', track = null;

  final WaveOptionKind kind;
  final String name;

  /// The track's own for a track; for an artist, their own track (the
  /// platform to look them up on, the picture while there's no avatar).
  final Track? track;

  String get about => switch (kind) {
    WaveOptionKind.artist => waveAboutArtist(name),
    WaveOptionKind.track => waveAboutTrack(track!.id),
    _ => '',
  };
}

/// Waves to turn to, artist and track by turns, as `Wave::picks` on the PC:
/// the top artists, and tracks of others (two fresh likes, then the top). An
/// artist's own hit beside their name would say the same twice.
List<WaveOption> wavePicks(RecsInput input, {int each = 4}) {
  final artists = topArtists(input, each);
  final listed = {for (final a in artists) a.key};

  final tracks = <Track>[];
  final taken = <String>{};
  void take(Iterable<Track> from, int upTo) {
    for (final t in from) {
      if (tracks.length >= upTo) return;
      if (taken.contains(t.id) ||
          input.disliked.contains(t.id) ||
          !recsAskable(input, t) ||
          artistKeys(t).any(listed.contains)) {
        continue;
      }
      taken.add(t.id);
      tracks.add(t);
    }
  }

  take(newestFirst(input.lib.favTracks, input.lib.favs), 2);
  take([
    for (final r in recsTopPlayed(input, limit: 50)) ?input.trackOf(r.id),
  ], each);

  return [
    for (var i = 0; i < each; i++) ...[
      if (i < artists.length)
        WaveOption.artist(artists[i].name, artists[i].own),
      if (i < tracks.length) WaveOption.track(tracks[i]),
    ],
  ];
}
