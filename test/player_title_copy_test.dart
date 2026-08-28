/// Что кладёт в буфер тап по названию в полноэкранном плеере (порт
/// `TitleCopyOnClick` с ПК).
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/player/ui/full_player.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track({required String name, required String artist}) => Track(
  id: 'sc_1',
  name: name,
  artist: artist,
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

void main() {
  test('название и артист через тире', () {
    expect(
      trackCopyText(_track(name: 'Runaway', artist: 'Kanye West')),
      'Runaway — Kanye West',
    );
  });

  test('несколько артистов идут строкой как есть', () {
    expect(
      trackCopyText(_track(name: 'Песня', artist: 'Kanye West & Ty Dolla')),
      'Песня — Kanye West & Ty Dolla',
    );
  });

  test('артиста нет — одно название, без висящего тире', () {
    expect(trackCopyText(_track(name: 'Песня', artist: '   ')), 'Песня');
  });
}
