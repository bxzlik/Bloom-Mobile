/// Полноэкранный плеер. Раскладка — по референсу: шапка (свернуть / «Играет
/// из» / меню), большая обложка с ♡ и ⊕ поверх неё, название и артист по
/// центру, прогресс, транспорт отдельным блоком, под ним ряд инструментов.
///
/// Вид (цвета, плёнки, радиус) — токены десктопного Bloom.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/util/format.dart';
import '../player_controller.dart';
import 'queue_sheet.dart';

/// Радиус обложки в плеере — заметно круглее блоков (как в референсе).
const double _coverRadius = 20;

/// Открыть плеер: выезд снизу.
void openFullPlayer(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const FullPlayerPage(),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    ),
  );
}

class FullPlayerPage extends ConsumerWidget {
  const FullPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final track = state.track;

    return Scaffold(
      backgroundColor: t.bg,
      body: GestureDetector(
        // Свайп вниз по всему экрану — закрыть, как в референсе.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 260) Navigator.of(context).maybePop();
        },
        child: SafeArea(
          child: track == null
              ? const SizedBox.shrink()
              : Padding(
                  // Сверху воздух: шапка не должна липнуть к статус-бару.
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    children: [
                      _Header(track: track),
                      const SizedBox(height: 16),
                      // Обложка по центру свободного места.
                      Flexible(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _Cover(state: state),
                          ),
                        ),
                      ),
                      // Отступы вокруг названия одинаковые: оно должно стоять
                      // ровно посередине между обложкой и прогрессом.
                      const SizedBox(height: 24),
                      _TitleBlock(state: state),
                      const SizedBox(height: 24),
                      const _Progress(),
                      const SizedBox(height: 16),
                      const _Transport(),
                      const SizedBox(height: 12),
                      _Tools(queueCount: state.queue.length),
                      // Воздух до края экрана: вся связка прогресс — транспорт
                      // — инструменты стоит выше кромки, обложка подожмётся
                      // сама (она во `Flexible`).
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.track});

  /// Текущий трек: его площадка стоит в пилюле «Играет из», он же уходит в
  /// меню под тремя точками.
  final Track track;

  /// Пилюля «Играет из» — та же плёнка, что у круглых кнопок по краям, только
  /// чуть ниже них: в шапке она подпись, а не орган управления.
  static const double _pillHeight = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    return Row(
      children: [
        CircleIconButton(
          icon: SolarIconsOutline.altArrowDown,
          iconSize: 22,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Center(
            child: Container(
              height: _pillHeight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: t.pill,
                borderRadius: BorderRadius.circular(_pillHeight / 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Играет из',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 7),
                  // Логотип площадки — тот же SVG, что на десктопе; берётся из
                  // самого трека, поэтому переключение площадок ничего тут не
                  // потребует.
                  PlatformLogo(track.source, size: 15),
                ],
              ),
            ),
          ),
        ),
        CircleIconButton(
          icon: SolarIconsOutline.menuDots,
          onTap: () => showTrackActions(context, ref, track),
        ),
      ],
    );
  }
}

