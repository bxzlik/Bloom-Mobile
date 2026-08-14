/// Настройка свайпов: что делает движение пальцем влево и вправо в каждом из
/// четырёх мест — библиотека, очередь, миниплеер, плеер.
///
/// Настройка мобильная целиком: на десктопе жестов нет, брать оттуда нечего.
/// Раскладка экрана и набор действий — по скриншотам, которые прислал
/// пользователь; смысл действий наш, из десктопного контекстного меню трека.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Что делает свайп. Один и тот же список во всех четырёх местах — так же, как
/// в референсе: строка библиотеки тоже умеет «Следующий», а плеер — «Удалить».
enum SwipeAction {
  /// Свайпа нет: строка не двигается, плеер не листается.
  none,

  /// Лайк — переключить «Любимое» у трека.
  like,

  /// Добавить в конец очереди (десктопный `addToQueue`).
  queue,

  /// Поставить сразу после текущего (десктопный `playNextInQueue`).
  playNext,

  /// Следующий трек.
  next,

  /// Предыдущий трек.
  prev,

  /// Скачать — офлайн-копия внутри приложения.
  download,

  /// Удалить: строку — из списка, трек в плеере — из очереди.
  delete,
}

/// Место, где живёт жест.
enum SwipeZone { library, queue, mini, player }

/// Пара действий одного места.
class SwipePair {
  const SwipePair(this.left, this.right);

  /// Движение пальцем ВЛЕВО (строка уезжает влево, плашка вылезает справа).
  final SwipeAction left;

  /// Движение пальцем ВПРАВО.
  final SwipeAction right;

  SwipePair withSide(bool isLeft, SwipeAction action) =>
      isLeft ? SwipePair(action, right) : SwipePair(left, action);
}

/// Умолчания — те, что пользователь показал на скриншотах: в списках свайп
/// влево удаляет, вправо кладёт в очередь; в очереди удаляют оба; плеер и
/// миниплеер листают треки.
const Map<SwipeZone, SwipePair> kDefaultSwipes = {
  SwipeZone.library: SwipePair(SwipeAction.delete, SwipeAction.queue),
  SwipeZone.queue: SwipePair(SwipeAction.delete, SwipeAction.delete),
  SwipeZone.mini: SwipePair(SwipeAction.next, SwipeAction.prev),
  SwipeZone.player: SwipePair(SwipeAction.next, SwipeAction.prev),
};

class SwipeSettings {
  const SwipeSettings({this.zones = kDefaultSwipes});

  final Map<SwipeZone, SwipePair> zones;

  SwipePair of(SwipeZone zone) => zones[zone] ?? kDefaultSwipes[zone]!;

  SwipeSettings withZone(SwipeZone zone, SwipePair pair) =>
      SwipeSettings(zones: {...zones, zone: pair});
}

final swipeProvider = NotifierProvider<SwipeController, SwipeSettings>(
  SwipeController.new,
);

class SwipeController extends Notifier<SwipeSettings> {
  @override
  SwipeSettings build() {
    final raw = ref.read(jsonStoreProvider).readMap('swipes');
    return SwipeSettings(
      zones: {
        for (final zone in SwipeZone.values)
          zone: _pairFromJson(raw[zone.name], kDefaultSwipes[zone]!),
      },
    );
  }

  void setAction(
    SwipeZone zone, {
    required bool isLeft,
    required SwipeAction action,
  }) {
    state = state.withZone(zone, state.of(zone).withSide(isLeft, action));
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write('swipes', {
    for (final zone in SwipeZone.values)
      zone.name: {
        'left': state.of(zone).left.name,
        'right': state.of(zone).right.name,
      },
  });
}

/// Пара из хранилища. Битую или незнакомую запись (правили файл руками, откат
/// на старую сборку) молча заменяем умолчанием — настройка жестов не повод
/// ронять запуск.
SwipePair _pairFromJson(Object? raw, SwipePair fallback) {
  if (raw is! Map) return fallback;
  return SwipePair(
    _actionFromJson(raw['left'], fallback.left),
    _actionFromJson(raw['right'], fallback.right),
  );
}

SwipeAction _actionFromJson(Object? raw, SwipeAction fallback) {
  for (final action in SwipeAction.values) {
    if (action.name == raw) return action;
  }
  return fallback;
}
