/// Действия над треком: лайк, добавление в плейлист, переход к артисту.
///
/// Аналог контекстного меню трека на десктопе, только снизу — на телефоне это
/// длинный тап по строке и кнопки на обложке в плеере.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../features/detail/detail_nav.dart';
import 'atoms.dart';
import 'bloom_sheet.dart';

Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final isFav = ref.read(libraryProvider).isFav(track.id);
  final artistId = track.artistId;

  await showBloomSheet(
    context: context,
    backdrop: track.cover,
    header: SheetLineHeader(
      cover: track.cover,
      title: track.name,
      subtitle: track.artist,
    ),
    groups: [
      [
        SheetAction(
          icon: isFav ? SolarIconsBold.heart : SolarIconsOutline.heart,
          label: isFav ? 'Убрать из любимых' : 'В любимые',
          onTap: () => ref.read(libraryProvider.notifier).toggleFav(track),
        ),
        SheetAction(
          icon: SolarIconsOutline.addCircle,
          label: 'Добавить в плейлист',
          chevron: true,
          onTap: () => showAddToPlaylistSheet(context, ref, track),
        ),
      ],
      [
        // Точный id артиста есть не у всякого трека — искать по имени незачем.
        if (artistId != null)
          SheetAction(
            icon: SolarIconsOutline.userRounded,
            label: 'Перейти к артисту',
            onTap: () => openArtist(context, artistId),
          ),
      ],
    ],
  );
}

Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  await showBloomSheetChild(
    context: context,
    backdrop: track.cover,
    header: SheetLineHeader(
      cover: track.cover,
      title: 'Добавить в плейлист',
      subtitle: track.name,
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final t = context.bloom;
        // Импортированные альбомы в список не идут: дописывать в них треки
        // руками смысла нет, они перетягиваются из источника целиком.
        final playlists = ref
            .watch(libraryProvider)
            .playlists
            .where((p) => !p.isAlbum)
            .toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Material(
            color: t.pill,
            borderRadius: BorderRadius.circular(t.radius),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    ref
                        .read(libraryProvider.notifier)
                        .createPlaylist(track.name, tracks: [track]);
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          SolarIconsOutline.addSquare,
                          size: 22,
                          color: t.accent,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Новый плейлист',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(color: t.accent),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final pl in playlists) ...[
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 54,
                    color: t.ovlLine,
                  ),
                  _PlaylistRow(playlist: pl, track: track),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({required this.playlist, required this.track});

  final UserPlaylist playlist;
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final has = playlist.trackIds.contains(track.id);

    return InkWell(
      onTap: () {
        ref
            .read(libraryProvider.notifier)
            .addTrackToPlaylist(playlist.id, track);
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Cover(url: playlist.cover, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (has)
              Icon(SolarIconsBold.checkCircle, size: 18, color: t.accent),
          ],
        ),
      ),
    );
  }
}
