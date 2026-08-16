/// Ленты главной: витрина «Новинки»/«Чарты», «Недавно слушали» и «Плейлисты».
/// Порт секций десктопной `HomePage` и `DiscoverSections`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../library/ui/create_playlist_sheet.dart';
import '../../player/play_source.dart';
import '../discover_store.dart';

/// Заголовок секции с местом под значок площадки справа от текста.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Блок витрины. Пока данных нет — на экране ничего: ни скелетона, ни ошибки
/// (см. `discover_store`).
class DiscoverSection extends ConsumerWidget {
  const DiscoverSection({super.key, required this.mode});

  final DiscoverMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(discoverProvider(mode)).value;
    if (result == null) return const SizedBox.shrink();
    final block = result.block;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          mode == DiscoverMode.charts
              ? context.l.homeCharts
              : context.l.homeNewReleases,
          // Вместо десктопного попапа «доступно только для Яндекс Музыки» —
          // сам логотип площадки: строчку текста он заменяет полностью, а
          // кнопка внутри заголовка на телефоне только мешала бы.
          trailing: PlatformLogo(result.source, size: 15),
        ),
        switch (block) {
          DiscoverTracks(:final tracks) => EntityCarousel(
            height: 194,
            padding: 16,
            itemCount: tracks.length,
            builder: (i) => TrackCard(
              track: tracks[i],
              queue: tracks,
              index: i,
              source: PlainSource(
                id: 'discover:${mode.name}',
                label: mode == DiscoverMode.charts
                    ? context.l.homeCharts
                    : context.l.homeNewReleases,
                icon: PlainSourceIcon.chart,
              ),
            ),
          ),
          DiscoverAlbums(:final albums) => EntityCarousel(
            height: 194,
            padding: 16,
            itemCount: albums.length,
            builder: (i) => SetCard(set: albums[i]),
          ),
        },
      ],
    );
  }
}

/// «Недавно слушали» — до 12 последних треков истории без повторов.
class RecentSection extends ConsumerWidget {
  const RecentSection({super.key});

  /// Сколько карточек показываем. Столько же, сколько на десктопе.
  static const int limit = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final recent = recentTracks(lib, limit);
    if (recent.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(context.l.homeRecent),
        EntityCarousel(
          height: 194,
          padding: 16,
          itemCount: recent.length,
          builder: (i) => TrackCard(
            track: recent[i],
            queue: recent,
            index: i,
            source: PlainSource(
              id: 'recent',
              label: context.l.homeRecent,
              icon: PlainSourceIcon.clock,
            ),
          ),
        ),
      ],
    );
  }
}

/// Последние [limit] треков истории без повторов — один трек, прослушанный
/// пять раз подряд, занимает в ленте одну карточку, а не пять.
List<Track> recentTracks(LibraryState lib, int limit) {
  final out = <Track>[];
  final seen = <String>{};
  for (final entry in lib.history) {
    if (!seen.add(entry.trackId)) continue;
    final track = lib.tracks[entry.trackId];
    if (track != null) out.add(track);
    if (out.length >= limit) break;
  }
  return out;
}

/// «Плейлисты» — свои списки лентой, в конце плитка «Новый».
class PlaylistsSection extends ConsumerWidget {
  const PlaylistsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final playlists = lib.playlists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(context.l.commonPlaylists),
        EntityCarousel(
          height: 194,
          padding: 16,
          // Плитка «Новый» стоит последней и есть всегда: с неё же начинается
          // главная на пустой библиотеке.
          itemCount: playlists.length + 1,
          builder: (i) => i == playlists.length
              ? const _NewPlaylistCard()
              : _PlaylistCard(playlist: playlists[i]),
        ),
      ],
    );
  }
}

/// Карточка своего плейлиста. Отдельная от [SetCard]: там сущность площадки
/// ([Playlist]), а здесь локальный [UserPlaylist] — с коллажем из треков
/// вместо обложки и переходом в список библиотеки.
class _PlaylistCard extends ConsumerStatefulWidget {
  const _PlaylistCard({required this.playlist});

  final UserPlaylist playlist;

  @override
  ConsumerState<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends ConsumerState<_PlaylistCard> {
  /// Метка перелёта обложки в шапку списка — своя у каждого экземпляра.
  final _tag = UniqueKey();

  static const double _size = 132;

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final theme = Theme.of(context).textTheme;
    final tracks = ref.watch(libraryProvider).tracksOf(playlist);
    final cover = playlist.cover;
    final flight = cover == null || cover.isEmpty
        ? null
        : CoverFlight(tag: _tag, image: cover);

    return GestureDetector(
      onTap: () => context.go('/library/list/${playlist.id}', extra: flight),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Cover(
              url: cover,
              size: _size,
              flight: flight,
              overlay: SetEqualizer(setId: playlist.id),
              covers: tracks.map((track) => track.cover),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              context.l.tracksCount(playlist.trackIds.length),
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

/// Плитка «Новый плейлист» — та же шторка создания, что в библиотеке.
class _NewPlaylistCard extends ConsumerWidget {
  const _NewPlaylistCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => showCreatePlaylistSheet(context, ref),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _PlaylistCardState._size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _PlaylistCardState._size,
              height: _PlaylistCardState._size,
              decoration: BoxDecoration(
                color: t.coverEmpty,
                borderRadius: BorderRadius.circular(t.radius * 0.72),
              ),
              child: Icon(
                SolarIconsOutline.addSquare,
                size: 28,
                color: t.text2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l.commonNewPlaylist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
