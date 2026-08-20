/// Каркас приложения: три таба, миниплеер над баром, полноэкранный плеер
/// поверх всего.
///
/// Бары лежат поверх содержимого (`extendBody`), а не отрезают ему низ: поля
/// вокруг карточки миниплеера прозрачные, и сквозь них видно список. Цена —
/// каждому скроллу нужен нижний запас в высоту баров, иначе последние строки
/// остаются под ними навсегда: он берётся из [bottomBarsInset].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../core/l10n/l10n.dart';
import '../features/customization/ui/app_background.dart';
import '../core/store/settings_store.dart';
import '../features/player/ui/mini_player.dart';
import '../features/player/ui/player_sheet.dart';
import '../features/profile/achievements.dart';
import '../features/settings/about_store.dart';
import '../features/settings/update_notes_store.dart';
import '../features/settings/ui/update_notes_sheet.dart';
import '../shared/ui/atoms.dart';
import '../shared/ui/bloom_toast.dart';
import '../shared/ui/cover_hero.dart';
import '../shared/ui/glass.dart';
import 'nav_menu.dart';
import 'theme/tokens.dart';

class BloomShell extends ConsumerStatefulWidget {
  const BloomShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<BloomShell> createState() => _BloomShellState();
}

class _BloomShellState extends ConsumerState<BloomShell> {
  /// Панель таб-бара целиком. По её прямоугольнику меню таба находит, над чем
  /// встать и где вырезать дырку в затемнении (см. [showNavMenu]).
  final _panelKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Первый прогон — молчаливый: он же засеивает уже выполненные достижения.
    // Из `initState` провайдер трогать нельзя, ждём кадр.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync();
      _whatsNew();
    });
  }

  /// «Что нового» — один раз после обновления приложения.
  ///
  /// Здесь, а не на экране «Система»: сравнить версию с прошлым запуском надо
  /// при старте, и до настроек человек может не дойти вовсе. Мастер первого
  /// запуска этой шторке не помешает: он живёт отдельным маршрутом, каркас при
  /// нём не построен, а свежая установка «Что нового» и не показывает (см.
  /// `UpdateNotes.whatsNew`).
  Future<void> _whatsNew() async {
    await ref.read(aboutProvider.notifier).loadVersion();
    if (!mounted) return;
    final version = ref.read(aboutProvider).version;
    if (version.isEmpty) return;
    final locale = Localizations.localeOf(context).languageCode;
    final note = await ref.read(updateNotesProvider).whatsNew(version, locale);
    if (!mounted || note == null) return;
    await showUpdateNote(context, note);
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
        context.l.achUnlockedToast(
          item.ach.def.name(context.l),
          tierLabel(context.l, item.tier),
        ),
        kind: ToastKind.success,
      );
    }
  }

  /// Долгое нажатие по табу [index]: меню встаёт над панелью бара, [radius] —
  /// её скругление, по нему вырезается дырка в затемнении.
  void _openMenu(int index, BorderRadius radius) {
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    showNavMenu(
      host: context,
      ref: ref,
      index: index,
      panel: box.localToGlobal(Offset.zero) & box.size,
      panelRadius: radius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    ref.listen(achievementsProvider, (_, _) => _sync());
    final shell = widget.shell;
    final scaffold = Scaffold(
      // Картинка фона лежит под каркасом — тогда своей заливки у него нет.
      backgroundColor: ref.watch(backgroundOnProvider)
          ? Colors.transparent
          : t.bg,
      extendBody: true,
      body: shell,
      // Бары именно в `bottomNavigationBar`, а не колонкой в `body`: только так
      // плавающий тост встаёт НАД миниплеером, а не поверх него. На раскладку
      // это не влияет — Scaffold точно так же отдаёт им низ, а телу остаток.
      //
      // Группа стекла у баров СВОЯ, отдельная от страницы: они лежат поверх
      // списка, и с общим снимком подложки уходящие под них строки в размытие
      // бы не попали.
      bottomNavigationBar: GlassGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Место под карточку миниплеера: саму карточку рисует панель
            // плеера — она из карточки вырастает и лежит поверх баров.
            const MiniCardSlot(),
            _NavBar(
              style: ref.watch(settingsProvider).navStyle,
              index: shell.currentIndex,
              panelKey: _panelKey,
              onTap: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
              onLongPress: _openMenu,
            ),
          ],
        ),
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: playerSheetOpen,
      builder: (context, open, child) => PopScope(
        // Развёрнутый плеер съедает системную «назад». Своего маршрута у него
        // нет, и без этого «назад» ушла бы мимо: свернула бы страницу под
        // панелью или закрыла приложение, оставив плеер во весь экран.
        canPop: !open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) collapsePlayerSheet();
        },
        child: child!,
      ),
      // Панель лежит ПОВЕРХ каркаса вместе с барами: она и есть карточка
      // миниплеера, только выросшая, и накрывать таб-бар обязана сама.
      child: Stack(
        fit: StackFit.expand,
        children: [scaffold, const PlayerSheet()],
      ),
    );
  }
}

