/// Шапка страницы, которая при прокрутке не уезжает целиком.
///
/// Обложка, название и ряд действий уходят вверх как обычное содержимое, а ряд
/// круглых кнопок (назад, сортировка, поиск, «…») остаётся приклеенным к
/// верхнему краю: на длинном трек-листе иначе некуда нажать, не пролистав всё
/// обратно.
///
/// Сжатая шапка — это верхняя полоска той же обложки, поэтому кнопки всё так же
/// стоят на картинке, а не на плоской панели.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'cover_hero.dart';

class StickyHero extends StatelessWidget {
  const StickyHero({
    super.key,
    required this.height,
    required this.background,
    required this.bar,
    required this.barHeight,
    required this.body,
    this.flying = false,
  });

  /// Полная высота шапки — та же, что была у нераскрытого hero.
  final double height;

  /// Картинка на всю шапку: обложка, коллаж или тинт раздела.
  final Widget background;

  /// Ряд кнопок, который остаётся видимым при прокрутке.
  final Widget bar;

  /// Высота этого ряда — по ней считается сжатая шапка. Не берётся из вёрстки:
  /// слайверу минимальный размер нужен до раскладки ребёнка.
  final double barHeight;

  /// Название, подписи и ряд действий — низ шапки, который уезжает.
  final Widget body;

  /// Сюда летит обложка с карточки: содержимое ждёт конца перелёта.
  final bool flying;

  /// Отступы содержимого шапки — общие у всех страниц с hero.
  static const double _side = 16;
  static const double _barTop = 10;
  static const double _barBottom = 10;
  static const double _bodyBottom = 12;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyHeroDelegate(
        height: height,
        top: MediaQuery.paddingOf(context).top,
        radius: context.bloom.radius * 1.5,
        background: background,
        bar: bar,
        barHeight: barHeight,
        body: body,
        flying: flying,
      ),
    );
  }
}

class _StickyHeroDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeroDelegate({
    required this.height,
    required this.top,
    required this.radius,
    required this.background,
    required this.bar,
    required this.barHeight,
    required this.body,
    required this.flying,
  });

  final double height;

  /// Системная строка: кнопки стоят под ней и в сжатой шапке.
  final double top;

  final double radius;
  final Widget background;
  final Widget bar;
  final double barHeight;
  final Widget body;
  final bool flying;

  @override
  double get maxExtent => math.max(height, minExtent);

  @override
  double get minExtent =>
      top + StickyHero._barTop + barHeight + StickyHero._barBottom;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final extent = math.max(minExtent, maxExtent - shrinkOffset);
    final collapse = ((maxExtent - extent) / (maxExtent - minExtent)).clamp(
      0.0,
      1.0,
    );
    // Название и ряд действий гаснут только на последней трети пути: раньше
    // они ещё стоят на своих местах, и гасить там нечего.
    final fade = (1 - (collapse - 0.55) / 0.45).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Обложка с подписями уезжает вверх целиком, как обычное содержимое:
          // в сжатой шапке остаётся её нижняя, самая затемнённая полоска — на
          // ней белые кнопки читаются с любой картинкой.
          Positioned(
            top: extent - maxExtent,
            left: 0,
            right: 0,
            height: maxExtent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                background,
                Positioned(
                  left: StickyHero._side,
                  right: StickyHero._side,
                  bottom: StickyHero._bodyBottom,
                  // Погасшее содержимое стоит ровно под рядом кнопок и осталось
                  // бы нажимаемым: невидимая «Воспроизвести» под «назад» — это
                  // случайный запуск списка.
                  child: IgnorePointer(
                    ignoring: fade == 0,
                    child: Opacity(
                      opacity: fade,
                      child: HeroContent(flying: flying, child: body),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: top + StickyHero._barTop,
            left: StickyHero._side,
            right: StickyHero._side,
            child: HeroContent(flying: flying, child: bar),
          ),
        ],
      ),
    );
  }

  /// Содержимое приходит уже собранным (у страниц свои кнопки и подписи), и
  /// сравнивать его нечем — перестраиваем всегда.
  @override
  bool shouldRebuild(_StickyHeroDelegate old) => true;
}
