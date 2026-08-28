/// Бегущая строка длинного названия — порт десктопного `MarqueeTitle.tsx`.
///
/// Схема ровно как на ПК: меряем строку и сравниваем с шириной обёртки; шире
/// больше чем на 4 px — рисуем «текст + зазор + текст» и катим влево ровно на
/// `текст + зазор`, после чего вторая копия оказывается на месте первой и цикл
/// повторяется без стыка. Скорость постоянная (55 px/s, `@keyframes ps-marquee`
/// + `duration = max(4, шаг/55)`), но цикл не короче 4 s — иначе короткие
/// названия дёргаются.
///
/// Влезает — обычный `Text` с эллипсисом: ни таймера, ни лишних перерисовок.
/// Пауза по ховеру с ПК не переносится — наводить на телефоне нечем.
library;

import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.align = TextAlign.start,
    this.gap = 64,
    this.speed = 55,
  });

  final String text;
  final TextStyle? style;

  /// Выравнивание, ПОКА строка влезает. Когда катится — всегда от левого края,
  /// как десктопное `.title-wrap.scrolling{justify-content:flex-start}`.
  final TextAlign align;

  /// Зазор между копиями текста, px.
  final double gap;

  /// Скорость прокрутки, px/s.
  final double speed;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Запустить цикл нужной длины или остановить его. Зовётся из `build`, где
  /// известна ширина, поэтому саму правку контроллера откладываем на конец
  /// кадра — трогать анимацию посреди раскладки нельзя.
  void _sync(Duration? duration) {
    if (_c.duration == duration && _c.isAnimating == (duration != null)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.duration = duration;
      if (duration == null) {
        _c
          ..stop()
          ..value = 0;
      } else {
        _c.repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        )..layout();
        final width = painter.width;
        final height = painter.height;
        final maxWidth = constraints.maxWidth;

        // Порог тот же, что на ПК: пара пикселей разницы — это округление
        // измерителя, а не переполнение.
        if (!maxWidth.isFinite || width <= maxWidth + 4) {
          _sync(null);
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.align,
            style: widget.style,
          );
        }

        final step = width + widget.gap;
        final seconds = (step / widget.speed).round();
        _sync(Duration(seconds: seconds < 4 ? 4 : seconds));

        // Копии стоят в `Stack`, а не в `Row`: `Positioned` с явной шириной
        // уходит за границу родителя, а строка в `Row` получила бы ограничение
        // по ширине обёртки и снова обрезалась бы эллипсисом.
        final line = Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        );
        return SizedBox(
          width: maxWidth,
          height: height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final dx = -_c.value * step;
                return Stack(
                  children: [
                    Positioned(left: dx, top: 0, width: width, child: child!),
                    Positioned(
                      left: dx + step,
                      top: 0,
                      width: width,
                      child: child,
                    ),
                  ],
                );
              },
              child: line,
            ),
          ),
        );
      },
    );
  }
}
