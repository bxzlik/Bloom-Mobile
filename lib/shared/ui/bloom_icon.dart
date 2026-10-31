/// Icons with a stroke weight that follows their size: small ones come out as
/// dark as big ones. Drawn as paths, at once: a picture would come a frame late.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

part 'glyphs.g.dart';

/// An icon: its shapes in a 24-unit box. The icons themselves are [Bi]'s.
@immutable
class BloomGlyph {
  const BloomGlyph._(this._shapes, {this.ink = false});

  final List<_Shape> _shapes;

  /// Drawn as filled outlines, not strokes: when small, it gets a thin outline
  /// of its own colour to keep up with the stroked ones.
  final bool ink;
}

@immutable
class _Shape {
  const _Shape.f(this.d) : kind = _Kind.fill;
  const _Shape.e(this.d) : kind = _Kind.evenOdd;
  const _Shape.s(this.d) : kind = _Kind.stroke;

  final String d;
  final _Kind kind;

  static final _paths = Expando<Path>();

  // Parsed once, on the first paint.
  Path get path => _paths[this] ??= () {
    final path = _PathOut(Path());
    writeSvgPathDataToPath(d, path);
    return path.out
      ..fillType = kind == _Kind.evenOdd
          ? PathFillType.evenOdd
          : PathFillType.nonZero;
  }();
}

enum _Kind { fill, evenOdd, stroke }

class _PathOut extends PathProxy {
  _PathOut(this.out);

  final Path out;

  @override
  void moveTo(double x, double y) => out.moveTo(x, y);

  @override
  void lineTo(double x, double y) => out.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => out.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => out.close();
}

/// The stroke for an icon this big: 1.5 on big ones, heavier on small ones, at
/// most 2.2.
double bloomIconStroke(double size) =>
    (1.15 * 24 / size).clamp(1.5, 2.2).toDouble();

/// A Solar icon. Size and colour default to the [IconTheme]'s, as [Icon]'s do.
class BloomIcon extends StatelessWidget {
  const BloomIcon(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
    this.shadows,
  });

  final BloomGlyph? glyph;
  final double? size;
  final Color? color;
  final List<Shadow>? shadows;

  /// A weight tuned by hand for a place; otherwise [bloomIconStroke].
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final glyph = this.glyph;
    if (glyph == null) return SizedBox.square(dimension: side);
    var tint = color ?? theme.color ?? const Color(0xFF000000);
    final opacity = theme.opacity ?? 1;
    if (opacity != 1) tint = tint.withValues(alpha: tint.a * opacity);
    // Its own size in the middle of whatever box it's given, as Icon does: a
    // parent's tight constraints would blow it up to the parent's size.
    return SizedBox.square(
      dimension: side,
      child: Center(
        child: CustomPaint(
          size: Size.square(side),
          painter: _GlyphPainter(
            glyph,
            tint,
            strokeWidth ?? bloomIconStroke(side),
            shadows,
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color, this.stroke, this.shadows);

  final BloomGlyph glyph;
  final Color color;
  final double stroke;
  final List<Shadow>? shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    for (final shadow in shadows ?? const <Shadow>[]) {
      canvas.save();
      canvas.translate(shadow.offset.dx, shadow.offset.dy);
      _draw(
        canvas,
        scale,
        shadow.color,
        MaskFilter.blur(BlurStyle.normal, shadow.blurSigma / scale),
      );
      canvas.restore();
    }
    _draw(canvas, scale, color, null);
  }

  void _draw(Canvas canvas, double scale, Color color, MaskFilter? blur) {
    canvas.save();
    canvas.scale(scale);
    // A filled icon is outlined by as much as the stroke is over 1.5.
    final ink = glyph.ink ? stroke - 1.5 : 0.0;
    for (final shape in glyph._shapes) {
      final paint = Paint()
        ..color = color
        ..maskFilter = blur;
      if (shape.kind == _Kind.stroke) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(shape.path, paint);
        continue;
      }
      canvas.drawPath(shape.path, paint);
      if (ink > 0) {
        canvas.drawPath(
          shape.path,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = ink
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.stroke != stroke ||
      old.shadows != shadows;
}
