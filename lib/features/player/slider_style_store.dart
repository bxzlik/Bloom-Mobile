/// Тип слайдера прогресса — порт `sliderType` из десктопного
/// `settings/model/playerViewStore.ts`. Рисовку там задаёт
/// `shared/styles/sliders-telemetry.css` (`body.slider-thin/-ios/-wave`), узор
/// волны считает `features/player/lib/waveSlider.ts`.
///
/// Пятого десктопного типа — `cover` — здесь нет: на ПК он только красит
/// заливку акцентом, а само фото пуговки на телефоне живёт отдельной настройкой
/// в «Кастомизации» (`CustomCtx.slider`) и показывается при любом типе, кроме
/// волны, — ровно как на ПК.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Вид полосы прогресса в полноэкранном плеере.
enum SliderStyle {
  /// Дорожка 5 px без пуговки — то, что было до настройки.
  standard,

  /// Волосяная дорожка с круглой пуговкой.
  thin,

  /// Два капсульных сегмента с прозрачным зазором и вертикальной каплей.
  ios,

  /// Столбики-волна вместо дорожки.
  wave,
}

final sliderStyleProvider =
    NotifierProvider<SliderStyleController, SliderStyle>(
      SliderStyleController.new,
    );

class SliderStyleController extends Notifier<SliderStyle> {
  @override
  SliderStyle build() {
    final raw = ref.read(jsonStoreProvider).read('sliderStyle');
    for (final style in SliderStyle.values) {
      if (style.name == raw) return style;
    }
    // Незнакомую запись (правили файл руками, откат на старую сборку) молча
    // заменяем умолчанием: вид слайдера не повод ронять запуск.
    return SliderStyle.standard;
  }

  void set(SliderStyle style) {
    state = style;
    ref.read(jsonStoreProvider).write('sliderStyle', style.name);
  }
}
