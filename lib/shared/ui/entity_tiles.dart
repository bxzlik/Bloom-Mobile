/// Строки и карточки сущностей — общие для поиска, страниц артиста и
/// библиотеки. Работают с нейтральными [Track]/[Artist]/[Playlist], поэтому
/// одинаковы для всех площадок.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../features/detail/detail_nav.dart';
import '../../features/player/player_controller.dart';
import '../util/format.dart';
import 'atoms.dart';
import 'platform_logo.dart';
import 'track_actions.dart';

/// Строка трека: обложка, название/артист, длительность. Тап ставит [queue]
/// целиком, чтобы работали «дальше»/«назад», а не один трек.
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
  });

  final Track track;
  final List<Track> queue;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final active = ref.watch(playbackProvider).track?.id == track.id;

    return InkWell(
      onTap: () => ref.read(playbackProvider.notifier).playQueue(queue, index),
      // Длинный тап — то же, что контекстное меню трека на десктопе.
      onLongPress: () => showTrackActions(context, ref, track),
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            // Бейдж площадки в углу обложки: в общем списке треки могут быть
            // из разных источников, и по обложке этого не понять.
            Stack(
              children: [
                Cover(url: track.cover, size: 48),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: PlatformLogo(track.source, size: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: active
                        ? theme.titleMedium?.copyWith(color: t.accent)
                        : theme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              mmss(track.duration),
              style: theme.bodySmall?.copyWith(color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка альбома или плейлиста: обложка, название, владелец. Нужна там, где
/// сет стоит в списке, а не в карусели — в репостах артиста.
class SetRow extends StatelessWidget {
  const SetRow({super.key, required this.set});

  final Playlist set;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final sub = [
      set.isAlbum ? 'Альбом' : 'Плейлист',
      set.ownerName,
      if (set.trackCount != null) tracksCount(set.trackCount!),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: () => openSet(context, set),
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Cover(url: set.cover, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    set.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка трека для карусели («Популярные» на странице артиста). Тап ставит
/// [queue] целиком — как и строка трека.
class TrackCard extends ConsumerWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.size = 132,
  });

  final Track track;
  final List<Track> queue;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final active = ref.watch(playbackProvider).track?.id == track.id;

    return GestureDetector(
      onTap: () => ref.read(playbackProvider.notifier).playQueue(queue, index),
      onLongPress: () => showTrackActions(context, ref, track),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Cover(url: track.cover, size: size),
            const SizedBox(height: 8),
            Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: active
                  ? theme.titleSmall?.copyWith(color: t.accent)
                  : theme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка артиста: круглый аватар, имя, подписчики. Тап открывает страницу
/// артиста — других применений у карточки нет.
///
/// [size] `null` — карточка занимает всю ширину ячейки (сетка выдачи); число —
/// фиксированная ширина (карусель).
class ArtistCard extends StatelessWidget {
  const ArtistCard({
    super.key,
    required this.artist,
    this.size = 104,
    this.centerLabel = false,
  });

  final Artist artist;
  final double? size;

  /// Подписи по центру — так стоят артисты в сетке и подписки в библиотеке.
  final bool centerLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final followers = artist.followers;
    final align = centerLabel ? TextAlign.center : TextAlign.start;

    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: centerLabel
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Cover(url: artist.avatar, size: box.maxWidth, circle: true),
          const SizedBox(height: 8),
          Text(
            artist.name,
            maxLines: 1,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: theme.titleSmall,
          ),
          if (followers != null) ...[
            const SizedBox(height: 2),
            Text(
              '${compactCount(followers)} подписчиков',
              maxLines: 1,
              textAlign: align,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
          ],
        ],
      ),
    );

    return GestureDetector(
      onTap: () => openArtist(context, artist.id, initial: artist),
      behavior: HitTestBehavior.opaque,
      child: size == null ? content : SizedBox(width: size, child: content),
    );
  }
}

/// Карточка плейлиста или альбома: обложка, название, владелец и счётчик.
///
/// [size] `null` — на всю ширину ячейки сетки, число — фиксированная ширина
/// карусели.
class SetCard extends StatelessWidget {
  const SetCard({super.key, required this.set, this.size = 132});

  final Playlist set;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    // Год и счётчик есть не всегда — пустые части просто выпадают, вместо
    // «0 треков» и пустых разделителей.
    final sub = [
      set.ownerName,
      set.year,
      if (set.trackCount != null) tracksCount(set.trackCount!),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Cover(url: set.cover, size: box.maxWidth),
          const SizedBox(height: 8),
          Text(
            set.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall,
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () => openSet(context, set),
      behavior: HitTestBehavior.opaque,
      child: size == null ? content : SizedBox(width: size, child: content),
    );
  }
}

/// Горизонтальная лента карточек — общая для выдачи поиска и секций страницы
/// артиста.
class EntityCarousel extends StatelessWidget {
  const EntityCarousel({
    super.key,
    required this.height,
    required this.itemCount,
    required this.builder,
  });

  final double height;
  final int itemCount;
  final Widget Function(int index) builder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => builder(i),
      ),
    );
  }
}

/// Заголовок секции выдачи.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
