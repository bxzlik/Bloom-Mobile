/// Пуговка ползунка своей картинкой — порт десктопного контекста «Слайдер»
/// (`playerStore.sliderThumb`, там это `background-image` у `.sl-thumb`).
///
/// До этого у нашего ползунка пуговки не было вовсе (`noThumb`): позицию
/// показывал сам край залитой части. Картинка её возвращает — но только пока
/// она выбрана, без картинки всё остаётся как было.
///
/// Рисуем ЧЕРЕЗ `SliderComponentShape`, а не виджетом поверх: `Slider` сам
/// знает, где сейчас пуговка, и сам двигает её под пальцем — своя раскладка
/// поверх дорожки разъезжалась бы с ней на каждом кадре.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/cover_store.dart';
import '../custom_store.dart';

/// Диаметр пуговки. Чуть больше дорожки плеера (6), чтобы картинку было
/// видно, но не настолько, чтобы она перекрывала полосу.
const double kSliderThumbSize = 22;

/// Декодированная картинка ползунка — `null`, если её не выбрали или не
/// удалось прочитать.
///
/// Художнику нужна именно `ui.Image`: `ImageProvider` рисуется виджетами, а на
/// холст канвы кладут уже готовые пиксели. Гифка отдаёт первый кадр — как и
/// курсор-гифка на десктопе, который Chromium растеризует.
final sliderThumbProvider = FutureProvider<ui.Image?>((ref) async {
  final src = ref.watch(customSrcProvider(CustomCtx.slider));
  if (src == null) return null;
  final provider = coverImage(src);
  if (provider == null) return null;

  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void done(ui.Image? image) {
    if (!completer.isCompleted) completer.complete(image);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    // Кадр может прийти не один (та же гифка) — берём первый и отписываемся.
    (info, _) => done(info.image),
    onError: (_, _) => done(null),
  );
  stream.addListener(listener);
  ref.onDispose(() => stream.removeListener(listener));
  return completer.future;
});

class ImageSliderThumb extends SliderComponentShape {
  const ImageSliderThumb(this.image, {this.size = kSliderThumbSize});

  final ui.Image image;
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
    final radius = size / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    // `cover`: картинку любых пропорций вписываем в круг без искажений —
    // лишнее уходит под обрезку.
    final src = _coverSrc(image, size);
    canvas.drawImageRect(
      image,
      src,
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  /// Прямоугольник исходника для заполнения квадрата: берём центральный
  /// квадрат картинки.
  static Rect _coverSrc(ui.Image image, double side) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final cut = w < h ? w : h;
    return Rect.fromLTWH((w - cut) / 2, (h - cut) / 2, cut, cut);
  }
}
