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
import '../util/format.dart';
import 'atoms.dart';
import 'bloom_sheet.dart';
import 'bloom_toast.dart';

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
            onTap: () => _deleteTrack(messenger, ref, track),
          ),
      ],
    ],
  );
}

/// Удаление насквозь, без переспроса: трек уходит и из любимых, и из
/// плейлистов, и из истории — пункт красный, тап по нему уже и есть решение.
void _deleteTrack(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  Track track,
) {
  // Офлайн-копию убираем вместе с треком: без строки в библиотеке файл остался
  // бы мусором, на который никто не ссылается.
  unawaited(ref.read(offlineProvider.notifier).remove(track.id));
  ref.read(libraryProvider.notifier).deleteTrack(track.id);
  messenger.toast('Трек удалён');
}

/// Шторка «Добавить в …»: сперва библиотека, потом плейлисты — порядок как в
/// десктопном `AddPopup` («В библиотеку» первым пунктом над списком).
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) => showAddTracksToPlaylistSheet(context, ref, [track]);

/// Та же шторка для пачки треков — выделение из режима правки списка.
///
/// [newName] — имя, которое подставится в «Новый плейлист»: у одного трека это
/// его название, у пачки — имя списка, откуда её взяли.
Future<void> showAddTracksToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  String? newName,
}) async {
  if (tracks.isEmpty) return;
  final one = tracks.length == 1 ? tracks.first : null;
  final cover = tracks.first.cover;

  await showBloomSheetChild(
    context: context,
    backdrop: cover,
    header: SheetLineHeader(
      cover: cover,
      title: 'Добавить в плейлист',
      subtitle: one?.name ?? tracksCount(tracks.length),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final t = context.bloom;
        final lib = ref.watch(libraryProvider);
        // Импортированные альбомы в список не идут: дописывать в них треки
        // руками смысла нет, они перетягиваются из источника целиком.
        final playlists = lib.playlists.where((p) => !p.isAlbum).toList();
        final outside = [
          for (final track in tracks)
            if (!lib.isInLib(track.id)) track,
        ];

        return SheetPanel(
          children: [
            // Того, что уже в библиотеке, пункт не касается — он прячется,
            // когда добавлять нечего (`canAddToLib` на десктопе). Убрать трек
            // можно только «Удалить трек» из шторки действий, насквозь.
            if (outside.isNotEmpty) ...[
              _SimpleRow(
                icon: SolarIconsOutline.download,
                label: 'В библиотеку',
                color: t.accent,
                onTap: () {
                  // Мессенджер берём до pop: после него context шторки уже
                  // отвязан от дерева и до Scaffold по нему не дойти.
                  final messenger = ScaffoldMessenger.of(context);
                  ref.read(libraryProvider.notifier).addToLibrary(outside);
                  Navigator.of(context).pop();
                  messenger.toast(
                    'Добавлено в библиотеку',
                    kind: ToastKind.success,
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
                    .createPlaylist(newName ?? one?.name ?? '', tracks: tracks);
                Navigator.of(context).pop();
              },
            ),
            for (final pl in playlists) ...[
              sheetDivider(),
              _PlaylistRow(playlist: pl, tracks: tracks),
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
  const _PlaylistRow({required this.playlist, required this.tracks});

  final UserPlaylist playlist;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final lib = ref.watch(libraryProvider);
    // Галочка — «всё это уже здесь»: у пачки половина треков в плейлисте ещё
    // не отметка, добавить остальные по-прежнему есть смысл.
    final ids = playlist.trackIds.toSet();
    final has = tracks.every((track) => ids.contains(track.id));

    return InkWell(
      onTap: () {
        ref
            .read(libraryProvider.notifier)
            .addTracksToPlaylist(playlist.id, tracks);
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Cover(
              url: playlist.cover,
              size: 40,
              covers: playlist.trackIds.map((id) => lib.tracks[id]?.cover),
            ),
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
