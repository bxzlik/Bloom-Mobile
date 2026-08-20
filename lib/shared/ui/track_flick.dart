/// Горизонтальный жест «перелистнуть трек» — миниплеер и полноэкранный плеер.
///
/// В отличие от [SwipeRow] здесь ничего не остаётся под пальцем: плашек нет,
/// содержимое само уезжает в сторону, действие срабатывает, и новое приезжает
/// с противоположного края. Что именно едет, решает вызывающий — [builder]
/// получает долю сдвига (−1…1) и оборачивает во [FlickSlide] ровно ту часть,
/// которая должна двигаться (в плеере это обложка с названием, а не весь
/// экран).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Доля ширины, после которой отпускание перелистывает трек.
const double kFlickThreshold = 0.22;

const double _flingVelocity = 700;
const Duration _out = Duration(milliseconds: 150);
const Duration _back = Duration(milliseconds: 240);
const Duration _snap = Duration(milliseconds: 200);

/// С какой доли приезжает новый трек — не с самого края: полный «пролёт»
/// читается как рывок.
const double _enterFrom = 0.55;

class TrackFlick extends StatefulWidget {
  const TrackFlick({
    super.key,
    required this.builder,
    this.onLeft,
    this.onRight,
  });

  /// Свайп влево. `null` — в эту сторону содержимое не двигается.
  final VoidCallback? onLeft;

  /// Свайп вправо.
  final VoidCallback? onRight;

  final Widget Function(BuildContext context, ValueListenable<double> shift)
  builder;

  @override
  State<TrackFlick> createState() => _TrackFlickState();
}

class _TrackFlickState extends State<TrackFlick>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _shift = ValueNotifier<double>(0);

  /// Заводится в [initState], а не ленивым полем: обложку, которую ни разу не
  /// перелистнули, первым и единственным трогал бы `dispose()`, а `vsync`
  /// оттуда лезет за `TickerMode` в уже мёртвый контекст и роняет само
  /// освобождение (та же ловушка, что была в `lyrics_view.dart`).
  late final AnimationController _anim;

  Animation<double>? _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _snap)
      ..addListener(() => _shift.value = _slide?.value ?? 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    _shift.dispose();
    super.dispose();
  }

  Future<void> _animateTo(double target, Duration duration) {
    _slide = Tween<double>(
      begin: _shift.value,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.duration = duration;
    return _anim.forward(from: 0);
  }

  void _update(DragUpdateDetails d, double width) {
    if (width <= 0) return;
    _anim.stop();
    var next = _shift.value + d.delta.dx / width;
    if (next < 0 && widget.onLeft == null) next = 0;
    if (next > 0 && widget.onRight == null) next = 0;
    _shift.value = next.clamp(-1.0, 1.0);
  }

  Future<void> _end(DragEndDetails d, double width) async {
    final value = _shift.value;
    final velocity = width <= 0 ? 0.0 : (d.primaryVelocity ?? 0);
    final flung =
        velocity.abs() > _flingVelocity && velocity.sign == value.sign;
    final action = value < 0 ? widget.onLeft : widget.onRight;
    if (action == null || !(value.abs() >= kFlickThreshold || flung)) {
      await _animateTo(0, _snap);
      return;
    }
    // Уводим до края, меняем трек и вводим новый с другой стороны: смена
    // содержимого приходится ровно на тот кадр, когда старого уже не видно.
    await _animateTo(value.sign, _out);
    if (!mounted) return;
    action();
    _shift.value = -value.sign * _enterFrom;
    await _animateTo(0, _back);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onLeft == null && widget.onRight == null) {
      return widget.builder(context, _shift);
    }
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return GestureDetector(
          onHorizontalDragUpdate: (d) => _update(d, width),
          onHorizontalDragEnd: (d) => _end(d, width),
          onHorizontalDragCancel: () => _animateTo(0, _snap),
          child: widget.builder(context, _shift),
        );
      },
    );
  }
}

/// Часть, которая едет за пальцем: сдвиг в долях СВОЕЙ ширины плюс затухание.
class FlickSlide extends StatelessWidget {
  const FlickSlide({
    super.key,
    required this.shift,
    required this.child,
    this.amplitude = 1,
  });

  /// Доля сдвига от [TrackFlick].
  final ValueListenable<double> shift;

  /// Насколько сильно эта часть отзывается на жест: обложка едет вся, подписи
  /// под ней — заметно меньше, иначе они обгоняют её на краю экрана.
  final double amplitude;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: shift,
      child: child,
      builder: (context, value, child) => FractionalTranslation(
        translation: Offset(value * amplitude, 0),
        child: Opacity(
          opacity: (1 - value.abs() * 1.2).clamp(0.0, 1.0),
          child: child,
        ),
      ),
    );
  }
}
