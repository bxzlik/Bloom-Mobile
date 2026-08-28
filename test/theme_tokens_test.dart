/// Токены темы должны совпадать с десктопным Bloom: те же формулы от трёх
/// цветов дают те же тона. Значения сверены с комментариями в `themeStore.ts`
/// («Было руками: Dark #1c1c1c… #262626… #999/#555»).
library;

import 'package:bloom/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(Color c) {
  String ch(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${ch(c.r)}${ch(c.g)}${ch(c.b)}';
}

/// Полупрозрачный [top] поверх непрозрачного [bottom] — то, что реально видит
/// глаз. Плёнки задаются альфой, а спрашивают с них итоговый цвет.
String _over(Color top, Color bottom) {
  double ch(double t, double b) => t * top.a + b * (1 - top.a);
  return _hex(
    Color.from(
      alpha: 1,
      red: ch(top.r, bottom.r),
      green: ch(top.g, bottom.g),
      blue: ch(top.b, bottom.b),
    ),
  );
}

void main() {
  test('Dark: производные тона от #0a0a0a + белый акцент', () {
    final t = BloomThemes.dark;

    expect(t.isLight, isFalse);
    // Плоская поверхность: блоки не выделяются своим цветом.
    expect(_hex(t.card), '#0a0a0a');
    // color-mix(block, ovl 12%) — на десктопе тут раньше стояло #262626.
    expect(_hex(t.border), '#272727');
    expect(_hex(t.text), '#ffffff');
    // mix(text, block 40%) / 68% — было #999 и #555.
    expect(_hex(t.text2), '#9d9d9d');
    expect(_hex(t.muted), '#585858');
    // mix(accent, block 22%).
    expect(_hex(t.accent2), '#c9c9c9');
    // Белый акцент — надпись на нём чёрная, ховер темнеет (осветлять некуда).
    expect(_hex(t.accentText), '#000000');
    expect(_hex(t.accentHover), '#e0e0e0');
    // mix(border, ovl 20%) считается от НЕокруглённой рамки (39.4), как
    // color-mix в CSS — отсюда 83, а не 82.
    expect(_hex(t.borderFocus), '#535353');
    // Пилюли и круглые кнопки шапки — ровно #1a1a1a, и именно сплошным
    // цветом: плёнка тех же 6% даёт 24.7 и на устройстве садится в #181818.
    expect(_hex(t.pill), '#1a1a1a');
    expect(t.pill.a, 1);
    // Плёнка --icon-bg остаётся как на десктопе — для элементов над обложкой.
    expect(_over(t.iconBg, t.bg), '#191919');
    expect(t.track.a, closeTo(0.04, 0.001));
  });

  test('Light: плёнка переворачивается в чёрную, текст темнеет', () {
    final t = BloomThemes.light;

    expect(t.isLight, isTrue);
    expect(_hex(t.text), '#111111');
    // ovl теперь чёрный → рамка ТЕМНЕЕ поверхности, а не светлее.
    expect(_hex(t.border), '#cccccc');
    // Тёмный акцент #333333 → надпись на нём белая.
    expect(_hex(t.accentText), '#ffffff');
    // Чёрная плёнка «весит» больше — дорожка ослаблена до .07.
    expect(t.track.a, closeTo(0.07, 0.001));
  });

  test('Акцентная тема: glow и folderTint идут от акцента', () {
    final t = BloomThemes.midnight;
    expect(_hex(t.glow), '#4d9fff');
    expect(t.glow.a, closeTo(0.2, 0.001));
    expect(_hex(t.folderTint), '#4d9fff');
  });
}
