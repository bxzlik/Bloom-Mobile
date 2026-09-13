/// Перемешивание переставляет саму очередь, а не подкидывает случайный номер
/// на переходе, — значит проверять надо состав и голову списка.
///
/// Случайность в тесте фиксируем: `Random(seed)` даёт тот же порядок, и падение
/// теста будет означать сломанную логику, а не невезение.
library;

import 'dart:math';

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'a',
  duration: Duration.zero,
  source: MusicSource.soundcloud,
);

List<String> _ids(List<Track> tracks) => [for (final t in tracks) t.id];

void main() {
  final queue = [
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) _track(id),
  ];

  test('играющий трек встаёт первым, состав не меняется', () {
    final out = shuffledQueue(queue, 3, Random(7));
    expect(out.first.id, 'd');
    expect(out.length, queue.length);
    expect(_ids(out).toSet(), _ids(queue).toSet());
  });

  test('без играющего мешаются все — порядок не исходный', () {
    final out = shuffledQueue(queue, -1, Random(7));
    expect(_ids(out).toSet(), _ids(queue).toSet());
    expect(_ids(out), isNot(_ids(queue)));
  });

  test('номер вне очереди — как будто играющего нет', () {
    final out = shuffledQueue(queue, 99, Random(1));
    expect(_ids(out).toSet(), _ids(queue).toSet());
  });

  test('очередь из одного трека переживает перемешку', () {
    expect(_ids(shuffledQueue([_track('a')], 0, Random(1))), ['a']);
    expect(shuffledQueue(const [], -1, Random(1)), isEmpty);
  });

  test('перемешка правда мешает: два разных зерна дают разный порядок', () {
    final long = [for (var i = 0; i < 30; i++) _track('t$i')];
    final a = _ids(shuffledQueue(long, 0, Random(1)));
    final b = _ids(shuffledQueue(long, 0, Random(2)));
    expect(a, isNot(b));
    expect(a.first, 't0'); // но голова на месте в обоих
    expect(b.first, 't0');
  });

  group('умная перемешка', () {
    test('играющий первым, состав не меняется', () {
      final out = weightedShuffledQueue(queue, 2, (_) => 1, Random(3));
      expect(out.first.id, 'c');
      expect(_ids(out).toSet(), _ids(queue).toSet());
      expect(out.length, queue.length);
    });

    test('тяжёлые треки в среднем встают в начало', () {
      // 40 «горячих» из 400 — расклад из комментария на ПК: ~9 из 10 первых.
      final long = [for (var i = 0; i < 400; i++) _track('t$i')];
      final rnd = Random(11);
      var hot = 0;
      for (var run = 0; run < 50; run++) {
        final out = weightedShuffledQueue(
          long,
          -1,
          (t) => int.parse(t.id.substring(1)) < 40 ? 70.5 : 0.5,
          rnd,
        );
        hot += out
            .take(10)
            .where((t) => int.parse(t.id.substring(1)) < 40)
            .length;
      }
      expect(hot / 500, greaterThan(0.8));
    });

    test('вес без истории — база 0.5, нулевой вес не ломает тасовку', () {
      expect(smartShuffleWeight(PlayStats.empty, 'x'), 0.5);
      final out = weightedShuffledQueue(queue, -1, (_) => 0, Random(1));
      expect(_ids(out).toSet(), _ids(queue).toSet());
    });
  });
}
