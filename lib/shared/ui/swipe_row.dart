/// Строка, которую можно смахнуть в сторону.
///
/// Вид — по скриншотам пользователя: под строкой из-под края вылезает
/// скруглённая плашка ровно той ширины, на сколько утянули, со значком действия
/// по центру. У удаления она красная, у остальных действий — тихая, цвета
/// «хрома» (`pill`).
///
/// Порог один на все места ([kSwipeThreshold] ширины строки либо резкий бросок);
/// пока он не пройден, плашка тусклая, после — значок подрастает и телефон
/// коротко откликается. Удаление уводит строку за край и только потом зовёт
/// обработчик, остальные действия срабатывают сразу и строка возвращается на
/// место: «в очередь» ничего из списка не убирает, и уезжать ей некуда.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../app/theme/tokens.dart';

/// Доля ширины строки, после которой действие сработает.
const double kSwipeThreshold = 0.32;

/// Бросок быстрее этого срабатывает и без порога.
const double _flingVelocity = 900;

/// Красный плашки удаления — тот же тон, из которого на десктопе сделан
/// системный «Любимое» (`#E03454`): своего «опасного» цвета в токенах нет, а
/// заводить ещё один красный ради одной плашки незачем.
const Color kSwipeDangerColor = Color(0xFFE03454);

const Duration _snapBack = Duration(milliseconds: 220);
const Duration _flyOut = Duration(milliseconds: 160);

/// Плашка одного направления.
@immutable
class SwipePanel {
  const SwipePanel({
    required this.icon,
    required this.onFire,
    this.danger = false,
    this.dismiss = false,
  });

  final IconData icon;

  /// Что сделать, когда порог пройден.
  final VoidCallback onFire;

  /// Красная плашка — удаление.
  final bool danger;

  /// Строка уезжает за край: её сейчас не станет. Иначе она вернётся на место.
  final bool dismiss;
}

class SwipeRow extends StatefulWidget {
  const SwipeRow({super.key, required this.child, this.left, this.right});

  /// Плашка, которая вылезает СЛЕВА, — свайп вправо. `null` — в эту сторону
  /// строка не двигается.
  final SwipePanel? left;

  /// Плашка справа — свайп влево.
  final SwipePanel? right;

  final Widget child;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow>
    with SingleTickerProviderStateMixin {
  /// Заводится в [initState], а не ленивым полем: строку, которую ни разу не
  /// свайпнули, первым и единственным трогал бы `dispose()`, а `vsync` оттуда
  /// лезет за `TickerMode` в уже мёртвый контекст и роняет само освобождение
  /// (та же ловушка, что была в `lyrics_view.dart`).
  late final AnimationController _anim;

  Animation<double>? _slide;

  /// Сдвиг строки в пикселях: положительный — вправо.
  double _offset = 0;

  /// Порог пройден: значок подрос, отпускание сработает.
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _snapBack)
      ..addListener(_onTick);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onTick() {
    final slide = _slide;
    if (slide == null) return;
    setState(() => _offset = slide.value);
  }

  /// Плашка, которая сейчас видна (или должна вылезти в эту сторону).
  SwipePanel? _panelFor(double offset) =>
      offset > 0 ? widget.left : (offset < 0 ? widget.right : null);

  void _update(DragUpdateDetails d, double width) {
    _anim.stop();
    var next = _offset + d.delta.dx;
    // В сторону, где действия нет, строка просто не идёт: пустая плашка
    // выглядела бы поломкой.
    if (next > 0 && widget.left == null) next = 0;
    if (next < 0 && widget.right == null) next = 0;
    final armed = next.abs() >= width * kSwipeThreshold;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _offset = next.clamp(-width, width);
      _armed = armed;
    });
  }

  void _end(DragEndDetails d, double width) {
    final panel = _panelFor(_offset);
    final velocity = d.primaryVelocity ?? 0;
    final flung =
        velocity.abs() > _flingVelocity && velocity.sign == _offset.sign;
    if (panel == null || !(_armed || flung)) {
      _animateTo(0, _snapBack);
      return;
    }
    if (!panel.dismiss) {
      panel.onFire();
      _animateTo(0, _snapBack);
      return;
    }
    _animateTo(_offset.sign * width, _flyOut).then((_) {
      if (!mounted) return;
      // Сдвиг снимаем ДО удаления: список не анимированный, и элемент этой
      // строки достанется следующему треку — уехавшим он остаться не должен.
      setState(() {
        _offset = 0;
        _armed = false;
      });
      panel.onFire();
    });
  }

  Future<void> _animateTo(double target, Duration duration) {
    _slide = Tween<double>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.duration = duration;
    if (target == 0) _armed = false;
    return _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.left == null && widget.right == null) return widget.child;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final panel = _panelFor(_offset);
        return GestureDetector(
          // Тап и долгое удержание остаются у строки: этот детектор ловит
          // только горизонтальное движение.
          onHorizontalDragUpdate: (d) => _update(d, width),
          onHorizontalDragEnd: (d) => _end(d, width),
          onHorizontalDragCancel: () => _animateTo(0, _snapBack),
          child: Stack(
            children: [
              if (panel != null)
                Positioned.fill(
                  child: _Panel(
                    panel: panel,
                    extent: _offset.abs(),
                    fromLeft: _offset > 0,
                    armed: _armed,
                  ),
                ),
              Transform.translate(
                offset: Offset(_offset, 0),
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Сама плашка: растёт от края вслед за пальцем, значок по её центру.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.panel,
    required this.extent,
    required this.fromLeft,
    required this.armed,
  });

  final SwipePanel panel;
  final double extent;
  final bool fromLeft;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    // Значок проявляется, когда плашке есть куда его положить, — иначе он
    // выползал бы обрезанным с первого же миллиметра движения.
    final show = ((extent - 16) / 40).clamp(0.0, 1.0);
    return Align(
      alignment: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: SizedBox(
        width: extent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.radius * 0.85),
          child: ColoredBox(
            color: panel.danger ? kSwipeDangerColor : t.pill,
            child: Center(
              child: Opacity(
                opacity: show,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 140),
                  scale: armed ? 1.15 : 1,
                  child: Icon(
                    panel.icon,
                    size: 22,
                    color: panel.danger ? Colors.white : t.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