/// Высота панели таб-бара вместе с её нижним вырезом — столько занимает низ
/// экрана под карточкой миниплеера.
///
/// По ней панель плеера считает своё место в покое, поэтому число обязано
/// совпадать с тем, что бар раскладывает у себя (см. [_NavBar.build]): высота
/// ряда иконок плюс отступ, которым он выводит себя из системного выреза.
double navBarInset(BuildContext context, NavBarStyle style) => switch (style) {
  NavBarStyle.floating ||
  NavBarStyle.pill => kNavBarFloatHeight + bottomEdgeInset(context),
  _ => kNavBarHeight + bottomSafeInset(context),
};

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
    this.motion = _NavMotion.wiggle,
  }) : assert(
         (icon != null && activeIcon != null) ||
             (svg != null && activeSvg != null),
         'у таба должна быть пара глифов или пара SVG',
       );

  /// Подпись резолвится при отрисовке, а не при сборке списка: таблица табов
  /// статическая и переживает смену языка.
  final String Function(AppLocalizations l) label;
  final IconData? icon;
  final IconData? activeIcon;
  final String? svg;
  final String? activeSvg;

  /// Чем иконка отвечает на выбор своей вкладки — см. [_NavMotion].
  final _NavMotion motion;
}

/// Высота ряда иконок у прижатых к низу стилей.
const double kNavBarHeight = 58;

/// Высота плавающих стилей. Больше прижатых намеренно: панель кончается до
/// краёв экрана, и в тех же 58 она на фоне пустых полей вокруг читается
/// мельче, чем бар во всю ширину.
const double kNavBarFloatHeight = 68;

