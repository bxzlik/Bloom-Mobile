/// Рисовка типов слайдера — порт `shared/styles/sliders-telemetry.css`
/// (`body.slider-thin/-ios/-wave`) и `features/player/lib/waveSlider.ts`.
///
/// Всё делаем формами самого `Slider` (`SliderTrackShape`/
/// `SliderComponentShape`), а не своей раскладкой поверх дорожки: слайдер знает,
/// где сейчас пуговка, и двигает её под пальцем — любая параллельная разметка
/// разъезжалась бы с ней на каждом кадре. Заодно ловушка под палец, перетаскивание
/// и тап по дорожке остаются даровыми.
///
/// Один вход на всех — [bloomSliderTheme]: и плеер, и превью в настройках берут
/// оформление отсюда, чтобы картинка в шторке не разошлась с настоящей.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../customization/ui/image_thumb.dart';
import '../slider_style_store.dart';

/// Высота дорожки для каждого типа.
///
/// Волна — не дорожка, а полоса столбиков (на ПК `height:28px`), поэтому и
/// высота у неё под столбики. Тонкая — десктопные 1.5 px.
double sliderTrackHeight(SliderStyle style) => switch (style) {
  SliderStyle.standard => 5,
  SliderStyle.thin => 1.5,
  SliderStyle.ios => 5,
  SliderStyle.wave => 28,
};

/// Оформление слайдера прогресса под выбранный тип.
///
/// [thumbImage] — фото пуговки из «Кастомизации». Оно перебивает пуговку типа
/// (как на ПК, где фото показывается при любом типе), но не волну: там пуговки
/// нет вовсе — позицию показывает граница залитых столбиков.
///
/// [waveSeed] — зерно узора волны, по одному на трек (см. [WaveTrackShape]).
SliderThemeData bloomSliderTheme(
  SliderThemeData base, {
  required SliderStyle style,
  required BloomTokens tokens,
  ui.Image? thumbImage,
  int waveSeed = 0,
}) {
  final SliderComponentShape thumb = switch (style) {
    SliderStyle.wave => SliderComponentShape.noThumb,
    _ when thumbImage != null => ImageSliderThumb(thumbImage),
    SliderStyle.standard => SliderComponentShape.noThumb,
    SliderStyle.thin => const DotSliderThumb(),
    SliderStyle.ios => const CapsuleSliderThumb(),
  };
  final SliderTrackShape track = switch (style) {
    SliderStyle.ios => const IosTrackShape(),
    SliderStyle.wave => WaveTrackShape(seed: waveSeed),
    _ => const RoundedRectSliderTrackShape(),
  };

  return base.copyWith(
    trackShape: track,
    trackHeight: sliderTrackHeight(style),
    thumbShape: thumb,
    activeTrackColor: tokens.accent,
    inactiveTrackColor: style == SliderStyle.wave
        ? waveRestColor(tokens)
        : tokens.track,
    // Ореол под пальцем не нужен нигде (заливок в Bloom нет).
    overlayShape: SliderComponentShape.noOverlay,
  );
}

/// Круглая пуговка тонкого типа: 10 px акцентом с тенью (десктопные
/// `body.slider-thin .ps-bar-thumb`).
class DotSliderThumb extends SliderComponentShape {
  const DotSliderThumb({this.size = 10});

  final double size;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.thumbColor ?? sliderTheme.activeTrackColor!;
    canvas.drawCircle(
      center.translate(0, 1),
      size / 2,
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawCircle(center, size / 2, Paint()..color = color);
  }
}

/// Вертикальная капля iOS-типа: 4×28 акцентом с тенью (десктопные
/// `body.slider-ios .ps-bar-thumb`).
class CapsuleSliderThumb extends SliderComponentShape {
  const CapsuleSliderThumb({this.width = 4, this.height = 28});

  final double width;
  final double height;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.thumbColor ?? sliderTheme.activeTrackColor!;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(width / 2),
    );
    canvas.drawRRect(
      rect.shift(const Offset(0, 1)),
      Paint()
        ..color = const Color(0x59000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawRRect(rect, Paint()..color = color);
  }
}

