/// Действия над треком: лайк, добавление в плейлист, переход к артисту.
///
/// Аналог контекстного меню трека на десктопе, только снизу — на телефоне это
/// длинный тап по строке и кнопки на обложке в плеере.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../features/detail/detail_nav.dart';
import '../../features/offline/file_download.dart';
import '../../features/offline/offline_actions.dart';
import '../../features/offline/offline_store.dart';
import 'atoms.dart';
import 'bloom_sheet.dart';

Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final lib = ref.read(libraryProvider);
  final isFav = lib.isFav(track.id);
  final inLib = lib.isInLib(track.id);
  final artistId = track.artistId;
  final offline = ref.read(offlineProvider);
  final isOffline = offline.has(track.id);
  // Пункт показываем, только если площадка вообще отдаёт трек файлом.
  final canOffline = ref.read(offlineProvider.notifier).canDownload(track);
  // Мессенджер берём здесь: шторка закрывается до вызова обработчика, и её
  // context к моменту снекбара уже отвязан от дерева.
  final messenger = ScaffoldMessenger.of(context);

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
        // Два скачивания, как на десктопе: копия внутри приложения — чтобы
        // играло без сети, и файл наружу — чтобы им можно было пользоваться
        // вне Bloom. Иконки оттуда же: дискета у офлайна, галочка когда трек
        // уже скачан (у Solar голой галочки нет, поэтому в кружке — на ПК её
        // ради этого рисовали своим SVG).
        if (canOffline) ...[
          SheetAction(
            icon: isOffline
                ? SolarIconsBold.checkCircle
                : SolarIconsOutline.diskette,
            label: isOffline ? 'Убрать из офлайна' : 'Слушать офлайн',
            onTap: () => toggleTrackOffline(messenger, ref, track),
          ),
          if (canSaveFiles)
            SheetAction(
              icon: SolarIconsOutline.downloadMinimalistic,
              label: 'Скачать файлом',
              onTap: () => saveTrackFile(messenger, ref, track),
            ),
        ],
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
      [
        // Удалять есть что только у трека из библиотеки: у остальных за строкой
        // ничего не стоит, они приехали из поиска.
        if (inLib)
          SheetAction(
            icon: SolarIconsOutline.trashBinMinimalistic,
            label: 'Удалить трек',
            danger: true,
            onTap: () => _confirmDelete(context, ref, track),
          ),
      ],
    ],
  );
}

/// Удаление насквозь — спрашиваем, как `confirm()` на десктопе: трек уходит и
/// из любимых, и из плейлистов, и из истории.
Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final t = context.bloom;
  final theme = Theme.of(context).textTheme;
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: t.blockColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: t.ovlLine),
      ),
      title: Text('Удалить трек?', style: theme.titleLarge),
      content: Text(
        '«${track.name}» пропадёт из библиотеки, любимых, плейлистов и истории.',
        style: theme.bodyMedium?.copyWith(color: t.text2),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Отмена', style: TextStyle(color: t.text2)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Удалить', style: TextStyle(color: t.sysFavIco)),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  // Мессенджер берём до удаления: строка, из которой вызвали шторку, после него
  // уезжает из списка вместе со своим context.
  final messenger = ScaffoldMessenger.of(context);
  // Офлайн-копию убираем вместе с треком: без строки в библиотеке файл остался
  // бы мусором, на который никто не ссылается.
  unawaited(ref.read(offlineProvider.notifier).remove(track.id));
  ref.read(libraryProvider.notifier).deleteTrack(track.id);
  messenger.showSnackBar(const SnackBar(content: Text('Трек удалён')));
}

/// Шторка «Добавить в …»: сперва библиотека, потом плейлисты — порядок как в
/// десктопном `AddPopup` («В библиотеку» первым пунктом над списком).
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
        final lib = ref.watch(libraryProvider);
        // Импортированные альбомы в список не идут: дописывать в них треки
        // руками смысла нет, они перетягиваются из источника целиком.
        final playlists = lib.playlists.where((p) => !p.isAlbum).toList();
        final inLib = lib.isInLib(track.id);

        return SheetPanel(
          children: [
            // Трека уже в библиотеке пункт не касается — он там и прячется
            // (`canAddToLib` на десктопе). Убрать трек можно только
            // «Удалить трек» из шторки действий, насквозь.
            if (!inLib) ...[
              _SimpleRow(
                icon: SolarIconsOutline.download,
                label: 'В библиотеку',
                color: t.accent,
                onTap: () {
                  // Мессенджер берём до pop: после него context шторки уже
                  // отвязан от дерева и до Scaffold по нему не дойти.
                  final messenger = ScaffoldMessenger.of(context);
                  ref.read(libraryProvider.notifier).addToLibrary([track]);
                  Navigator.of(context).pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Добавлено в библиотеку')),
                  );
                },
              ),
              sheetDivider(),
            ],
            _SimpleRow(
              icon: SolarIconsOutline.addSquare,
              label: 'Новый плейлист',
              color: t.accent,
              onTap: () {
                ref
                    .read(libraryProvider.notifier)
                    .createPlaylist(track.name, tracks: [track]);
                Navigator.of(context).pop();
              },
            ),
            for (final pl in playlists) ...[
              sheetDivider(),
              _PlaylistRow(playlist: pl, track: track),
            ],
          ],
        );
      },
    ),
  );
}

/// Строка шторки без обложки — под высоту строки плейлиста.
class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 16),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
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
