/// Merging playlists: the join order and collapsing repeats.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/library/merge.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  artist: 'Artist',
  duration: const Duration(seconds: 200),
  source: MusicSource.soundcloud,
);

List<Track> _list(List<String> ids) => [for (final id in ids) _track(id)];

void main() {
  test('the source playlist comes first, the others in the picked order', () {
    final merged = mergeTracks([
      _list(['a', 'b']),
      _list(['c']),
      _list(['d']),
    ], dedup: true);

    expect(merged.map((t) => t.id), ['a', 'b', 'c', 'd']);
  });

  test('a repeat stays at its first place', () {
    final merged = mergeTracks([
      _list(['a', 'b']),
      _list(['b', 'c']),
    ], dedup: true);

    expect(merged.map((t) => t.id), ['a', 'b', 'c']);
  });

  test('one id has one place, with the choice on or off', () {
    for (final dedup in [true, false]) {
      final merged = mergeTracks([
        _list(['a']),
        _list(['a']),
      ], dedup: dedup);

      expect(merged.map((t) => t.id), ['a'], reason: 'dedup: $dedup');
    }
  });

  group('one song in several entries', () {
    Track song(String id, {String? cover}) => Track(
      id: id,
      name: 'Night  ',
      artist: 'ONE',
      duration: const Duration(seconds: 200),
      source: MusicSource.soundcloud,
      cover: cover,
    );
    final lists = [
      [song('sc:1'), _track('b')],
      [song('ym:1'), _track('c')],
    ];

    test('the choice decides: both copies, or one in the first place', () {
      expect(mergeTracks(lists, dedup: false).map((t) => t.id), [
        'sc:1',
        'b',
        'ym:1',
        'c',
      ]);
      expect(mergeTracks(lists, dedup: true).map((t) => t.id), [
        'sc:1',
        'b',
        'c',
      ]);
      expect(mergeDupCount(lists), 1);
    });

    test('the copy with a cover wins, then the most played', () {
      final withCover = mergeTracks([
        [song('sc:1')],
        [song('ym:1', cover: 'x')],
      ], dedup: true);
      expect(withCover.single.id, 'ym:1');

      final played = mergeTracks(
        lists,
        dedup: true,
        plays: (id) => id == 'ym:1' ? 3 : 1,
      );
      expect(played.map((t) => t.id), ['ym:1', 'b', 'c']);

      final kept = mergeTracks(
        [
          [song('sc:1', cover: 'x')],
          [song('ym:1')],
        ],
        dedup: true,
        plays: (id) => id == 'ym:1' ? 9 : 0,
      );
      expect(kept.single.id, 'sc:1');
    });
  });

  test('empty lists break nothing', () {
    expect(mergeTracks([], dedup: true), isEmpty);
    expect(mergeDupCount([]), 0);
  });
}
