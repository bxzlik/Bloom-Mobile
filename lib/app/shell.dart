/// Каркас приложения: три таба, миниплеер над баром, полноэкранный плеер
/// поверх всего.
///
/// Бары непрозрачные и лежат в колонке под контентом, а не поверх него —
/// поэтому списку не нужен «фантомный» нижний отступ под миниплеер.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../features/player/ui/mini_player.dart';
import '../features/profile/achievements.dart';
import '../shared/ui/atoms.dart';
import '../shared/ui/bloom_toast.dart';
import '../shared/ui/cover_hero.dart';
import 'theme/tokens.dart';

class BloomShell extends ConsumerStatefulWidget {
  const BloomShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<BloomShell> createState() => _BloomShellState();
}

class _BloomShellState extends ConsumerState<BloomShell> {
  @override
  void initState() {
    super.initState();
    // Первый прогон — молчаливый: он же засеивает уже выполненные достижения.
    // Из `initState` провайдер трогать нельзя, ждём кадр.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  /// Достижения ловятся здесь, а не на вкладке профиля: иначе они «получались»
  /// бы только когда пользователь до неё дошёл (та же причина, по которой на
  /// десктопе вотчер живёт в `App`).
  void _sync() {
    final fresh = ref
        .read(unlockedAchievementsProvider.notifier)
        .sync(ref.read(achievementsProvider));
    // Тосты не налезают друг на друга: `ScaffoldMessenger` держит очередь и
    // показывает следующий, когда догорит предыдущий.
    for (final item in fresh) {
      ScaffoldMessenger.of(context).toast(
        '🏅 Достижение получено: ${item.ach.def.name} — ${tierLabel(item.tier)}',
        kind: ToastKind.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    ref.listen(achievementsProvider, (_, _) => _sync());
    final shell = widget.shell;
    return Scaffold(
      backgroundColor: t.bg,
      body: shell,
      // Бары именно в `bottomNavigationBar`, а не колонкой в `body`: только так
      // плавающий тост встаёт НАД миниплеером, а не поверх него. На раскладку
      // это не влияет — Scaffold точно так же отдаёт им низ, а телу остаток.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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

// ─── Переключение вкладок ───────────────────────────────────────────────────

/// Смена вкладки. Вдвое короче перехода страниц (450 мс): там шаг вглубь, а
/// здесь ответ на тап по бару — растворение должно успеть кончиться раньше,
/// чем палец дойдёт до следующего таба.
const Duration kTabTransition = Duration(milliseconds: 220);

/// Контейнер веток каркаса: вкладки сменяют друг друга растворением.
///
/// Готовый `StatefulShellRoute.indexedStack` меняет вкладку одним кадром —
/// здесь тот же `IndexedStack` по смыслу (все ветки живут в дереве,
/// `Offstage` + `TickerMode` у неактивных, состояние вкладки переживает
/// переключение), но на время перехода видно сразу две: уходящая гаснет,
/// приходящая проявляется.
///
/// Кривые — общие со страницами ([kPageFadeIn], [kPageFadeOut]), а вот
/// длительность своя, [kTabTransition]: страница уезжает в глубину, и ей
/// уместно идти степенно, а таб-бар отвечает под пальцем. Сдвига нет
/// намеренно — у вкладок нет общей оси, а под перелётом обложки горизонталь
/// спорила бы с ним (см. `detailPageTransition`).
class BranchCrossfade extends StatefulWidget {
  const BranchCrossfade({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<BranchCrossfade> createState() => _BranchCrossfadeState();
}

class _BranchCrossfadeState extends State<BranchCrossfade>
    with SingleTickerProviderStateMixin {
  // Стартует «догоревшим»: первый кадр приложения — вкладка уже на месте,
  // растворять нечего.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kTabTransition,
    value: 1,
  );

  /// Ветка, с которой ушли. Её ещё рисуют, пока не догорит [_fade].
  int _leaving = 0;

  @override
  void didUpdateWidget(BranchCrossfade old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      _leaving = old.index;
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Раскладка как у `IndexedStack`: свободные ограничения, выравнивание по
    // началу — ветка сама занимает отданное каркасом место.
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [for (var i = 0; i < widget.children.length; i++) _branch(i)],
      ),
    );
  }

  Widget _branch(int i) {
    final active = i == widget.index;
    final opacity = active
        ? kPageFadeIn.transform(_fade.value)
        : i == _leaving
        ? kPageFadeOut.transform(_fade.value)
        : 0.0;

    return Offstage(
      // Уходящая гаснет за первую четверть перехода — дальше её незачем
      // раскладывать и красить, хотя переход ещё идёт.
      offstage: opacity == 0,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          // `Opacity` при 1 не заводит слой — на покое это обычная ветка.
          child: Opacity(opacity: opacity, child: widget.children[i]),
        ),
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