class _Cover extends ConsumerWidget {
  const _Cover({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.track!;
    final isFav = ref.watch(libraryProvider).isFav(track.id);
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.biggest.shortestSide;
        return Stack(
          children: [
            Cover(url: track.cover, size: side, radius: _coverRadius),
            Positioned(
              left: 16,
              bottom: 16,
              child: _CoverButton(
                icon: isFav ? SolarIconsBold.heart : SolarIconsOutline.heart,
                color: isFav ? const Color(0xFFFF5578) : Colors.white,
                onTap: () =>
                    ref.read(libraryProvider.notifier).toggleFav(track),
              ),
            ),
            // Именно addCircle, а не plus: в solar_icons 0.1.0 `plus` и `minus`
            // сидят на одном коде 0xec4a и рисуются знаком «±» из
            // калькуляторной группы. В референсе тут и так ⊕.
            Positioned(
              right: 16,
              bottom: 16,
              child: _CoverButton(
                icon: SolarIconsOutline.addCircle,
                iconSize: 28,
                onTap: () => showAddToPlaylistSheet(context, ref, track),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Кнопка НА ОБЛОЖКЕ: подложка честно чёрная, штрих белый — под ней всегда
/// картинка, а не поверхность темы. Тонкая светлая рамка нужна, чтобы кружок
/// читался и на почти чёрной обложке, где одной заливки не видно.
class _CoverButton extends StatelessWidget {
  const _CoverButton({
    required this.icon,
    this.iconSize = 26,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: CircleIconButton(
        icon: icon,
        iconSize: iconSize,
        size: 56,
        background: Colors.black.withValues(alpha: 0.45),
        color: color ?? Colors.white,
        onTap: onTap,
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final track = state.track!;
    final theme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          track.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.headlineSmall,
        ),
        const SizedBox(height: 5),
        Text(
          state.error ?? track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          // Крупнее общей подписи (13): в плеере под названием стоит одна
          // строка, и она должна читаться с руки.
          style: theme.bodyMedium?.copyWith(
            fontSize: 16,
            color: state.error != null ? t.sysFavIco : null,
          ),
        ),
      ],
    );
  }
}

class _Progress extends ConsumerStatefulWidget {
  const _Progress();

  @override
  ConsumerState<_Progress> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<_Progress> {
  /// Позиция под пальцем, пока тянут (мс). Пока она не null — дорожка и время
  /// слева живут от неё, а не от плеера.
  ///
  /// Иначе `Slider` (он управляемый) рисует то, что пришло из стрима, и
  /// заливка отпрыгивает назад к фактической позиции — резинка. Перематываем
  /// один раз, на отпускании: seek по сетевому стриму дорогой, а на каждый
  /// кадр перетаскивания их набегают десятки.
  double? _drag;

  Future<void> _commit(double v) async {
    await ref
        .read(playbackProvider.notifier)
        .seek(Duration(milliseconds: v.round()));
    // Отпускаем только после самой перемотки: до неё стрим отдаёт ещё старую
    // позицию, и полоска моргнула бы назад.
    if (mounted) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final head =
        ref.watch(playheadProvider).value ??
        (position: Duration.zero, total: Duration.zero);

    final max = head.total.inMilliseconds.toDouble();
    final live = max <= 0
        ? 0.0
        : head.position.inMilliseconds
              .clamp(0, head.total.inMilliseconds)
              .toDouble();
    final value = (_drag ?? live).clamp(0.0, max <= 0 ? 0.0 : max);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const RoundedRectSliderTrackShape(),
            // Дорожка в плеере толще общей (3): это главный орган
            // управления экрана, а не строка настройки.
            trackHeight: 5,
            // Без кружка — как в референсе: позицию показывает сам край
            // залитой части. Тянуть и тыкать по дорожке это не мешает.
            thumbShape: SliderComponentShape.noThumb,
          ),
          child: Slider(
            value: value,
            max: max <= 0 ? 1 : max,
            onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
            onChangeEnd: max <= 0 ? null : _commit,
          ),
        ),
        // Слайдер рисует дорожку по центру своей высоты, но времена всё
        // равно шли впритык к ней — отодвигаем их явно.
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Тем же цветом, что артист под названием (`bodyMedium`).
              Text(
                mmss(Duration(milliseconds: value.round())),
                style: theme.bodyMedium,
              ),
              Text(mmss(head.total), style: theme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

/// Блок-контейнер: плёнка + рамка + радиус темы.
class _Block extends StatelessWidget {
  const _Block({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: t.ovlBg,
        border: Border.all(color: t.ovlLine),
        // Круглее общего блока: у транспорта углы мягче, чем у карточек.
        borderRadius: BorderRadius.circular(t.radius * 1.8),
      ),
      child: child,
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final ctrl = ref.read(playbackProvider.notifier);
    final player = ref.watch(audioPlayerProvider);

    // Режим повтора различаем бейджем, а не подменой иконки (как на ПК): сама
    // кнопка всегда repeat, сверху справа — «список» для всей очереди и «1» для
    // одного трека.
    final repeatMark = switch (state.repeat) {
      PlayerRepeat.all => Icon(
        SolarIconsOutline.list,
        size: 9,
        color: t.accentText,
      ),
      PlayerRepeat.one => Text(
        '1',
        style: TextStyle(
          fontSize: 8,
          // Цифра оптически сидит выше центра — прижимаем высотой строки.
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: t.accentText,
        ),
      ),
      _ => null,
    };

    return _Block(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _FlatIcon(
            icon: SolarIconsOutline.repeat,
            size: 24,
            active: state.repeat != PlayerRepeat.off,
            onTap: ctrl.cycleRepeat,
            mark: repeatMark,
          ),
          _FlatIcon(
            icon: SolarIconsBold.skipPrevious,
            size: 30,
            onTap: ctrl.prev,
          ),
          SizedBox(
            width: 68,
            height: 68,
            // На загрузке круг ОСТАЁТСЯ на месте, спиннер рисуется внутри него:
            // иначе транспорт на каждом переходе трека визуально схлопывается.
            child: state.loading
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: t.accentText,
                        ),
                      ),
                    ),
                  )
                : StreamBuilder<bool>(
                    stream: player.playingStream,
                    initialData: player.playing,
                    builder: (context, snap) => Material(
                      color: t.accent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: ctrl.toggle,
                        child: Icon(
                          snap.data == true
                              ? SolarIconsBold.pause
                              : SolarIconsBold.play,
                          size: 28,
                          color: t.accentText,
                        ),
                      ),
                    ),
                  ),
          ),
          _FlatIcon(icon: SolarIconsBold.skipNext, size: 30, onTap: ctrl.next),
          _FlatIcon(
            icon: SolarIconsOutline.shuffle,
            size: 24,
            active: state.shuffle,
            onTap: ctrl.toggleShuffle,
          ),
        ],
      ),
    );
  }
}

class _FlatIcon extends StatelessWidget {
  const _FlatIcon({
    required this.icon,
    this.onTap,
    this.size = 22,
    this.active = false,
    this.badge,
    this.mark,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool active;
  final int? badge;

  /// Мини-бейдж в кружке акцента поверх иконки (перенос .cc-badge с ПК): им
  /// различаем режимы кнопки, чтобы не подменять саму иконку.
  final Widget? mark;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: size, color: active ? t.accent : t.iconFg),
            if (badge != null)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: t.accentText,
                    ),
                  ),
                ),
              ),
            if (mark != null)
              Positioned(
                right: -4,
                top: -3,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: mark,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tools extends StatelessWidget {
  const _Tools({required this.queueCount});

  final int queueCount;

  @override
  Widget build(BuildContext context) {
    return _Block(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const _FlatIcon(icon: SolarIconsOutline.text, size: 26),
          const _FlatIcon(icon: SolarIconsOutline.tuning, size: 26),
          const _FlatIcon(icon: SolarIconsOutline.speedometerMiddle, size: 26),
          _FlatIcon(
            icon: SolarIconsOutline.playlistMinimalistic,
            size: 26,
            badge: queueCount > 0 ? queueCount : null,
            onTap: queueCount > 0 ? () => showQueueSheet(context) : null,
          ),
        ],
      ),
    );
  }
}
