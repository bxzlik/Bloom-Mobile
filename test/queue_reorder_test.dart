/// Перенос строк в очереди: номер играющего трека обязан ехать вместе с ним.
///
/// Проверяем не на глаз, а сверкой со списком: перекладываем настоящий список
/// и смотрим, что по посчитанному номеру лежит тот же элемент, что и был.
library;

import 'package:bloom/features/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Что осталось под номером [indexAfterReorder] после переноса.
String _after(List<String> queue, int current, int from, int target) {
  final q = [...queue];
  q.insert(target, q.removeAt(from));
  return q[indexAfterReorder(current, from, target)];
}

void main() {
  const queue = ['a', 'b', 'c', 'd', 'e'];

  test('перетащили сам играющий трек — номер идёт за ним', () {
    expect(indexAfterReorder(2, 2, 0), 0);
    expect(_after(queue, 2, 2, 0), 'c');
    expect(_after(queue, 2, 2, 4), 'c');
  });

  test('строку перенесли сверху вниз через играющий — он поднялся', () {
    expect(indexAfterReorder(2, 0, 4), 1);
    expect(_after(queue, 2, 0, 4), 'c');
  });

  test('строку перенесли снизу вверх через играющий — он опустился', () {
    expect(indexAfterReorder(2, 4, 0), 3);
    expect(_after(queue, 2, 4, 0), 'c');
  });

  test('перенос по одну сторону от играющего его не трогает', () {
    expect(indexAfterReorder(4, 0, 2), 4);
    expect(_after(queue, 4, 0, 2), 'e');
    expect(indexAfterReorder(0, 3, 1), 0);
    expect(_after(queue, 0, 3, 1), 'a');
  });

  test('пустой плеер: играющего нет — номер остаётся -1', () {
    expect(indexAfterReorder(-1, 1, 3), -1);
  });
}
