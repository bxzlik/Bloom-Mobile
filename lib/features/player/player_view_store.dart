/// Вид плеера — порт настроек из десктопного `settings/model/playerViewStore.ts`.
///
/// Осей три — выравнивание заголовка (`titleAlign`), вид очереди (`queueView`)
/// и плашка «Далее» (`nextUp`, своя); на ПК рядом живут стиль плеера,
/// положение очереди и прочее, чего у нас нет. Хранилище заведено сразу общим (`playerView`), а не ключом
/// на настройку: остальные оси переносятся сюда же, и переезжать потом с
/// одиночного ключа значило бы терять уже выбранное.
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

/// Вид списка очереди — порт десктопного `queueView`.
///
/// [normal] — плоский список, как было. [extended] — тот же список, разбитый
/// на «Прослушано» / «Сейчас играет» / «Далее»; играющий трек в нём закреплён,
/// а перетаскивание не выходит за пределы своей секции.
enum QueueView {
  normal,
  extended;

  bool get isExtended => this == QueueView.extended;
}

final queueViewProvider = NotifierProvider<QueueViewController, QueueView>(
  QueueViewController.new,
);

class QueueViewController extends Notifier<QueueView> {
  @override
  QueueView build() {
    final raw = ref.read(jsonStoreProvider).readMap('playerView');
    // Умолчание десктопное — `normal`; незнакомое значение молча заменяем им
    // же, ровно как у выравнивания заголовка.
    for (final v in QueueView.values) {
      if (v.name == raw['queueView']) return v;
    }
    return QueueView.normal;
  }

  void set(QueueView view) {
    state = view;
    final store = ref.read(jsonStoreProvider);
    store.write('playerView', {
      ...store.readMap('playerView'),
      'queueView': view.name,
    });
  }
}

/// Показывать ли под слайдером плашку «Далее: …» — трек, который заиграет
/// после текущего.
///
/// Десктопной пары у настройки нет: там очередь стоит колонкой рядом с
/// плеером, и следующий трек виден в ней сам. На телефоне очередь — шторка, и
/// узнать, что дальше, можно только открыв её.
final nextUpProvider = NotifierProvider<NextUpController, bool>(
  NextUpController.new,
);

class NextUpController extends Notifier<bool> {
  @override
  bool build() {
    final raw = ref.read(jsonStoreProvider).readMap('playerView')['nextUp'];
    // Умолчание — включено: плашка приехала вместе с настройкой, и выключенной
    // по умолчанию её бы просто никто не увидел.
    return raw is bool ? raw : true;
  }

  void set(bool on) {
    state = on;
    final store = ref.read(jsonStoreProvider);
    store.write('playerView', {...store.readMap('playerView'), 'nextUp': on});
  }
}
