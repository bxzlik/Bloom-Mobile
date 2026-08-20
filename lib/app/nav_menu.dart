/// Меню таба — попап по долгому нажатию на иконку нижнего бара.
///
/// Не шторка: жест начинается у самого бара, и ответ обязан вырасти прямо над
/// пальцем, а не приехать снизу из-под него. Отсюда и вся геометрия — карточка
/// стоит НАД панелью бара и раскрывается из центра своего таба.
///
/// Затемнение с дыркой: сама панель бара остаётся в полном цвете, темнеет и
/// размывается только страница над ней. Барьер при этом всё равно во весь
/// экран — тап по бару под дыркой закрывает меню, а не переключает вкладку.
///
/// Пункты — шорткаты к тому, что и так есть на вкладке, а не вторая навигация:
/// у главной — запуск волны, продолжение и поиск, у библиотеки — создание
/// плейлиста и сами плейлисты. У настроек меню нет (его слово), поэтому
/// долгое нажатие по третьему табу ничего не открывает.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../core/entities/entities.dart';
import '../core/l10n/l10n.dart';
import '../core/store/library_store.dart';
import '../features/library/lib_order_store.dart';
import '../features/library/ui/create_playlist_sheet.dart';
import '../features/player/player_controller.dart';
import '../features/player/resume_store.dart';
import '../features/settings/transparency_store.dart';
import '../features/wave/wave_actions.dart';
import '../shared/ui/atoms.dart';
import '../shared/ui/glass.dart';
import 'theme/tokens.dart';

/// Раскрытие меню. Длиннее смены вкладки (220 мс): там ответ на тап, а тут
/// палец уже полсекунды держит бар — рывок в один кадр выглядел бы испугом.
const Duration kNavMenuIn = Duration(milliseconds: 200);

/// Закрытие — заметно быстрее: меню уходит, потому что своё дело сделало.
const Duration kNavMenuOut = Duration(milliseconds: 140);

/// Просвет между панелью бара и карточкой меню.
const double _kGap = 10;

/// Поля меню от краёв экрана — те же, что у плавающих стилей бара.
const double _kMargin = kFloatGap * 2;

/// Ширина карточки. Фиксированная, а не по содержимому: из неё считается точка,
/// из которой меню раскрывается, и «поедет» она уже после первого кадра.
const double _kWidth = 268;

/// Есть ли у таба [index] меню. Бар спрашивает заранее: у таба без меню
/// долгого нажатия нет вовсе, иначе палец получал бы отклик впустую.
bool navMenuHasContent(int index) => index == 0 || index == 1;

/// Открыть меню таба [index] над панелью бара [panel].
///
/// [host] — контекст каркаса, а не меню: пункт срабатывает уже ПОСЛЕ закрытия
/// попапа, и его собственный контекст к этому моменту мёртв. По той же причине
/// приходит и [ref] каркаса.
///
/// [panelRadius] — скругление панели: по нему вырезается дырка в затемнении,
/// иначе у скруглённых стилей по углам бара оставались бы тёмные уголки.
Future<void> showNavMenu({
  required BuildContext host,
  required WidgetRef ref,
  required int index,
  required Rect panel,
  required BorderRadius panelRadius,
}) {
  final content = switch (index) {
    0 => _HomeMenu(host: host, hostRef: ref),
    1 => _LibraryMenu(host: host, hostRef: ref),
    // Настройки: меню нет — тогда и попапа нет, жест просто ничего не делает.
    _ => null,
  };
  if (content == null) return Future<void>.value();

  final navigator = Navigator.of(host, rootNavigator: true);
  return navigator.push(
    _NavMenuRoute(
      panel: panel,
      panelRadius: panelRadius,
      // Таб-бар делит панель на равные доли — по ним и находится центр иконки,
      // не спрашивая каждый таб о его прямоугольнике.
      centerX: panel.left + panel.width * (index + 0.5) / 3,
      barrierLabel: MaterialLocalizations.of(
        host,
      ).modalBarrierDismissLabel,
      // Как у шторок: попап строится в оверлее корневого навигатора, и всё, что
      // объявлено ниже него, иначе потерялось бы.
      themes: InheritedTheme.capture(from: host, to: navigator.context),
      child: content,
    ),
  );
}

