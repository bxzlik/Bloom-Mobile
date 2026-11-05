/// Merge with: builds one new playlist from several. The source goes first,
/// then the picked ones in pick order. Sources don't change: the result is ALWAYS
/// a new playlist, and deleting them is a separate checkbox.
library;

import '../../core/entities/entities.dart';
import 'dups.dart';

/// The new playlist's contents. A list holds a track once, so the same id
/// collapses always. What the choice is about is one song in several entries, say
/// from two platforms, known by [dupKey]: with [dedup] it keeps its first place,
/// and the better copy takes it: one with a cover, then the most played.
List<Track> mergeTracks(
  List<List<Track>> lists, {
  required bool dedup,
  int Function(String id)? plays,
}) {
  final out = <Track>[];
  final seen = <String>{};
  final kept = <String, int>{};
  for (final list in lists) {
    for (final track in list) {
      if (!seen.add(track.id)) continue;
      final key = dupKey(track);
      final at = kept[key];
      if (at == null) {
        kept[key] = out.length;
        out.add(track);
      } else if (!dedup) {
        out.add(track);
      } else if (_better(track, out[at], plays)) {
        out[at] = track;
      }
    }
  }
  return out;
}

bool _better(Track copy, Track kept, int Function(String id)? plays) {
  final hasCover = (copy.cover ?? '').isNotEmpty;
  if (hasCover != (kept.cover ?? '').isNotEmpty) return hasCover;
  return (plays?.call(copy.id) ?? 0) > (plays?.call(kept.id) ?? 0);
}

/// How many extra copies of a song the merge has, for the sheet's count line.
int mergeDupCount(List<List<Track>> lists) =>
    mergeTracks(lists, dedup: false).length -
    mergeTracks(lists, dedup: true).length;
