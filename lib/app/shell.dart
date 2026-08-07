/// Каркас приложения: три таба, миниплеер над баром, полноэкранный плеер
/// поверх всего.
///
/// Бары непрозрачные и лежат в колонке под контентом, а не поверх него —
/// поэтому списку не нужен «фантомный» нижний отступ под миниплеер.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../features/player/ui/mini_player.dart';
import '../shared/ui/atoms.dart';
import 'theme/tokens.dart';

class BloomShell extends StatelessWidget {
  const BloomShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Scaffold(
      backgroundColor: t.bg,
      body: Column(
        children: [
          Expanded(child: shell),
          const MiniPlayer(),
          _NavBar(
            index: shell.currentIndex,
            onTap: (i) =>
                shell.goBranch(i, initialLocation: i == shell.currentIndex),
          ),
        ],
      ),
    );
  }
}

/// Описание таба: пара «в покое / активный» — либо глифы Solar (outline+bold),
/// либо пара SVG для иконок, чей глиф в шрифте нарисован не тем.
class _NavSpec {
  const _NavSpec({
    required this.label,
    this.icon,
    this.activeIcon,
    this.svg,
    this.activeSvg,
  }) : assert(
         (icon != null && activeIcon != null) ||
             (svg != null && activeSvg != null),
         'у таба должна быть пара глифов или пара SVG',
       );

  final String label;
  final IconData? icon;
  final IconData? activeIcon;
  final String? svg;
  final String? activeSvg;
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  /// Неактивный таб — outline, активный — bold (правило Solar).
  ///
  /// У Библиотеки — настоящие Solar-SVG (те же файлы, что в anibloom): глиф
  /// `library` в шрифте залит сплошным ящиком, а у `folder` сверху справа
  /// торчит планка, которая в размере таба читается как «минус».
  static const _items = <_NavSpec>[
    _NavSpec(
      label: 'Главная',
      icon: SolarIconsOutline.homeAngle_2,
      activeIcon: SolarIconsBold.homeAngle_2,
    ),
    _NavSpec(
      label: 'Библиотека',
      svg: 'assets/icons/library-linear.svg',
      activeSvg: 'assets/icons/library-bold.svg',
    ),
    _NavSpec(
      label: 'Настройки',
      icon: SolarIconsOutline.settings,
      activeIcon: SolarIconsBold.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.ovlLine)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    spec: _items[i],
                    active: i == index,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  final _NavSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = active ? t.accent : t.iconFgSb;
    final glyph = active ? spec.activeIcon : spec.icon;
    final svg = active ? spec.activeSvg : spec.svg;

    return Semantics(
      button: true,
      selected: active,
      label: spec.label,
      // Без подложки и без ряби: активный таб отличается заливкой глифа
      // (bold вместо outline) и цветом акцента — этого достаточно, а
      // material-ripple на голом фоне читается как посторонний круг.
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: svg != null
              ? SvgIcon(svg, size: 24, color: color)
              : Icon(glyph, size: 24, color: color),
        ),
      ),
    );
  }
}
