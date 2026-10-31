/// A cover's tone as text on the page: light on the dark theme, dark on the
/// light one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/cover_accent.dart';

class CoverTones {
  const CoverTones({required this.ink, required this.inkLight});

  final Color ink;
  final Color inkLight;

  factory CoverTones.of(CoverHsl hsl) {
    Color ink(double light) {
      // A grey cover has no hue to speak of: it isn't coloured.
      final s = hsl.s < 0.12 ? hsl.s : hsl.s.clamp(0.35, 0.8).toDouble();
      return HSLColor.fromAHSL(1, hsl.h, s, light).toColor();
    }

    return CoverTones(ink: ink(0.72), inkLight: ink(0.34));
  }
}

/// Tones by cover link. Kept until restart: scanning means loading the image.
final coverTonesProvider = FutureProvider.family<CoverTones?, String?>((
  ref,
  cover,
) async {
  final hsl = await extractCoverHsl(cover);
  return hsl == null ? null : CoverTones.of(hsl);
});
