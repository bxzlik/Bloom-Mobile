/// Акцент из обложки — порт десктопного `coverAccent.ts`.
///
/// Обложка сжимается до 32×32, из пикселей берётся самый «сочный» (насыщенность
/// × близость светлоты к 0.5), его тон и служит акцентом. Светлота и
/// насыщенность зажимаются вокруг заданной яркости, иначе на тёмной обложке
/// акцент сливается с фоном, а на светлой выцветает.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/store/cover_store.dart';
import '../../core/store/settings_store.dart';

/// Полуширина коридора светлоты вокруг заданной яркости (десктопный `L_BAND`).
const double _lBand = 0.075;

/// Доминантный цвет обложки в HSL — сырьё, из которого считается акцент.
///
/// Держим отдельно от готового цвета: движение ползунка яркости пересчитывает
/// акцент из него же, без повторного скана картинки.
class CoverHsl {
  const CoverHsl(this.h, this.s, this.l);

  /// Тон 0–360.
  final double h;

  /// Насыщенность и светлота 0–1.
  final double s;
  final double l;
}

/// Доминантный HSL обложки; `null` — обложки нет или картинка не загрузилась.
Future<CoverHsl?> extractCoverHsl(String? cover) async {
  final provider = coverImage(cover);
  if (provider == null) return null;
  // Скан идёт по 32×32: сеть и декодер отдают полноразмерную картинку, а нам
  // нужен доминант — сжатие и быстрее, и заодно усредняет шум.
  final image = await _load(
    ResizeImage(provider, width: 32, height: 32, allowUpscaling: true),
  );
  if (image == null) return null;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();

    var bestH = 0.0;
    var bestS = 0.0;
    var bestL = 0.0;
    var bestScore = -1.0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      final r = bytes[i] / 255;
      final g = bytes[i + 1] / 255;
      final b = bytes[i + 2] / 255;
      final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
      final l = (max + min) / 2;
      final s = max == min
          ? 0.0
          : l < 0.5
          ? (max - min) / (max + min)
          : (max - min) / (2 - max - min);
      final score = s * (1 - (l - 0.5).abs() * 1.5);
      if (score <= bestScore) continue;
      bestScore = score;
      var h = 0.0;
      if (max != min) {
        if (max == r) {
          h = ((g - b) / (max - min) + 6) % 6;
        } else if (max == g) {
          h = (b - r) / (max - min) + 2;
        } else {
          h = (r - g) / (max - min) + 4;
        }
        h = (h * 60).roundToDouble();
      }
      bestH = h;
      bestS = s;
      bestL = l;
    }
    return CoverHsl(bestH, bestS, bestL);
  } catch (_) {
    return null;
  } finally {
    image.dispose();
  }
}

/// Доминантный HSL → цвет акцента при заданной яркости.
///
/// Насыщенность едет за яркостью (0.75 + level): на тёмном тоне высокая S даёт
/// цветной шум, на светлом — наоборот нужна «сочность».
Color accentFromHsl(CoverHsl hsl, double level) {
  final lvl = clampAutoAccentL(level);
  final s = (hsl.s * (0.75 + lvl)).clamp(0.0, 1.0);
  final l = hsl.l.clamp(lvl - _lBand, lvl + _lBand);
  return HSLColor.fromAHSL(1, hsl.h % 360, s, l).toColor();
}

/// Картинка провайдера в виде `ui.Image`; `null` — сеть/файл не отдали.
Future<ui.Image?> _load(ImageProvider provider) {
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(ui.Image? image) {
    if (!completer.isCompleted) completer.complete(image);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener((info, _) {
    // Клон: сам кадр принадлежит кешу картинок, освобождать его нам нельзя —
    // отдаём наружу копию, а `info` закрываем сразу.
    final image = info.image.clone();
    info.dispose();
    finish(image);
  }, onError: (_, _) => finish(null));
  stream.addListener(listener);
  return completer.future;
}
