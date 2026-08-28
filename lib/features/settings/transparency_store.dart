/// Прозрачность / стекло для блоков интерфейса — порт десктопного
/// `settings/model/transparencyStore.ts` + `shared/styles/transparency.css`.
///
/// На ПК стор ставит на `:root` две переменные (`--glass-block-bg` — цвет блока
/// с альфой `blockOpacity`, `--glass-filter` — `blur() brightness()`), а класс
/// `glass-mode` раздаёт их внешним контейнерам. Здесь тех же двух величин
/// хватает: [GlassSpec] отдаёт альфу заливки и готовый `ImageFilter`, а
/// раздаёт их `shared/ui/glass.dart` (`GlassBox`).
///
/// Отличия от ПК, все вынужденные:
/// * **Нативной прозрачности окна нет.** `nativeTransparent` делает прозрачным
///   само окно Tauri (`transparent: true`), чтобы сквозь зазоры был виден
///   рабочий стол. У телефона под приложением стола нет — настройку не
///   переносили.
/// * **Деления outer/inner нет.** На ПК стекло получают КОНТЕЙНЕРЫ
///   (`.sidebar`/`.main`/панели), а блоки внутри становятся прозрачными и
///   просвечивают родительское стекло. На телефоне таких контейнеров нет
///   вовсе: карточки лежат прямо на фоне приложения, поэтому стекло — у каждой
///   своё. Чтобы это не превратилось в десятки `saveLayer`, все `GlassBox`
///   живут в одном `BackdropGroup` (`BackdropFilter.grouped`): движок считает
///   размытие один раз на группу.
/// * **Умолчание `blockOpacity` — 60, а не 100.** На ПК включённая
///   прозрачность со стопроцентной заливкой не меняет вид вообще, и понять,
///   что настройка сработала, нельзя.
///
/// Тумблер оверлеев — подрежим основного, ровно как на ПК: при выключенной
/// прозрачности стекла нет нигде ([Transparency.overlaysOn]).
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Границы ползунков. Те же, что на ПК: проценты 0–100, размытие 0–40 px.
const int kTrBlurMax = 40;

/// Умолчания. `blockOpacity` — наш (см. шапку), остальные десктопные.
const int kTrOpacityDefault = 60;
const int kTrBrightnessDefault = 50;
const int kTrBlurDefault = 12;

@immutable
class Transparency {
  const Transparency({
    this.on = false,
    this.overlayGlass = false,
    this.blockOpacity = kTrOpacityDefault,
    this.glassStr = kTrBrightnessDefault,
    this.glassBlur = kTrBlurDefault,
  });

  /// Режим: выключено — обычные непрозрачные блоки, включено — стекло.
  final bool on;

  /// Стекло на всплывающих поверхностях: шторки, меню, диалоги и затемнение
  /// под ними. Подрежим основного — см. [overlaysOn].
  final bool overlayGlass;

  /// НЕПРОЗРАЧНОСТЬ блоков, 0–100 (доля заливки поверх фона).
  ///
  /// Внимание: в интерфейсе это «Уровень прозрачности» и показывается
  /// перевёрнутым ([transparencyPercent]) — пользователь крутит «насколько
  /// видно фон», а не «насколько плотна заливка». Хранение осталось
  /// десктопным, чтобы формула заливки читалась так же, как в `transparency.css`.
  final int blockOpacity;

  /// Яркость стекла, 0–100 (50 — нейтрально).
  final int glassStr;

  /// Размытие стекла, 0–[kTrBlurMax].
  final int glassBlur;

  /// «Уровень прозрачности» — то, что видно в настройках.
  int get transparencyPercent => 100 - blockOpacity;

  /// Множитель яркости: 0 → 0.4 (тёмное стекло), 50 → 1.0, 100 → 1.8.
  /// Формула из `applyTransparency` слово в слово.
  double get brightness => glassStr < 50
      ? 0.4 + (glassStr / 50) * 0.6
      : 1 + ((glassStr - 50) / 50) * 0.8;

  double get opacity => blockOpacity / 100;

  /// Стекло оверлеев включено. Оба тумблера разом — на ПК `overlayGlass`
  /// действует только при `trMode === 'on'`.
  bool get overlaysOn => on && overlayGlass;

  Transparency copyWith({
    bool? on,
    bool? overlayGlass,
    int? blockOpacity,
    int? glassStr,
    int? glassBlur,
  }) => Transparency(
    on: on ?? this.on,
    overlayGlass: overlayGlass ?? this.overlayGlass,
    blockOpacity: blockOpacity ?? this.blockOpacity,
    glassStr: glassStr ?? this.glassStr,
    glassBlur: glassBlur ?? this.glassBlur,
  );

