/// Стопка из трёх обложек веером — порт десктопного `.fy-all`: верхняя по
/// центру, задние вынесены в стороны, наклонены и притушены. Одна на
/// «Вся подборка» в «Для вас» и на плашки «Любимые / История» — различаются
/// только размерами.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';

class CoverFan extends StatelessWidget {
  const CoverFan({
    super.key,
    required this.front,
    this.left,
    this.right,
    required this.width,
    required this.height,
    required this.frontSize,
    required this.backSize,
    required this.shift,
    this.tilt = 7 * math.pi / 180,
    this.dim = 0.55,
    this.shadowScale = 1,
  });

  /// Обложки: верхняя и две задние. Задней нет — её место просто пустое.
  final String? front;
  final String? left;
  final String? right;

  final double width;
  final double height;
  final double frontSize;
  final double backSize;

  /// Вынос задних обложек от центра.
  final double shift;

  /// Наклон задних обложек, радианы.
  final double tilt;

  /// Яркость задних обложек (десктопный `brightness(.55)`).
  final double dim;

  /// Множитель размытия и сдвига теней: на мелкой стопке тени карточки
  /// «Для вас» растеклись бы на всю плашку.
  final double shadowScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        // Порядок детей = порядок слоёв: задние раньше верхней.
        children: [
          if (left != null) _back(context, left!, -1),
          if (right != null) _back(context, right!, 1),
          _Shadowed(
            blur: 22 * shadowScale,
            offsetY: 8 * shadowScale,
            opacity: 0.5,
            child: Cover(url: front, size: frontSize),
          ),
        ],
      ),
    );
  }

  Widget _back(BuildContext context, String url, int side) {
    return Transform.translate(
      offset: Offset(side * shift, 0),
      child: Transform.rotate(
        angle: side * tilt,
        child: _Shadowed(
          blur: 14 * shadowScale,
          offsetY: 4 * shadowScale,
          opacity: 0.35,
          child: Stack(
            children: [
              Cover(url: url, size: backSize),
              // Плёнка вместо `brightness`: притушить картинку так дешевле, чем
              // гонять её через цветовой фильтр.
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    context.bloom.radius * 0.72,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 1 - dim),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Тень под обложкой той же формы, что и сама обложка.
class _Shadowed extends StatelessWidget {
  const _Shadowed({
    required this.child,
    required this.blur,
    required this.offsetY,
    required this.opacity,
  });

  final Widget child;
  final double blur;
  final double offsetY;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // Та же форма, что у [Cover] по умолчанию.
        borderRadius: BorderRadius.circular(context.bloom.radius * 0.72),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: opacity),
            blurRadius: blur,
            offset: Offset(0, offsetY),
          ),
        ],
      ),
      child: child,
    );
  }
}
