/// Знак бренда — 8-лучевая звезда, та же, что в иконке приложения.
///
/// В файле звезда белая, поэтому перекрашивается через `srcIn`: на светлой
/// теме белое на белом было бы не видно.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

class BloomMark extends StatelessWidget {
  const BloomMark({super.key, this.size = 18, this.color, this.opacity = 1});

  final double size;

  /// Цвет знака; по умолчанию — `text` темы.
  final Color? color;

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final tint = (color ?? context.bloom.text).withValues(alpha: opacity);
    return Image.asset(
      'assets/brand/bloom_mark.png',
      width: size,
      height: size,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
}