class _NavMenuRoute extends PopupRoute<void> {
  _NavMenuRoute({
    required this.panel,
    required this.panelRadius,
    required this.centerX,
    required this.barrierLabel,
    required this.themes,
    required this.child,
  });

  final Rect panel;
  final BorderRadius panelRadius;
  final double centerX;
  final CapturedThemes themes;
  final Widget child;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  /// Затемнение своё ([_Scrim]) — барьеру красить нечего: ему нужна дырка под
  /// панелью бара, а цветом барьера её не вырезать.
  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => kNavMenuIn;

  @override
  Duration get reverseTransitionDuration => kNavMenuOut;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
  ) => themes.wrap(
    _NavMenuLayer(
      panel: panel,
      panelRadius: panelRadius,
      centerX: centerX,
      animation: animation,
      child: child,
    ),
  );
}

/// Раскладка попапа: затемнение с дыркой и сама карточка над баром.
class _NavMenuLayer extends StatelessWidget {
  const _NavMenuLayer({
    required this.panel,
    required this.panelRadius,
    required this.centerX,
    required this.animation,
    required this.child,
  });

  final Rect panel;
  final BorderRadius panelRadius;
  final double centerX;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final media = MediaQuery.of(context);
    final screen = media.size;

    final width = math.min(_kWidth, screen.width - _kMargin * 2);
    // Меню тянется к своему табу, но за поля экрана не выходит: у крайних табов
    // оно упирается в край, как папки в референсе.
    final left = (centerX - width / 2)
        .clamp(_kMargin, math.max(_kMargin, screen.width - _kMargin - width))
        .toDouble();
    // Потолок высоты — до системного выреза сверху: длинный список плейлистов
    // обязан скроллиться внутри карточки, а не лезть в статус-бар.
    final maxHeight = math.max(
      120.0,
      panel.top - _kGap - media.padding.top - _kMargin,
    );
    // Точка раскрытия: низ карточки в том месте, где стоит иконка таба.
    final originX = (((centerX - left) / width) * 2 - 1)
        .clamp(-1.0, 1.0)
        .toDouble();

    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.55),
      reverseCurve: Curves.easeIn,
    );
    final grow = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );

    return Stack(
      children: [
        // Затемнение не ловит нажатия: за них отвечает барьер маршрута — иначе
        // тап по дырке уходил бы в живой таб-бар под ней.
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: fade,
              child: _Scrim(hole: panel, radius: panelRadius),
            ),
          ),
        ),
        Positioned(
          left: left,
          width: width,
          bottom: screen.height - panel.top + _kGap,
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(grow),
              alignment: Alignment(originX, 1),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                // Своя группа стекла: карточка лежит поверх страницы, и снимок
                // подложки ей нужен свой (см. `GlassGroup`).
                child: GlassGroup(
                  child: GlassBox(
                    overlay: true,
                    borderRadius: BorderRadius.circular(
                      math.max(t.radius * 1.4, 16),
                    ),
                    borderSide: BorderSide(color: t.ovlLine),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Затемнение страницы с дыркой под панелью бара.
///
/// Сила — та же, что у шторок: при включённой прозрачности оверлеев страница не
/// просто темнеет, а размывается, и плёнка тогда светлее (под тёмной размытия
/// всё равно не видно).
class _Scrim extends ConsumerWidget {
  const _Scrim({required this.hole, required this.radius});

  final Rect hole;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = ref.watch(overlayGlassProvider);
    final Widget dim = ColoredBox(
      color: Colors.black.withValues(alpha: glass == null ? 0.5 : 0.28),
    );
    final filter = glass?.filter;
    return ClipPath(
      clipper: _HoleClipper(hole: hole, radius: radius),
      child: filter == null
          ? dim
          : BackdropFilter(filter: filter, child: dim),
    );
  }
}

class _HoleClipper extends CustomClipper<Path> {
  const _HoleClipper({required this.hole, required this.radius});

  final Rect hole;
  final BorderRadius radius;

  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.difference,
    Path()..addRect(Offset.zero & size),
    Path()..addRRect(radius.toRRect(hole)),
  );

  @override
  bool shouldReclip(_HoleClipper old) =>
      old.hole != hole || old.radius != radius;
}

// ─── Содержимое меню ────────────────────────────────────────────────────────

/// Главная: волна, продолжение и поиск.
class _HomeMenu extends ConsumerWidget {
  const _HomeMenu({required this.host, required this.hostRef});

  final BuildContext host;
  final WidgetRef hostRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final track = ref.watch(playbackProvider.select((s) => s.track));
    final playing = ref.watch(playingProvider).value ?? false;
    // Снимок прошлой сессии нужен, только пока живого трека нет — ровно то же
    // условие, что у карточки «Продолжить» на главной.
    final resume = track == null ? ref.watch(resumeProvider) : null;

    // Продолжать нечего — пункта нет: играющий трек продолжать не надо, а до
    // первого запуска и продолжать не с чего.
    final Track? paused = track != null && !playing ? track : resume?.track;

    return _Panel(
      children: [
        _Row(
          icon: SolarIconsBold.soundwave,
          label: l.waveTitle,
          onTap: () => startPersonalWave(host, hostRef),
        ),
        if (paused != null)
          _Row(
            icon: SolarIconsBold.play,
            label: l.commonContinue,
            // Подпись — имя трека: иначе непонятно, что именно продолжится.
            sub: paused.name,
            onTap: () {
              final player = hostRef.read(playbackProvider.notifier);
              if (resume != null) {
                player.resumeSession(resume);
              } else {
                player.toggle();
              }
            },
          ),
        _Row(
          icon: SolarIconsOutline.magnifier,
          label: l.searchHint,
          onTap: () => host.go('/home/search'),
        ),
      ],
    );
  }
}