/// Размер глифа в баре. У плавающих крупнее — вслед за высотой панели, иначе
/// прибавка уходит в пустые поля над иконками и бар выглядит просто рыхлым.
const double _kNavIcon = 24;
const double _kNavFloatIcon = 27;

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.style,
    required this.index,
    required this.panelKey,
    required this.onTap,
    required this.onLongPress,
  });

  final NavBarStyle style;
  final int index;

  /// Ключ панели: по ней меню таба считает свою раскладку (см. [showNavMenu]).
  final Key panelKey;
  final ValueChanged<int> onTap;

  /// Долгое нажатие по табу. Вторым аргументом уходит скругление панели — оно
  /// зависит от стиля бара и известно только здесь.
  final void Function(int index, BorderRadius radius) onLongPress;

  /// Неактивный таб — outline, активный — bold (правило Solar).
  ///
  /// У Библиотеки — настоящие Solar-SVG (те же файлы, что в anibloom): глиф
  /// `library` в шрифте залит сплошным ящиком, а у `folder` сверху справа
  /// торчит планка, которая в размере таба читается как «минус».
  static final _items = <_NavSpec>[
    _NavSpec(
      label: (l) => l.navHome,
      icon: SolarIconsOutline.homeAngle_2,
      activeIcon: SolarIconsBold.homeAngle_2,
    ),
    _NavSpec(
      label: (l) => l.navLibrary,
      svg: 'assets/icons/library-linear.svg',
      activeSvg: 'assets/icons/library-bold.svg',
    ),
    _NavSpec(
      label: (l) => l.navSettings,
      icon: SolarIconsOutline.settings,
      activeIcon: SolarIconsBold.settings,
      motion: _NavMotion.spin,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final floating = style == NavBarStyle.floating || style == NavBarStyle.pill;
    final height = floating ? kNavBarFloatHeight : kNavBarHeight;

    // Прижатые стили отличаются друг от друга только радиусом верхних углов.
    // У «Купола» он вдвое больше темы и не мельче 28: на слабом радиусе темы он
    // иначе повторял бы «Скруглённый», ради которого его и заводили отдельным
    // видом.
    final topRadius = switch (style) {
      NavBarStyle.rounded => math.max(t.radius, 10.0),
      NavBarStyle.dome => math.max(t.radius * 2, 28.0),
      _ => 0.0,
    };
    // Форма панели целиком — она же форма дырки, которую меню таба вырезает в
    // своём затемнении.
    final radius = switch (style) {
      NavBarStyle.bar || NavBarStyle.rounded || NavBarStyle.dome =>
        BorderRadius.vertical(top: Radius.circular(topRadius)),
      // Капсула круглая по определению, а не по теме: её углы — всегда половина
      // высоты, что бы ни стояло в «Скруглениях».
      NavBarStyle.pill => BorderRadius.circular(height / 2),
      NavBarStyle.floating => BorderRadius.circular(t.radius),
    };

    // Ряд у всех стилей один: три таба делят ширину поровну. Капсула от
    // плавающей панели отличается только радиусом — иконки в ней стоят там
    // же, а не жмутся к середине.
    final row = Row(
      children: [
        for (var i = 0; i < _items.length; i++)
          Expanded(
            child: _NavItem(
              spec: _items[i],
              active: i == index,
              iconSize: floating ? _kNavFloatIcon : _kNavIcon,
              onTap: () => onTap(i),
              // У таба без меню долгого нажатия нет вовсе — иначе палец получал
              // бы отклик там, где ничего не откроется.
              onLongPress: navMenuHasContent(i)
                  ? () => onLongPress(i, radius)
                  : null,
            ),
          ),
      ],
    );

    switch (style) {
      // Прижатые к низу: заливка уходит под системный вырез, ряд иконок из
      // него выводит нижний отступ ([bottomSafeInset]).
      case NavBarStyle.bar:
      case NavBarStyle.rounded:
      case NavBarStyle.dome:
        final rounded = topRadius > 0;
        // Заливка одна на все четыре стиля — та же `pill`, что у шапки главной
        // и строк настроек: бары обязаны читаться как элементы интерфейса, а
        // не как продолжение фона. В стекле она полупрозрачна, и сквозь бар
        // видно уходящий под него список.
        return GlassBox(
          key: panelKey,
          // Не мельче 10 у «Скруглённого»: на нуле темы он ничем не
          // отличался бы от обычного.
          borderRadius: radius,
          // При скруглении рамка обязана быть одинаковой со всех сторон —
          // нижняя всё равно уходит за край экрана; у прямого бара линия
          // только сверху, поэтому ему нужна своя форма.
          borderSide: rounded ? BorderSide(color: t.ovlLine) : null,
          shape: rounded ? null : Border(top: BorderSide(color: t.ovlLine)),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomSafeInset(context)),
            child: SizedBox(height: height, child: row),
          ),
        );

      // Плавающие: панель кончается до низа экрана, вырез системы отдан
      // просвету под ней ([bottomEdgeInset]) — иначе она села бы на жестовую
      // полосу.
      case NavBarStyle.floating:
      case NavBarStyle.pill:
        return Padding(
          padding: EdgeInsets.fromLTRB(
            kFloatGap,
            0,
            kFloatGap,
            bottomEdgeInset(context),
          ),
          child: GlassBox(
            key: panelKey,
            borderSide: BorderSide(color: t.ovlLine),
            borderRadius: radius,
            child: SizedBox(height: height, child: row),
          ),
        );
    }
  }
}

// ─── Оживление иконок бара ──────────────────────────────────────────────────

/// Наплыв outline→bold и цвета. В такт со сменой самой вкладки
/// ([kTabTransition]): бар и содержимое обязаны идти одним темпом, иначе
/// заливка глифа договаривает уже поверх новой страницы.
const Duration kNavMorph = kTabTransition;

/// Чем иконка отвечает на выбор своей вкладки. Жест — свой на глиф, а не общий
/// на бар: одно и то же движение на всех трёх иконках выглядит как дёрганье
/// бара, а не как отклик конкретной.
enum _NavMotion {
  /// Качок вправо-влево с затуханием. Домик и ящик библиотеки стоят на
  /// «земле» — им идёт качнуться, как задетой вещи.
  wiggle,

  /// Оборот вокруг центра — шестерёнке настроек. Она круглая и симметричная:
  /// поворот на ней читается как вращение, а качок — как перекос.
  spin,
}

/// Отклик живёт отдельно от наплыва и заметно дольше него: это ответ под
/// пальцем, ему нормально догорать уже после того, как вкладка встала.
const Duration kNavWiggle = Duration(milliseconds: 380);
const Duration kNavSpin = Duration(milliseconds: 520);

/// Размах первого взмаха качка.
const double kWiggleMax = 9 * math.pi / 180;

