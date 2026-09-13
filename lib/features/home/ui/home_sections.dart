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
import '../../../core/store/history_store.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../library/lib_order_store.dart';
import '../../player/play_source.dart';
import '../discover_store.dart';
import 'chart_card.dart';
import 'chart_screen.dart';
import 'release_card.dart';
import 'releases_screen.dart';

/// Заголовок секции главной.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader(this.title, {super.key, this.onTap, this.inset = 16});

  final String title;

  /// Отступ от краёв по горизонтали. В паре «Недавно слушали / Плейлисты» он
  /// 0: там поле уже задано самим рядом.
  final double inset;

  /// Заголовок-ссылка «Чарт ›»: ведёт на полную страницу раздела. Стрелка
  /// приглушена — это подсказка, а не кнопка рядом с заголовком.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2),
            child: Icon(
              SolarIconsOutline.altArrowRight,
              size: 22,
              color: context.bloom.text.withValues(alpha: 0.55),
            ),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 18, inset, 10),
      child: onTap == null
          ? row
          : GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: row,
            ),
    );
  }
}

/// Сколько мест чарта на главной: площадка отдаёт весь чарт, полный список —
/// на странице «Чарт».
const int _homeChartMax = 15;

/// Сколько релизов на главной: карточка широкая, остальное — сеткой на
/// странице «Релизы».
const int _homeReleasesMax = 10;

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
    final charts = mode == DiscoverMode.charts;
    final title = charts ? context.l.homeCharts : context.l.homeNewReleases;
    final source = PlainSource(
      id: 'discover:${mode.name}',
      label: title,
      icon: PlainSourceIcon.chart,
    );
    // Заголовок ведёт на полную страницу: чарт — списком, релизы — сеткой.
    // У SoundCloud новинки приходят треками — сетки для них нет, и заголовок
    // остаётся обычным, как на ПК.
    final Widget? page = charts
        ? const ChartScreen()
        : block is DiscoverAlbums
        ? const ReleasesScreen()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title,
          // Значка площадки у заголовка нет — как на ПК.
          onTap: page == null
              ? null
              : () => Navigator.of(
                  context,
                ).push(detailPageRoute<void>((_) => page)),
        ),
        switch (block) {
          DiscoverTracks(:final tracks) when charts => EntityCarousel(
            height: kChartCardHeight + 6,
            padding: 16,
            itemCount: tracks.length.clamp(0, _homeChartMax),
            builder: (i) => ChartCard(
              track: tracks[i],
              pos: tracks[i].chartPos ?? i + 1,
              source: source,
            ),
          ),
          DiscoverAlbums(:final albums) => EntityCarousel(
            height: kReleaseCardHeight + 6,
            padding: 16,
            itemCount: albums.length.clamp(0, _homeReleasesMax),
            builder: (i) => ReleaseCard(album: albums[i]),
          ),
          DiscoverTracks(:final tracks) => EntityCarousel(
            height: 194,
            padding: 16,
            itemCount: tracks.length,
            builder: (i) => TrackCard(
              track: tracks[i],
              queue: tracks,
              index: i,
              source: source,
            ),
          ),
        },
      ],
    );
  }
}

/// «Недавно слушали» и «Плейлисты» в один ряд, по половине — как `.home-duo`
/// на ПК. Зазор тот же, что между плашками «Любимые / История», поэтому
/// половины стоят ровно под ними. Одна секция пуста — вторая встаёт на всю
/// ширину, обе пусты — ряда нет.
class RecentAndPlaylists extends ConsumerWidget {
  const RecentAndPlaylists({super.key});

  /// Сколько карточек в «Недавно слушали». Столько же, сколько на десктопе.
  static const int recentLimit = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = recentTracks(ref.watch(historyProvider), recentLimit);
    // Порядок — тот же, что у плиток библиотеки: её сортировка, ручной порядок
    // и закреплённые сверху. Фильтр чипов сюда не относится.
    final playlists = ref
        .watch(libOrderProvider)
        .arrange(
          ref.watch(libraryProvider).playlists,
          key: (p) => libKeyOfPlaylist(p.id),
          name: (p) => p.name,
          rank: (_) => kLibRankPlaylist,
        );

    if (recent.isEmpty && playlists.isEmpty) return const SizedBox.shrink();
    if (playlists.isEmpty) return _RecentSection(tracks: recent, inset: 16);
    if (recent.isEmpty) {
      return _PlaylistsSection(playlists: playlists, inset: 16);
    }
    // В паре ленты режутся по полю страницы, а не у края экрана: у каждой
    // половины своя прокрутка, как на ПК.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _RecentSection(tracks: recent, inset: 0)),
          const SizedBox(width: 12),
          Expanded(child: _PlaylistsSection(playlists: playlists, inset: 0)),
        ],
      ),
    );
  }
}

/// «Недавно слушали» — до 12 последних треков истории без повторов.
class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.tracks, required this.inset});

  final List<Track> tracks;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(context.l.homeRecent, inset: inset),
        EntityCarousel(
          height: 194,
          padding: inset,
          itemCount: tracks.length,
          builder: (i) => TrackCard(
            track: tracks[i],
            queue: tracks,
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

/// Последние [limit] треков «Истории». Повторов в ней нет — строка одна на
/// трек, — так что трек, прослушанный пять раз подряд, занимает в ленте одну
/// карточку. Спрятанное из «Истории» не показывается и здесь.
List<Track> recentTracks(List<HistoryItem> history, int limit) => [
  for (final item in history.take(limit)) item.track,
];

/// «Плейлисты» — свои списки лентой. Кнопки «Новый» тут нет, как на ПК:
/// плейлисты создаются в библиотеке.
class _PlaylistsSection extends StatelessWidget {
  const _PlaylistsSection({required this.playlists, required this.inset});

  final List<UserPlaylist> playlists;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(context.l.commonPlaylists, inset: inset),
        EntityCarousel(
          height: 194,
          padding: inset,
          itemCount: playlists.length,
          builder: (i) => _PlaylistCard(playlist: playlists[i]),
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