/// Дорожка iOS-типа: два капсульных сегмента с прозрачным зазором у пуговки.
///
/// На ПК зазор вырезан из дорожки (`--ios-gap:6px`, `::before` слева от
/// ползунка и подрезанная заливка справа) — здесь то же самое, только сегменты
/// рисуются прямо, без вырезания.
class IosTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const IosTrackShape({this.gap = 6});

  /// Пустота с каждой стороны пуговки (десктопный `--ios-gap`).
  final double gap;

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;

    final radius = Radius.circular(rect.height / 2);
    final canvas = context.canvas;
    // Сегмент рисуем, только если после зазора от него что-то осталось: у краёв
    // дорожки он вырождается, и капсула в минус ширины дала бы кляксу.
    void segment(double left, double right, Color color) {
      if (right - left <= 0) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, rect.top, right, rect.bottom),
          radius,
        ),
        Paint()..color = color,
      );
    }

    segment(rect.left, thumbCenter.dx - gap, sliderTheme.activeTrackColor!);
    segment(thumbCenter.dx + gap, rect.right, sliderTheme.inactiveTrackColor!);
  }
}

/// Дорожка-волна: столбики вместо полосы, до позиции — акцентом, дальше —
/// плёнкой.
///
/// Узор — порт `regenWave`: та же огибающая из трёх синусов со случайными
/// фазами плюс дрожание. Отличие одно, и оно намеренное: фазы берутся не из
/// `Math.random()` на каждую смену трека, а из [seed] (id трека) — в
/// декларативном UI художник зовётся на каждый кадр перемотки, и «свежий»
/// случай перерисовывал бы волну заново десятки раз в секунду.
class WaveTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const WaveTrackShape({required this.seed});

  /// Зерно узора: один трек — один рисунок.
  final int seed;

  /// Шаг столбика (сам столбик + просвет). На ПК столбиков ровно 120 на всю
  /// ширину плеера; на телефоне полоса вдвое уже, и фиксированное число
  /// схлопнуло бы их в кашу — держим постоянным шаг, а число считаем от ширины.
  static const double pitch = 5;

  /// Просвет между столбиками (десктопный `bw - 1.5`).
  static const double slit = 1.5;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;

    final count = math.max(1, (rect.width / pitch).round());
    final bars = waveBars(seed, count, rect.height);
    final width = rect.width / count;
    final canvas = context.canvas;

    void draw(Paint paint) {
      for (var i = 0; i < count; i++) {
        final height = bars[i];
        final inner = math.max(width - slit, 1.0);
        final left = rect.left + i * width + slit / 2;
        final top = rect.top + (rect.height - height) / 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, inner, height),
            Radius.circular(math.min(inner / 2, height / 2)),
          ),
          paint,
        );
      }
    }

    draw(Paint()..color = sliderTheme.inactiveTrackColor!);
    // Залитую часть рисуем теми же столбиками под обрезкой по позиции — так
    // столбик на границе делится, а не перекрашивается целиком.
    final split = thumbCenter.dx - rect.left;
    if (split > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(rect.left, rect.top, split, rect.height));
      draw(Paint()..color = sliderTheme.activeTrackColor!);
      canvas.restore();
    }
  }
}

/// Высоты столбиков волны — порт `regenWave` из `waveSlider.ts`.
///
/// На ПК высоты (2..21) считаны под полосу в 28 px; [height] масштабирует их
/// под свою — превью в настройках ниже плеерной полосы.
List<double> waveBars(int seed, int count, double height) {
  final rnd = math.Random(seed);
  final s1 = rnd.nextDouble() * 10;
  final s2 = rnd.nextDouble() * 10;
  final s3 = rnd.nextDouble() * 10;
  final scale = height / 28;
  return [
    for (var i = 0; i < count; i++)
      () {
        final t = i / count;
        final env =
            (math.sin(t * math.pi * 4 + s1)).abs() * 0.45 +
            (math.sin(t * math.pi * 9 + s2)).abs() * 0.35 +
            (math.sin(t * math.pi * 17 + s3)).abs() * 0.2;
        return (2 + env * 16 + rnd.nextDouble() * 3) * scale;
      }(),
  ];
}

/// Цвет незалитых столбиков волны.
///
/// Общая дорожка (`track`, плёнка 4%) для столбиков слишком тиха — они тоньше
/// полосы и на ней просто пропадают. На ПК под это заведена своя ручка
/// `--wave-rest-a` (плёнка 10%), берём её же.
Color waveRestColor(BloomTokens tokens) =>
    (tokens.isLight ? const Color(0xFF000000) : const Color(0xFFFFFFFF))
        .withValues(alpha: 0.1);