  Map<String, dynamic> toJson() => {
    'on': on,
    'overlayGlass': overlayGlass,
    'blockOpacity': blockOpacity,
    'glassStr': glassStr,
    'glassBlur': glassBlur,
  };

  @override
  bool operator ==(Object other) =>
      other is Transparency &&
      other.on == on &&
      other.overlayGlass == overlayGlass &&
      other.blockOpacity == blockOpacity &&
      other.glassStr == glassStr &&
      other.glassBlur == glassBlur;

  @override
  int get hashCode =>
      Object.hash(on, overlayGlass, blockOpacity, glassStr, glassBlur);
}

final transparencyProvider =
    NotifierProvider<TransparencyController, Transparency>(
      TransparencyController.new,
    );

class TransparencyController extends Notifier<Transparency> {
  static const _key = 'transparency';

  @override
  Transparency build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    int number(String field, int fallback, int max) {
      final value = raw[field];
      // Битую запись (правили файл руками) молча заменяем умолчанием: вид
      // приложения не повод ронять запуск.
      return value is num ? value.round().clamp(0, max) : fallback;
    }

    return Transparency(
      on: raw['on'] == true,
      overlayGlass: raw['overlayGlass'] == true,
      blockOpacity: number('blockOpacity', kTrOpacityDefault, 100),
      glassStr: number('glassStr', kTrBrightnessDefault, 100),
      glassBlur: number('glassBlur', kTrBlurDefault, kTrBlurMax),
    );
  }

  void setOn(bool on) => _set(state.copyWith(on: on));

  void setOverlayGlass(bool on) => _set(state.copyWith(overlayGlass: on));

  /// Ползунок «Уровень прозрачности»: пришло «насколько видно фон», в стор
  /// уходит десктопная непрозрачность.
  void setTransparencyPercent(int percent) =>
      _set(state.copyWith(blockOpacity: 100 - percent.clamp(0, 100)));

  void setGlassStr(int value) =>
      _set(state.copyWith(glassStr: value.clamp(0, 100)));

  void setGlassBlur(int value) =>
      _set(state.copyWith(glassBlur: value.clamp(0, kTrBlurMax)));

  void _set(Transparency next) {
    if (next == state) return;
    state = next;
    ref.read(jsonStoreProvider).write(_key, next.toJson());
  }
}

/// Готовое стекло: чем красить и чем фильтровать подложку.
@immutable
class GlassSpec {
  const GlassSpec({required this.opacity, required this.filter});

  /// Доля непрозрачности заливки блока (десктопная `--glass-block-bg`).
  final double opacity;

  /// Фильтр подложки (десктопный `--glass-filter`). `null` — фильтровать
  /// нечего (размытие 0 и яркость 1): стекло сводится к полупрозрачной
  /// заливке, и заводить ради него слой незачем.
  final ui.ImageFilter? filter;
}

/// Матрица умножения яркости — аналог CSS `brightness(k)`: множим RGB, альфу
/// не трогаем.
ui.ColorFilter _brightnessFilter(double k) => ui.ColorFilter.matrix(<double>[
  k, 0, 0, 0, 0, //
  0, k, 0, 0, 0, //
  0, 0, k, 0, 0, //
  0, 0, 0, 1, 0, //
]);

GlassSpec? _spec(Transparency tr, {required bool enabled}) {
  if (!enabled) return null;
  final blur = tr.glassBlur.toDouble();
  final bright = tr.brightness;
  // `clamp`: без него размытие тянет прозрачность с краёв блока и по его
  // периметру идёт светлая кайма (та же беда, что у фона шторки).
  final blurFilter = blur > 0
      ? ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: ui.TileMode.clamp,
        )
      : null;
  final colorFilter = bright == 1 ? null : _brightnessFilter(bright);
  return GlassSpec(
    opacity: tr.opacity,
    filter: switch ((blurFilter, colorFilter)) {
      (final b?, final c?) => ui.ImageFilter.compose(outer: c, inner: b),
      (final b?, null) => b,
      (null, final c?) => c,
      _ => null,
    },
  );
}

/// Стекло блоков интерфейса. `null` — прозрачность выключена, блоки сплошные.
final glassProvider = Provider<GlassSpec?>((ref) {
  final tr = ref.watch(transparencyProvider);
  return _spec(tr, enabled: tr.on);
});

/// Стекло всплывающих поверхностей — шторок, меню и затемнения под ними.
final overlayGlassProvider = Provider<GlassSpec?>((ref) {
  final tr = ref.watch(transparencyProvider);
  return _spec(tr, enabled: tr.overlaysOn);
});
