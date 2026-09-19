/// Режимы плеера в снимке «Продолжить».
///
/// Очередь записывается уже перемешанной, поэтому без сохранённого флага она
/// возвращалась тасованной, а значок перемешки — погасшим: плеер вёл себя не
/// так, как показывал. Проверяем обе стороны — запись и чтение, — и отдельно
/// снимки старого формата, где полей ещё нет.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/resume_store.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'a',
  duration: Duration.zero,
  source: MusicSource.soundcloud,
);

ResumeData _capture({
  bool shuffle = false,
  bool smartShuffle = false,
  PlayerRepeat repeat = PlayerRepeat.off,
}) => ResumeData.capture(
  queue: [_track('t1'), _track('t2')],
  index: 0,
  position: const Duration(seconds: 30),
  paused: true,
  shuffle: shuffle,
  smartShuffle: smartShuffle,
  repeat: repeat,
);

void main() {
  test('перемешка и повтор переживают запись снимка', () {
    final back = ResumeData.fromJson(
      _capture(
        shuffle: true,
        smartShuffle: true,
        repeat: PlayerRepeat.one,
      ).toJson(),
    )!;
    expect(back.shuffle, isTrue);
    expect(back.smartShuffle, isTrue);
    expect(back.repeat, PlayerRepeat.one);
  });

  test('умная перемешка без обычной не оживает', () {
    // Подвид без своего родителя не живёт — то же правило, что в `copyWith`.
    final back = ResumeData.fromJson({
      ..._capture().toJson(),
      'smartShuffle': true,
    })!;
    expect(back.shuffle, isFalse);
    expect(back.smartShuffle, isFalse);
  });

  test('снимок старого формата поднимается с режимами по умолчанию', () {
    final raw = _capture(shuffle: true, repeat: PlayerRepeat.all).toJson()
      ..remove('shuffle')
      ..remove('repeat');
    final back = ResumeData.fromJson(raw)!;
    expect(back.shuffle, isFalse);
    expect(back.repeat, PlayerRepeat.off);
  });

  test('режимы не теряются при очистке очереди и на «Продолжить»', () {
    // Оба пересобирают снимок вручную — поля легко не дописать.
    final data = _capture(shuffle: true, repeat: PlayerRepeat.all);
    final cleared = data.markedCleared([_track('t1'), _track('t2')]);
    expect(cleared.shuffle, isTrue);
    expect(cleared.repeat, PlayerRepeat.all);
    final forContinue = cleared.forContinue();
    expect(forContinue.shuffle, isTrue);
    expect(forContinue.repeat, PlayerRepeat.all);
  });
}
