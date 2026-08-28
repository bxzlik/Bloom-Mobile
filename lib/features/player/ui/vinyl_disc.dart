/// Пластинка — вращение и этикетка. Порт `.ps-cover.vinyl-mode` с ПК.
///
/// Один вход на всех: и полноэкранный плеер, и превью в настройках берут
/// вращение и этикетку отсюда — иначе картинка в настройках со временем
/// разошлась бы с настоящей (та же беда, что у слайдера).
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// Вращение пластинки — порт `.ps-cover.vinyl-spin img`: 10 с на оборот,
/// линейно, без конца.
///
/// Пауза не отматывает диск в ноль: десктопное `animation-play-state:paused`
/// замирает на месте, и `repeat()` после `stop()` идёт с ТЕКУЩЕГО значения
/// контроллера — оборот продолжается с того же угла.
class VinylSpin extends StatefulWidget {
  const VinylSpin({
    super.key,
    required this.enabled,
    required this.spinning,
    required this.child,
    this.playing,
  });

  /// Пластинка на экране (выбран стиль «Пластинка»). Выключена — виджет пустая
  /// обёртка: заводить тикер обычному плееру незачем.
  final bool enabled;

  /// Крутится ли диск прямо сейчас. Для плеера это лишь ПЕРВЫЙ кадр — дальше
  /// состояние приезжает потоком [playing], который отдаёт значение не сразу.
  final bool spinning;

  /// Поток «идёт ли звук». `null` — крутить решает один [spinning] (превью в
  /// настройках: там звука нет вовсе).
  final Stream<bool>? playing;

  final Widget child;

  @override
  State<VinylSpin> createState() => _VinylSpinState();
}

class _VinylSpinState extends State<VinylSpin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(VinylSpin old) {
    super.didUpdateWidget(old);
    if (widget.enabled != old.enabled ||
        widget.spinning != old.spinning ||
        widget.playing != old.playing) {
      _listen();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _turn.dispose();
    super.dispose();
  }

  /// Подписка на плеер. Диск выключили — гасим и её, и тикер: крутить кадры
  /// вхолостую обычному плееру незачем.
  void _listen() {
    _sub?.cancel();
    _sub = null;
    if (!widget.enabled) {
      _apply(false);
      return;
    }
    _apply(widget.spinning);
    final playing = widget.playing;
    if (playing != null) _sub = playing.listen(_apply);
  }

  void _apply(bool spinning) {
    if (!mounted || spinning == _turn.isAnimating) return;
    if (spinning) {
      _turn.repeat();
    } else {
      _turn.stop(canceled: false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.enabled
      ? RotationTransition(turns: _turn, child: widget.child)
      : widget.child;
}

/// Этикетка в середине пластинки — порт `.ps-cover.vinyl-mode::after`: тёмный
/// кружок с тонким светлым кольцом у своего края.
///
/// Кольцо белое, а не «плёнкой темы», как на ПК (`rgba(var(--ovl-rgb),.1)`): на
/// светлой теме плёнка там чёрная, и на почти чёрной этикетке кольца просто не
/// было бы видно.
class VinylLabel extends StatelessWidget {
  const VinylLabel({super.key, required this.size});

  /// Диаметр этикетки. На ПК это 22% диаметра диска.
  final double size;

  /// Доля диаметра диска, которую занимает этикетка (`width:22%`).
  static const double share = 0.22;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          // Доли те же, что в CSS, но там они меряются от центра до ДАЛЬНЕГО
          // УГЛА коробки (умолчание `radial-gradient`), а у Flutter радиус —
          // доля ширины. Отсюда 0.707: половина диагонали квадрата.
          radius: 0.707,
          colors: [
            Color(0xFF111111),
            Color(0xFF222222),
            Color(0x1AFFFFFF),
            Color(0x08FFFFFF),
            Color(0xFF1A1A1A),
          ],
          stops: [0.30, 0.58, 0.60, 0.62, 0.64],
        ),
      ),
    ),
  );
}
