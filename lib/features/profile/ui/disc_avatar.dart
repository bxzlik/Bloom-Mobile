/// Винил-диск — дефолтный аватар профиля. Порт `discSvg.ts`, слой в слой.
///
/// На десктопе это строка SVG; здесь тот же рисунок кладётся [CustomPainter].
/// Координаты оставлены в исходной сетке 72×72 и масштабируются целиком —
/// так пропорции колец, блика и «пятака» совпадают с десктопными при любом
/// размере.
library;

import 'package:flutter/material.dart';

/// Яркие цвета для пикера своего диска — `discDefColors`.
const List<Color> kDiscDefColors = [
  Color(0xFF6E3CFF),
  Color(0xFFFF3C3C),
  Color(0xFF1E8CFF),
  Color(0xFFBE32FF),
  Color(0xFF28D25A),
  Color(0xFFFFB914),
];

/// Тема диска: две ступени фона, два цвета «свечения» и цвет пятака.
@immutable
class _DiscTheme {
  const _DiscTheme(this.b1, this.b2, this.s1, this.s2, this.cc);

  final Color b1;
  final Color b2;
  final Color s1;
  final Color s2;
  final Color cc;

  @override
  bool operator ==(Object other) =>
      other is _DiscTheme &&
      other.b1 == b1 &&
      other.b2 == b2 &&
      other.s1 == s1 &&
      other.s2 == s2 &&
      other.cc == cc;

  @override
  int get hashCode => Object.hash(b1, b2, s1, s2, cc);
}

const List<_DiscTheme> _themes = [
  _DiscTheme(
    Color(0xFF1A1235),
    Color(0xFF080514),
    Color(0x666E3CFF),
    Color(0x4032AAFF),
    Color(0xFF0E0A22),
  ),
  _DiscTheme(
    Color(0xFF3A0808),
    Color(0xFF160202),
    Color(0x66FF3C3C),
    Color(0x40FF8C1E),
    Color(0xFF120303),
  ),
  _DiscTheme(
    Color(0xFF062038),
    Color(0xFF020B18),
    Color(0x661E8CFF),
    Color(0x4014DCBE),
    Color(0xFF030D1A),
  ),
  _DiscTheme(
    Color(0xFF280638),
    Color(0xFF100215),
    Color(0x66BE32FF),
    Color(0x40FF46A0),
    Color(0xFF0E0218),
  ),
  _DiscTheme(
    Color(0xFF063020),
    Color(0xFF020F08),
    Color(0x6628D25A),
    Color(0x4014FFA0),
    Color(0xFF020E08),
  ),
  _DiscTheme(
    Color(0xFF302008),
    Color(0xFF120C02),
    Color(0x66FFB914),
    Color(0x40FF6414),
    Color(0xFF100800),
  ),
];

/// Тема из одного цвета — `discThemeFromColor`.
_DiscTheme _themeFromColor(Color c) {
  Color dim(double f) => Color.from(alpha: 1, red: c.r * f, green: c.g * f, blue: c.b * f);
  double up(double v, double add) => (v + add / 255).clamp(0.0, 1.0);
  return _DiscTheme(
    dim(0.28),
    dim(0.10),
    c.withValues(alpha: 0.4),
    Color.from(
      alpha: 0.25,
      red: up(c.r, 40),
      green: up(c.g, 60),
      blue: up(c.b, 20),
    ),
    dim(0.18),
  );
}

class DiscAvatar extends StatelessWidget {
  const DiscAvatar({super.key, required this.idx, this.color, this.size});

  final int idx;
  final Color? color;

  /// `null` — занять всё, что дал родитель.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = color != null
        ? _themeFromColor(color!)
        : _themes[idx % _themes.length];
    final painter = CustomPaint(painter: _DiscPainter(theme));
    return size == null
        ? painter
        : SizedBox(width: size, height: size, child: painter);
  }
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter(this.theme);

  final _DiscTheme theme;

  /// Сетка исходного SVG.
  static const double _unit = 72;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / _unit;
    canvas.save();
    canvas.scale(k);

    const center = Offset(36, 36);
    const full = Rect.fromLTWH(0, 0, _unit, _unit);
    final paint = Paint()..isAntiAlias = true;

    // Тело диска: радиальный градиент от смещённого вверх-влево центра.
    paint.shader = RadialGradient(
      center: const Alignment(-0.2, -0.32),
      radius: 0.7,
      colors: [theme.b1, theme.b2],
    ).createShader(full);
    canvas.drawCircle(center, 36, paint);

    // Дорожки.
    paint.shader = null;
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.07);
    for (final r in const [28.0, 18.0]) {
      canvas.drawCircle(center, r, paint);
    }
    paint.style = PaintingStyle.fill;

    // Свечение. Прозрачный конец берётся от самого цвета свечения, а не
    // «чёрный с нулевой альфой»: браузер смешивает градиент в premultiplied,
    // а Flutter — нет, и от чёрного по краю пошла бы грязная кайма.
    paint.shader = RadialGradient(
      center: const Alignment(-0.4, -0.52),
      radius: 0.62,
      colors: [theme.s2, theme.s1, theme.s1.withValues(alpha: 0)],
      stops: const [0, 0.48, 1],
    ).createShader(full);
    canvas.drawCircle(center, 36, paint);

    // Блик.
    paint.shader = null;
    paint.color = Colors.white.withValues(alpha: 0.045);
    canvas.drawCircle(const Offset(28, 22), 5, paint);

    // Пятак: свой градиент, отсчитанный от его собственных границ.
    const label = 10.5;
    paint.shader = RadialGradient(
      center: const Alignment(0, -0.24),
      radius: 0.55,
      colors: [theme.b1, theme.cc],
    ).createShader(Rect.fromCircle(center: center, radius: label));
    canvas.drawCircle(center, label, paint);

    // Отверстие.
    paint.shader = null;
    paint.color = const Color(0xFF050505);
    canvas.drawCircle(center, 2.8, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.theme != theme;
}