/// Затухающий качок: три полувзмаха — вправо, влево, вправо. Взмахи даёт
/// синус, а множитель `(1 − t)` их гасит и ровно в конце обнуляет угол, так
/// что иконка успокаивается сама, а не сбрасывается в ноль рывком.
double _wiggleAngle(double t) =>
    kWiggleMax * math.sin(t * math.pi * 3) * (1 - t);

/// Оборот с выбегом: стартует быстро и тормозит к концу — шестерёнку будто
/// крутанули пальцем, а не провернули мотором. Полный круг, а не половина:
/// зубцы у неё частые, и на половине глаз не поймёт, что она вернулась.
double _spinAngle(double t) => 2 * math.pi * Curves.easeOutCubic.transform(t);

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.spec,
    required this.active,
    required this.iconSize,
    required this.onTap,
    required this.onLongPress,
  });

  final _NavSpec spec;
  final bool active;
  final double iconSize;
  final VoidCallback onTap;

  /// Меню таба. `null` — у этого таба меню нет.
  final VoidCallback? onLongPress;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with TickerProviderStateMixin {
  /// 0 — покой, 1 — активный таб. Стартует «доехавшим»: на первом кадре
  /// приложения наплывать неоткуда.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: kNavMorph,
    value: widget.active ? 1 : 0,
  );

  /// Жест иконки: качок или оборот, смотря по [_NavSpec.motion].
  late final AnimationController _react = AnimationController(
    vsync: this,
    duration: widget.spec.motion == _NavMotion.spin ? kNavSpin : kNavWiggle,
  );

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _morph.forward();
      _react.forward(from: 0);
    } else {
      _morph.reverse();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _react.dispose();
    super.dispose();
  }

  void _tap() {
    // Повторный тап по своей же вкладке не меняет `active` (и жеста из
    // `didUpdateWidget` не будет), но что-то делает — сбрасывает ветку в
    // корень. Отвечаем на него тем же жестом, иначе тап выглядит потерянным.
    if (widget.active) _react.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.spec.label(context.l),
      // Без подложки и без ряби: активный таб отличается заливкой глифа
      // (bold вместо outline) и цветом акцента — этого достаточно, а
      // material-ripple на голом фоне читается как посторонний круг.
      child: GestureDetector(
        onTap: _tap,
        // Вкладка при этом НЕ переключается: `onLongPress` и `onTap` у одного
        // распознавателя взаимоисключающие. Отклик пальцу даёт сама система —
        // короткая вибрация ровно в момент срабатывания жеста.
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                Feedback.forLongPress(context);
                widget.onLongPress!();
              },
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_morph, _react]),
            builder: (context, _) {
              // В покое контроллер стоит на 1 (жест доигран), и обе формы там
              // дают ту же картинку, что при 0: качок обнулён затуханием, а
              // оборот — это полный круг. Отдельного «покоя» заводить не надо.
              final angle = widget.spec.motion == _NavMotion.spin
                  ? _spinAngle(_react.value)
                  : _wiggleAngle(_react.value);
              return Transform.rotate(angle: angle, child: _icons(t));
            },
          ),
        ),
      ),
    );
  }

  /// Два слоя друг на друге: bold проявляется поверх outline.
  ///
  /// Кривые подобраны так, чтобы слои перекрывались, а не разошлись в
  /// середине: outline держится первую треть на полной непрозрачности и
  /// уходит, когда заливка уже набрала вес. Иначе на половине перехода
  /// суммарная альфа контура проседает и иконка на кадр тускнеет.
  Widget _icons(BloomTokens t) {
    final m = _morph.value;
    // Покой — полный контраст (`text`), а не приглушённый `iconFgSb`: в баре
    // всего три глифа, и тусклые они читаются как выключенные. Активный таб
    // и без разницы в яркости виден — по заливке и акценту.
    final color = Color.lerp(t.text, t.accent, m)!;
    final fill = Curves.easeOut.transform(m);
    final line = 1 - const Interval(0.35, 1).transform(m);
    final spec = widget.spec;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (line > 0) _layer(spec.icon, spec.svg, color, line),
        if (fill > 0) _layer(spec.activeIcon, spec.activeSvg, color, fill),
      ],
    );
  }

  Widget _layer(IconData? glyph, String? svg, Color color, double opacity) =>
      Opacity(
        opacity: opacity.clamp(0, 1),
        child: svg != null
            ? SvgIcon(svg, size: widget.iconSize, color: color)
            : Icon(glyph, size: widget.iconSize, color: color),
      );
}