/// Библиотека: создание плейлиста и сами плейлисты — с обложками, как папки в
/// референсе. Порядок тот же, что на вкладке: закреплённые сверху.
class _LibraryMenu extends ConsumerWidget {
  const _LibraryMenu({required this.host, required this.hostRef});

  final BuildContext host;
  final WidgetRef hostRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final playlists = ref
        .watch(libOrderProvider)
        .arrange(
          lib.playlists,
          key: (pl) => libKeyOfPlaylist(pl.id),
          name: (pl) => pl.name,
          rank: (_) => kLibRankPlaylist,
        );

    return _Panel(
      children: [
        _Row(
          icon: SolarIconsOutline.addCircle,
          label: context.l.commonCreatePlaylist,
          onTap: () => showCreatePlaylistSheet(host, hostRef),
        ),
        if (playlists.isNotEmpty) ...[
          const _Line(),
          // `Flexible` + `shrinkWrap`: пока плейлистов мало, карточка ровно по
          // ним, а дальше список упирается в потолок высоты и листается сам.
          Flexible(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, i) {
                final pl = playlists[i];
                return _Row(
                  leading: Cover(
                    url: pl.cover,
                    size: _kCover,
                    radius: context.bloom.radius * 0.7,
                    // Своей обложки нет — коллаж из треков, как на плитке
                    // библиотеки.
                    covers: lib.tracksOf(pl).map((track) => track.cover),
                  ),
                  label: pl.name,
                  sub: context.l.tracksCount(pl.trackIds.length),
                  onTap: () => host.go('/library/list/${pl.id}'),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Строки меню ────────────────────────────────────────────────────────────

/// Размер обложки плейлиста в строке. Держится за высоту строки: крупнее —
/// и список плейлистов перестаёт читаться как меню.
const double _kCover = 34;

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

/// Разделитель между блоками меню. Во всю ширину, а не от текста, как в
/// шторках: он делит блоки, а не пункты одного блока.
class _Line extends StatelessWidget {
  const _Line();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.bloom.ovlLine);
}

/// Пункт меню. Слева — глиф [icon] или своя картинка [leading] (обложка
/// плейлиста), справа — название и необязательная подпись.
class _Row extends StatelessWidget {
  const _Row({
    this.icon,
    this.leading,
    required this.label,
    this.sub,
    required this.onTap,
  }) : assert(icon != null || leading != null, 'пункту нужен значок');

  final IconData? icon;
  final Widget? leading;
  final String label;
  final String? sub;

  /// Меню закрывается ДО действия: почти каждый пункт уводит на другую вкладку
  /// или открывает шторку, и делать это из-под попапа нельзя.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            // Колонка значков одной ширины: глиф мельче обложки, и без общего
            // бокса подписи в списке разъезжались бы по левому краю.
            SizedBox(
              width: _kCover,
              height: _kCover,
              child: leading ?? Icon(icon, size: 22, color: t.text),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleSmall,
                  ),
                  if (sub case final text?) ...[
                    const SizedBox(height: 1),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
