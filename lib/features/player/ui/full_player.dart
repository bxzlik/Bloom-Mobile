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
                      _Header(source: track.source),
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
                      const SizedBox(height: 20),
                      _TitleBlock(state: state),
                      const SizedBox(height: 16),
                      const _Progress(),
                      const SizedBox(height: 14),
                      const _Transport(),
                      const SizedBox(height: 10),
                      _Tools(queueCount: state.queue.length),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.source});

  /// Площадка текущего трека — её логотип стоит в пилюле «Играет из».
  final MusicSource source;

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: t.pill,
                borderRadius: BorderRadius.circular(999),
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
                  PlatformLogo(source, size: 15),
                ],
              ),
            ),
          ),
        ),
        CircleIconButton(icon: SolarIconsOutline.menuDots, onTap: () {}),
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
                iconSize: 22,
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
    this.iconSize = 20,
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
        size: 44,
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
        const SizedBox(height: 4),
        Text(
          state.error ?? track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: state.error != null
              ? theme.bodyMedium?.copyWith(color: t.sysFavIco)
              : theme.bodyMedium,
        ),
      ],
    );
  }
}

class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final player = ref.watch(audioPlayerProvider);
    final theme = Theme.of(context).textTheme;

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snap) {
        final total = player.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        final value = max <= 0
            ? 0.0
            : pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble();
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackShape: const RoundedRectSliderTrackShape(),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: value,
                max: max <= 0 ? 1 : max,
                onChanged: max <= 0
                    ? null
                    : (v) => ref
                          .read(playbackProvider.notifier)
                          .seek(Duration(milliseconds: v.round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    mmss(pos),
                    style: theme.bodySmall?.copyWith(color: t.muted),
                  ),
                  Text(
                    mmss(total),
                    style: theme.bodySmall?.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
      padding: padding ?? const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: t.ovlBg,
        border: Border.all(color: t.ovlLine),
        borderRadius: BorderRadius.circular(t.radius),
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

    final repeatIcon = switch (state.repeat) {
      PlayerRepeat.one => SolarIconsOutline.repeatOne,
      _ => SolarIconsOutline.repeat,
    };

    return _Block(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _FlatIcon(
            icon: repeatIcon,
            active: state.repeat != PlayerRepeat.off,
            onTap: ctrl.cycleRepeat,
          ),
          _FlatIcon(
            icon: SolarIconsBold.skipPrevious,
            size: 26,
            onTap: ctrl.prev,
          ),
          SizedBox(
            width: 64,
            height: 64,
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
                        width: 26,
                        height: 26,
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
                          size: 26,
                          color: t.accentText,
                        ),
                      ),
                    ),
                  ),
          ),
          _FlatIcon(icon: SolarIconsBold.skipNext, size: 26, onTap: ctrl.next),
          _FlatIcon(
            icon: SolarIconsOutline.shuffle,
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
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool active;
  final int? badge;

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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const _FlatIcon(icon: SolarIconsOutline.text),
          const _FlatIcon(icon: SolarIconsOutline.tuning),
          const _FlatIcon(icon: SolarIconsOutline.speedometerMiddle),
          _FlatIcon(
            icon: SolarIconsOutline.playlistMinimalistic,
            badge: queueCount > 0 ? queueCount : null,
            onTap: queueCount > 0 ? () => showQueueSheet(context) : null,
          ),
        ],
      ),
    );
  }
}
