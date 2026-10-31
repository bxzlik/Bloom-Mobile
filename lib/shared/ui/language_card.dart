/// Карточка выбора языка — порт десктопного `.s-lang-card`: флаг и название на
/// самом языке, столбиком по центру.
///
/// Кода языка в углу у активной карточки нет: выбранную и так видно по рамке
/// акцентом, а бейдж «RU» сидел в углу и перекашивал карточку.
///
/// Живёт в общих, потому что мест два: первый шаг онбординга и шторка выбора
/// языка в «Настройках».
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import 'glass.dart';
import 'pressable.dart';

class LanguageCard extends StatelessWidget {
  const LanguageCard({
    super.key,
    required this.locale,
    required this.active,
    required this.onTap,
  });

  final Locale locale;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final name = switch (locale.languageCode) {
      'ru' => context.l.apLanguageRu,
      _ => context.l.apLanguageEn,
    };

    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: GlassBox(
        borderRadius: BorderRadius.circular(t.radius * 0.75),
        borderSide: BorderSide(
          color: active ? t.accent : Colors.transparent,
          width: 1.5,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(46, 46 * 24 / 36),
                painter: _FlagPainter(locale.languageCode),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: active ? t.text : t.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Один флаг — для мест, где карточка целиком не нужна: строка «Язык» в
/// «Настройках» и пункты её шторки.
class LanguageFlag extends StatelessWidget {
  const LanguageFlag({super.key, required this.code, this.width = 28});

  /// Код языка (`ru`, `en`).
  final String code;

  /// Ширина флага; высота считается по сетке 36×24.
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * 24 / 36),
    painter: _FlagPainter(code),
  );
}

/// Флаги — те же две картинки, что в `FLAGS` десктопного `InterfaceSection`,
/// с той же сеткой: холст 36×24, у американского 13 полос и кантон в семь из
/// них. Рисуем кодом, а не SVG-файлом: две фигуры проще посчитать, чем тащить
/// ассеты.
class _FlagPainter extends CustomPainter {
  const _FlagPainter(this.code);

  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 36;
    final paint = Paint();
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(2 * k),
    );
    canvas.clipRRect(rect);
    canvas.drawRect(Offset.zero & size, paint..color = const Color(0xFFFFFFFF));

    if (code == 'ru') {
      canvas.drawRect(
        Rect.fromLTWH(0, 8 * k, size.width, 8 * k),
        paint..color = const Color(0xFF0039A6),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 16 * k, size.width, 8 * k),
        paint..color = const Color(0xFFD52B1E),
      );
      return;
    }

    final stripe = 24 / 13 * k;
    paint.color = const Color(0xFFB22234);
    for (var i = 0; i < 13; i += 2) {
      canvas.drawRect(Rect.fromLTWH(0, i * stripe, size.width, stripe), paint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 15.6 * k, stripe * 7),
      paint..color = const Color(0xFF3C3B6E),
    );
    paint.color = const Color(0xFFFFFFFF);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        canvas.drawCircle(
          Offset(
            (1.6 + c * 3.1 + (r.isOdd ? 1.55 : 0)) * k,
            (1.6 + r * 2.9) * k,
          ),
          0.6 * k,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FlagPainter old) => old.code != code;
}
