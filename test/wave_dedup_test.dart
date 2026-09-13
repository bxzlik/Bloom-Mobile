/// Отсев перезаливов SoundCloud в «Моей волне»: один трек, залитый разными
/// загрузчиками, не должен вставать в очередь дважды — ни внутри пачки, ни
/// поверх того, что уже пришло прошлой пачкой.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/wave/wave_engine.dart';
import 'package:bloom/features/wave/wave_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String id, String name, String artist, {int seconds = 200}) => Track(
  id: id,
  name: name,
  artist: artist,
  duration: Duration(seconds: seconds),
  source: MusicSource.soundcloud,
);

void main() {
  test('перезалив внутри пачки выпадает, остаётся тот, что выше рангом', () {
    final batch = [
      candidateFromLibrary(_t('sc_1', 'целоваться', 'lightprey'), 0),
      candidateFromLibrary(_t('sc_2', 'Другая песня', 'Кто-то'), 1),
      // Тот же трек: автор уехал в заголовок, загрузчик чужой.
      candidateFromLibrary(_t('sc_3', 'lightprey - целоваться', 'クリソライト'), 2),
    ];

    final out = dedupCandidates(batch);
    expect(out.map((c) => c.track.id), ['sc_1', 'sc_2']);
  });

  test('трек, уже стоящий в очереди, выпадает и под другим id', () {
    final queue = [_t('sc_10', 'Ночь', 'Artist')];
    final batch = [
      candidateFromLibrary(_t('sc_11', 'Artist - Ночь', 'reupload'), 0),
      candidateFromLibrary(_t('sc_12', 'День', 'Artist', seconds: 240), 1),
    ];

    final out = dedupCandidates(batch, already: queue);
    expect(out.map((c) => c.track.id), ['sc_12']);
  });

  test('разные треки одного артиста проходят, порядок сохраняется', () {
    final batch = [
      for (final (i, name) in ['Первая', 'Вторая', 'Третья'].indexed)
        candidateFromLibrary(_t('sc_$i', name, 'Artist', seconds: 180 + i), i),
    ];
    expect(dedupCandidates(batch).map((c) => c.track.id), [
      'sc_0',
      'sc_1',
      'sc_2',
    ]);
  });
}
