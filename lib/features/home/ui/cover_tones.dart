/// Тон обложки для «тёмных островов» витрин главной: плашек чарта и релизов,
/// плитки сида «Похожих на». Одна формула на всех — десктопный `tileTint`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/cover_accent.dart';

/// Нейтральный тёмный фон плашки, пока тон не посчитан или обложки нет. Не
/// цвет темы: плашка остаётся тёмной и в светлой теме — текст на ней белый.
const Color kCoverTileFallback = Color(0xFF1B1C20);

class CoverTones {
  const CoverTones({
    required this.tint,
    required this.ink,
    required this.inkLight,
  });

  /// Фон плашки — доминанта, приглушённая до тёмного коридора: цвет должен
  /// читаться оттенком, а не цветным пятном.
  final Color tint;

  /// Тот же оттенок текстом: светлый для тёмной темы…
  final Color ink;

  /// …и тёмный для светлой.
  final Color inkLight;

  factory CoverTones.of(CoverHsl hsl) {
    Color ink(double light) {
      // Серую обложку не раскрашиваем: оттенок у неё случайный, вышел бы
      // красный.
      final s = hsl.s < 0.12 ? hsl.s : hsl.s.clamp(0.35, 0.8).toDouble();
      return HSLColor.fromAHSL(1, hsl.h, s, light).toColor();
    }

    return CoverTones(
      tint: HSLColor.fromAHSL(
        1,
        hsl.h,
        math.min(0.55, hsl.s * 0.8),
        (hsl.l * 0.5).clamp(0.13, 0.24).toDouble(),
      ).toColor(),
      ink: ink(0.72),
      inkLight: ink(0.34),
    );
  }
}

/// Тона по ссылке обложки. Не autoDispose: главная пересобирается на каждый
/// заход, а скан обложки — это загрузка картинки; кеш живёт до перезапуска.
final coverTonesProvider = FutureProvider.family<CoverTones?, String?>((
  ref,
  cover,
) async {
  final hsl = await extractCoverHsl(cover);
  return hsl == null ? null : CoverTones.of(hsl);
});
