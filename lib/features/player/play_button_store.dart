/// Вид кнопки воспроизведения. Настройка наша, десктопной пары у неё нет: на ПК
/// транспорт живёт в узкой полосе и круг там единственный вариант, а на телефоне
/// кнопка — самый крупный элемент плеера, и её форма видна первой.
///
/// Настройка ОДНА на обе поверхности (плеер и карточка над таб-баром): кнопка в
/// них одна и та же по смыслу, и разъехавшийся вид читался бы как недоделка, а
/// не как выбор.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

enum PlayButtonShape {
  /// Круг с заливкой акцентом — то, что было до настройки.
  circle,

  /// Та же заливка, но скруглённым квадратом.
  square,

  /// Заливки нет вовсе: один знак, цветом соседних кнопок и крупнее их.
  plain;

  bool get isPlain => this == PlayButtonShape.plain;
}

final playButtonShapeProvider =
    NotifierProvider<PlayButtonShapeController, PlayButtonShape>(
      PlayButtonShapeController.new,
    );

class PlayButtonShapeController extends Notifier<PlayButtonShape> {
  @override
  PlayButtonShape build() {
    final raw = ref.read(jsonStoreProvider).read('playButtonShape');
    for (final shape in PlayButtonShape.values) {
      if (shape.name == raw) return shape;
    }
    // Незнакомую запись (правили файл руками, откат на старую сборку) молча
    // заменяем умолчанием: форма кнопки не повод ронять запуск.
    return PlayButtonShape.circle;
  }

  void set(PlayButtonShape shape) {
    if (shape == state) return;
    state = shape;
    ref.read(jsonStoreProvider).write('playButtonShape', shape.name);
  }
}
