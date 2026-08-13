/// Карточка «Продолжить» на главной — порт десктопного `ContinueCard`
/// (`app/pages/HomePage.tsx`): обложка, круглая кнопка play/pause, полоса-
/// пилюля с названием внутри и ♡ справа. Одной строкой, как на ПК.
///
/// Два состояния: живой трек этой сессии (полоса перематывается) и снимок
/// прошлой сессии из [resumeProvider] — тогда полоса просто показывает, где
/// остановились, а тап восстанавливает очередь и играет с того же места.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/track_actions.dart';
import '../../player/player_controller.dart';
import '../../player/resume_store.dart';
import '../../player/ui/full_player.dart';

class ContinueCard extends ConsumerWidget {
  const ContinueCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playbackProvider.select((s) => s.track));
    // Снимок прошлой сессии слушаем ТОЛЬКО пока нет живого трека: плеер
    // обновляет его каждые несколько секунд, и подписка на ходу перерисовывала
    // бы карточку впустую.
    if (track == null) {
      final data = ref.watch(resumeProvider);
      return data == null ? const SizedBox.shrink() : _FromResume(data: data);
    }
    return const _Live();
  }
}

/// Живой трек: позиция идёт из плеера, полоса перематывает.
class _Live extends ConsumerStatefulWidget {
  const _Live();

  @override
  ConsumerState<_Live> createState() => _LiveState();
}

class _LiveState extends ConsumerState<_Live> {
  /// Доля под пальцем, пока тянут. Как в полноэкранном плеере: перематываем
  /// один раз, на отпускании, иначе заливка отпрыгивает к позиции из стрима.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(playbackProvider.select((s) => s.track));
    if (track == null) return const SizedBox.shrink();
    final head =
        ref.watch(playheadProvider).value ??
        (position: Duration.zero, total: Duration.zero);
    final playing =
        ref.watch(playingProvider).value ??
        ref.read(audioPlayerProvider).playing;

    final total = head.total;
    final ms = total.inMilliseconds;
    final live = ms <= 0 ? 0.0 : head.position.inMilliseconds / ms;
    final value = (_drag ?? live).clamp(0.0, 1.0);

    return _CardShell(
      track: track,
      progress: value,
      playing: playing,
      onTap: () => openFullPlayer(context),
      onPlay: () => ref.read(playbackProvider.notifier).toggle(),
      onSeek: ms <= 0 ? null : (v) => setState(() => _drag = v),
      onSeekEnd: ms <= 0
          ? null
          : (v) async {
              await ref
                  .read(playbackProvider.notifier)
                  .seek(Duration(milliseconds: (v * ms).round()));
              // Отпускаем только после самой перемотки: до неё стрим отдаёт
              // ещё старую позицию, и заливка моргнула бы назад.
              if (mounted) setState(() => _drag = null);
            },
    );
  }
}

/// Снимок прошлой сессии: играть ещё нечему, поэтому полоса неподвижна, а
/// любой тап по карточке восстанавливает очередь.
class _FromResume extends ConsumerWidget {
  const _FromResume({required this.data});

  final ResumeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = data.track;
    final total = track.duration;
    final start = ref.read(playbackProvider.notifier).resumeSession;
    return _CardShell(
      track: track,
      progress: total.inMilliseconds <= 0
          ? 0
          : (data.position.inMilliseconds / total.inMilliseconds).clamp(
              0.0,
              1.0,
            ),
      playing: false,
      onTap: () => start(data),
      onPlay: () => start(data),
    );
  }
}

/// Вид карточки — общий для обоих состояний.
class _CardShell extends ConsumerWidget {
  const _CardShell({
    required this.track,
    required this.progress,
    required this.playing,
    required this.onTap,
    required this.onPlay,
    this.onSeek,
    this.onSeekEnd,
  });

  final Track track;
  final double progress;
  final bool playing;

  /// Тап по обложке и по свободному месту: у живого трека — открыть плеер, у
  /// снимка — продолжить прошлую сессию.
  final VoidCallback onTap;
  final VoidCallback onPlay;

  /// Перемотка. `null` — полоса неподвижна (снимок прошлой сессии).
  final ValueChanged<double>? onSeek;
  final Future<void> Function(double)? onSeekEnd;

  /// Высота ряда «кнопка — полоса — ♡».
  static const double _height = 44;

  /// Обложка стоит НАД рядом и по центру — так он показал на скриншоте.
  static const double _cover = 88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final isFav = ref.watch(
      libraryProvider.select((lib) => lib.isFav(track.id)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => showTrackActions(context, ref, track),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Cover(url: track.cover, size: _cover),
            const SizedBox(height: 10),
            Row(
              children: [
                CircleIconButton(
                  icon: playing ? SolarIconsBold.pause : SolarIconsBold.play,
                  iconSize: 16,
                  size: _height,
                  background: t.pill,
                  onTap: onPlay,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SeekPill(
                    title: track.name,
                    artist: track.artist,
                    progress: progress,
                    onSeek: onSeek,
                    onSeekEnd: onSeekEnd,
                  ),
                ),
                const SizedBox(width: 8),
                CircleIconButton(
                  icon: isFav ? SolarIconsBold.heart : SolarIconsOutline.heart,
                  iconSize: 18,
                  size: _height,
                  color: isFav ? t.sysFavIco : null,
                  onTap: () =>
                      ref.read(libraryProvider.notifier).toggleFav(track),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Полоса-пилюля десктопной карточки (`hcc-seek`): заливка прогресса и
/// название с артистом внутри неё, по центру. Времён здесь нет — он попросил
/// их убрать, они и так стоят в плеере.
///
/// Перемотка своя, а не `Slider`: слайдеру нужна собственная высота и он не
/// умеет держать под собой текст. Доля считается от ширины пилюли — так же,
/// как `applyAt` на десктопе.
class _SeekPill extends StatelessWidget {
  const _SeekPill({
    required this.title,
    required this.artist,
    required this.progress,
    this.onSeek,
    this.onSeekEnd,
  });

  final String title;
  final String artist;
  final double progress;
  final ValueChanged<double>? onSeek;
  final Future<void> Function(double)? onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(999);
    final seek = onSeek;

    final pill = LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        void applyAt(double dx) =>
            seek?.call((dx / width).clamp(0.0, 1.0));

        final content = Container(
          height: _CardShell._height,
          decoration: BoxDecoration(color: t.track, borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Заливка прогресса — приглушённый акцент: поверх неё лежит
              // текст, и полный акцент забивал бы его.
              //
              // `Positioned.fill` обязателен: в `Stack` доля получает свободные
              // ограничения, схлопывается по высоте в ноль и вдобавок встаёт по
              // центру, а не от левого края.
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: ColoredBox(color: t.accent.withValues(alpha: 0.28)),
                ),
              ),
              // Тоже `Positioned.fill`: иначе блок текста получает свободные
              // ограничения, сжимается по своей ширине и встаёт у левого края
              // пилюли — центрировать его внутри самого себя бесполезно.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.titleSmall,
                      ),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        if (seek == null) return content;
        return GestureDetector(
          // Свои жесты только по горизонтали: вертикальные остаются ленте
          // главной, иначе пилюля мешала бы её листать.
          onTapDown: (d) => applyAt(d.localPosition.dx),
          onTapUp: (d) => onSeekEnd?.call((d.localPosition.dx / width).clamp(0.0, 1.0)),
          onHorizontalDragStart: (d) => applyAt(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => applyAt(d.localPosition.dx),
          onHorizontalDragEnd: (_) => onSeekEnd?.call(progress),
          child: content,
        );
      },
    );

    return pill;
  }
}
