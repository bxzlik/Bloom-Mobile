/// Миниплеер — плавающая карточка над таб-баром.
///
/// Вид взят с десктопного `#miniPlayer` в режиме `mp-floating`: сплошная
/// заливка `block-color` (список под ней не просвечивает), рамка `ovl-line`,
/// радиус темы, отступы по 8. Тап и свайп вверх разворачивают плеер.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../player_controller.dart';
import 'full_player.dart';

const double kMiniPlayerHeight = 64;

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final track = state.track;
    if (track == null) return const SizedBox.shrink();

    final player = ref.watch(audioPlayerProvider);
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: GestureDetector(
        onTap: () => openFullPlayer(context),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -240) openFullPlayer(context);
        },
        child: Container(
          height: kMiniPlayerHeight,
          decoration: BoxDecoration(
            color: t.blockColor,
            border: Border.all(color: t.ovlLine),
            borderRadius: BorderRadius.circular(t.radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Cover(url: track.cover, size: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            state.error ?? track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: state.error != null
                                ? theme.bodySmall?.copyWith(color: t.sysFavIco)
                                : theme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleIconButton(
                      icon: SolarIconsOutline.skipPrevious,
                      size: 38,
                      iconSize: 20,
                      background: Colors.transparent,
                      onTap: ref.read(playbackProvider.notifier).prev,
                    ),
                    const SizedBox(width: 4),
                    if (state.loading)
                      // Кружок тот же, что у play — на переходе трека кнопка не
                      // должна пропадать из строки.
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: t.accentText,
                        ),
                      )
                    else
                      StreamBuilder<bool>(
                        stream: player.playingStream,
                        initialData: player.playing,
                        builder: (context, snap) => CircleIconButton(
                          icon: snap.data == true
                              ? SolarIconsBold.pause
                              : SolarIconsBold.play,
                          iconSize: 18,
                          size: 38,
                          background: t.accent,
                          color: t.accentText,
                          onTap: ref.read(playbackProvider.notifier).toggle,
                        ),
                      ),
                    const SizedBox(width: 4),
                    CircleIconButton(
                      icon: SolarIconsOutline.skipNext,
                      size: 38,
                      iconSize: 20,
                      background: Colors.transparent,
                      onTap: ref.read(playbackProvider.notifier).next,
                    ),
                  ],
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Hairline(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Прогресс полоской по нижней кромке карточки.
class _Hairline extends ConsumerWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final head =
        ref.watch(playheadProvider).value ??
        (position: Duration.zero, total: Duration.zero);
    final total = head.total.inMilliseconds;
    final frac = total <= 0
        ? 0.0
        : (head.position.inMilliseconds / total).clamp(0.0, 1.0);
    return SizedBox(
      height: 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac,
          child: ColoredBox(color: t.accent, child: const SizedBox(height: 2)),
        ),
      ),
    );
  }
}
