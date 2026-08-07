/// Скелетоны загрузки: серые плашки в раскладке того, что сейчас грузится.
///
/// Полоски прогресса на экранах нет намеренно — заготовка держит будущую
/// высоту, поэтому выдача не «прыгает», когда ответ приходит.
///
/// Мигает не каждая плашка по отдельности, а всё поддерево целиком
/// ([SkeletonPulse]): один контроллер на экран и ни одного рассинхрона между
/// соседними плашками.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// Плашка-заготовка. [width] `null` — занять всю доступную ширину.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double? radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: t.iconBg,
        borderRadius: BorderRadius.circular(
          circle ? height / 2 : radius ?? t.radius * 0.72,
        ),
      ),
    );
  }
}

/// Плашка на месте строки текста: скругление по высоте, ширина — доля от
/// доступной, чтобы «строки» не выглядели одинаковой линейкой.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, required this.widthFactor, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height, radius: height / 2),
    );
  }
}

/// Общее мигание для поддерева заготовок.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  late final _opacity = Tween(begin: 1.0, end: 0.45).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Не ловит тапы: под заготовкой ничего нажимаемого нет, но и «мёртвых»
    // касаний по ней быть не должно.
    return IgnorePointer(
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}
