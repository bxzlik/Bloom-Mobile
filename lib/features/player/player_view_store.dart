/// Вид плеера — порт настроек из десктопного `settings/model/playerViewStore.ts`.
///
/// Пока в наборе одна ось — выравнивание заголовка (`titleAlign`); на ПК рядом
/// живут стиль плеера, положение очереди и прочее, чего у нас нет. Хранилище
/// заведено сразу общим (`playerView`), а не ключом на настройку: остальные
/// оси переносятся сюда же, и переезжать потом с одиночного ключа значило бы
/// терять уже выбранное.
library;

import 'package:flutter/widgets.dart' show CrossAxisAlignment, TextAlign;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Где в плеере стоит название трека с артистом. Умолчание — по центру, как на
/// ПК (`DEFAULTS.titleAlign`).
enum TitleAlign {
  left,
  center,
  right;

  TextAlign get text => switch (this) {
    TitleAlign.left => TextAlign.left,
    TitleAlign.center => TextAlign.center,
    TitleAlign.right => TextAlign.right,
  };

  /// Как встают сами строки в колонке подписи. Одного [text] мало: строка,
  /// которая влезла, шириной равна тексту — двигать её приходится колонкой.
  CrossAxisAlignment get cross => switch (this) {
    TitleAlign.left => CrossAxisAlignment.start,
    TitleAlign.center => CrossAxisAlignment.center,
    TitleAlign.right => CrossAxisAlignment.end,
  };
}

final titleAlignProvider = NotifierProvider<TitleAlignController, TitleAlign>(
  TitleAlignController.new,
);

class TitleAlignController extends Notifier<TitleAlign> {
  @override
  TitleAlign build() {
    final raw = ref.read(jsonStoreProvider).readMap('playerView');
    // Незнакомое значение (правили файл руками, откат на старую сборку) молча
    // заменяем умолчанием — выравнивание не повод ронять запуск.
    for (final v in TitleAlign.values) {
      if (v.name == raw['titleAlign']) return v;
    }
    return TitleAlign.center;
  }

  void set(TitleAlign align) {
    state = align;
    // Пишем поверх прочитанного, а не голым объектом: когда в `playerView`
    // приедут соседние настройки, они не должны стираться сменой заголовка.
    final store = ref.read(jsonStoreProvider);
    store.write('playerView', {
      ...store.readMap('playerView'),
      'titleAlign': align.name,
    });
  }
}
