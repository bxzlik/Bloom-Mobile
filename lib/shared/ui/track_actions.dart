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
import '../../core/l10n/l10n.dart';
import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../features/detail/artists_sheet.dart';
import '../../features/library/local_tracks.dart';
import '../../features/offline/file_download.dart';
import '../../features/offline/offline_actions.dart';
import '../../features/offline/offline_store.dart';
import '../../features/wave/wave_actions.dart';
import '../../features/wave/wave_store.dart';
import '../util/artists.dart';
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
  // Артистов в строке трека может быть несколько, а точный id есть только у
  // первого: тогда пункт ведёт не на страницу, а в шторку с выбором.
  final artists = parseArtists(track.artist);
  final canOpenArtist = track.artistId != null || artists.length > 1;
  final offline = ref.read(offlineProvider);
  final isOffline = offline.has(track.id);
  // Пункт показываем, только если площадка вообще отдаёт трек файлом.
  final canOffline = ref.read(offlineProvider.notifier).canDownload(track);
  final isDisliked = ref.read(waveStoreProvider).isDisliked(track.id);
  // Мессенджер берём здесь: шторка закрывается до вызова обработчика, и её
  // context к моменту снекбара уже отвязан от дерева.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

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
          label: isFav
              ? context.l.taRemoveFromFavorites
              : context.l.taAddToFavorites,
          onTap: () => ref.read(libraryProvider.notifier).toggleFav(track),
        ),
        SheetAction(
          icon: SolarIconsOutline.addCircle,
          label: context.l.taAddToPlaylist,
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
            label: isOffline
                ? context.l.taRemoveOffline
                : context.l.taListenOffline,
            onTap: () => toggleTrackOffline(messenger, l10n, ref, track),
          ),
          if (canSaveFiles)
            SheetAction(
              icon: SolarIconsOutline.downloadMinimalistic,
              label: context.l.fdDownloadFile,
              onTap: () => saveTrackFile(messenger, l10n, ref, track),
            ),
        ],
      ],
      [
        // Волна по треку — только у площадок со своим подбором: у остальных
        // пункт открывался бы ради отказа.
        if (canStartWaveFrom(track))
          SheetAction(
            icon: SolarIconsOutline.playStream,
            label: context.l.waveFromTrack,
            onTap: () => startWaveFromTrack(context, ref, track),
          ),
        SheetAction(
          icon: isDisliked ? SolarIconsBold.dislike : SolarIconsOutline.dislike,
          label: isDisliked ? context.l.waveUndislike : context.l.waveDislike,
          onTap: () => toggleWaveDislike(context, ref, track),
        ),
      ],
      [
        // Одиночного артиста без точного id открывать нечем — искать по имени
        // там, где выбирать не из чего, значит уводить наугад.
        if (canOpenArtist)
          SheetAction(
            icon: SolarIconsOutline.userRounded,
            label: context.l.taGoToArtist,
            chevron: artists.length > 1,
            onTap: () => openTrackArtist(context, ref, track),
          ),
      ],
      [
        // Удалять есть что только у трека из библиотеки: у остальных за строкой
        // ничего не стоит, они приехали из поиска.
        if (inLib)
          SheetAction(
            icon: SolarIconsOutline.trashBinMinimalistic,
            label: context.l.taDeleteTrack,
            danger: true,
            onTap: () => _deleteTrack(messenger, l10n, ref, track),
          ),
      ],
    ],
  );
}

/// Удаление насквозь, без переспроса: трек уходит и из любимых, и из
/// плейлистов, и из истории — пункт красный, тап по нему уже и есть решение.
void _deleteTrack(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
  Track track,
) {
  // Офлайн-копию убираем вместе с треком: без строки в библиотеке файл остался
  // бы мусором, на который никто не ссылается. Со своим треком то же самое:
  // копия внутри приложения стирается, чужой файл остаётся на месте.
  unawaited(ref.read(offlineProvider.notifier).remove(track.id));
  unawaited(forgetLocalTracks([track]));
  ref.read(libraryProvider.notifier).deleteTrack(track.id);
  messenger.toast(l10n.taTrackDeleted);
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
      title: context.l.taAddToPlaylist,
      subtitle: one?.name ?? context.l.tracksCount(tracks.length),
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
                label: context.l.commonAddToLibrary,
                color: t.accent,
                onTap: () {
                  // Мессенджер берём до pop: после него context шторки уже
                  // отвязан от дерева и до Scaffold по нему не дойти.
                  final messenger = ScaffoldMessenger.of(context);
                  final l10n = context.l;
                  ref.read(libraryProvider.notifier).addToLibrary(outside);
                  Navigator.of(context).pop();
                  messenger.toast(
                    l10n.taAddedToLibrary,
                    kind: ToastKind.success,
                  );
                },
              ),
              sheetDivider(),
            ],
            _SimpleRow(
              icon: SolarIconsOutline.addSquare,
              label: context.l.commonNewPlaylist,
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
