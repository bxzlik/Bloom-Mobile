/// Страница артиста площадки: шапка с баннером и секции — «Популярные»,
/// «Альбомы», «Репосты», «Похожие исполнители», «Треки».
///
/// Состав секций взят с десктопа (`features/search/ui/DetailView.tsx`,
/// `ArtistBody`), раскладка — из референса: не вкладки, а одна прокрутка.
/// Плейлисты артиста провайдер отдаёт, но своей секции у них нет и на ПК.
///
/// Всё содержимое приходит одним `getArtist` (провайдер собирает его из шести
/// эндпоинтов параллельно); докручиваются только треки и репосты — курсорами.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/store/library_store.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/detail_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/util/format.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, required this.artistId, this.initial});

  /// Сквозной id артиста («sc_artist_123»).
  final String artistId;

  /// Артист из карточки, с которой пришли: шапка рисуется до ответа сети.
  final Artist? initial;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  ArtistPageData? _data;
  String? _error;
  bool _loading = true;

  /// Треки и репосты живут в состоянии экрана, а не в [_data]: их докручивают
  /// курсорами, и список растёт.
  List<Track> _tracks = const [];
  String? _tracksCursor;
  List<RepostItem> _reposts = const [];
  String? _repostsCursor;

  /// Что именно догружается сейчас — чтобы не жать кнопку дважды.
  String? _loadingMore;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = ref.read(registryProvider).forEntity(widget.artistId);
    if (provider == null) {
      setState(() {
        _loading = false;
        _error = 'Площадка этого артиста не подключена';
      });
      return;
    }
    try {
      final data = await provider.getArtist(widget.artistId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (data == null) {
          _error = 'Артист не найден';
          return;
        }
        _data = data;
        _tracks = data.tracks;
        _tracksCursor = data.tracksCursor;
        _reposts = data.reposts;
        _repostsCursor = data.repostsCursor;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _moreTracks() async {
    final cursor = _tracksCursor;
    if (cursor == null || _loadingMore != null) return;
    setState(() => _loadingMore = 'tracks');
    final provider = ref.read(registryProvider).forEntity(widget.artistId);
    TrackPage? page;
    try {
      page = await provider?.getArtistTracksPage(cursor);
    } catch (_) {
      page = null;
    }
    if (!mounted) return;
    setState(() {
      _loadingMore = null;
      if (page == null) {
        // Не вышло — курсор гасим, иначе кнопка «Загрузить ещё» будет вечной.
        _tracksCursor = null;
        return;
      }
      _tracks = [..._tracks, ...page.tracks];
      _tracksCursor = page.cursor;
    });
  }

  Future<void> _moreReposts() async {
    final cursor = _repostsCursor;
    if (cursor == null || _loadingMore != null) return;
    setState(() => _loadingMore = 'reposts');
    final provider = ref.read(registryProvider).forEntity(widget.artistId);
    RepostPage? page;
    try {
      page = await provider?.getArtistRepostsPage(cursor);
    } catch (_) {
      page = null;
    }
    if (!mounted) return;
    setState(() {
      _loadingMore = null;
      if (page == null) {
        _repostsCursor = null;
        return;
      }
      _reposts = [..._reposts, ...page.reposts];
      _repostsCursor = page.cursor;
    });
  }

  /// Что играет кнопка «Воспроизвести»: сначала «популярные», их у SoundCloud
  /// отдаёт отдельный эндпоинт и они точнее представляют артиста.
  List<Track> get _playQueue {
    final top = _data?.topTracks ?? const <Track>[];
    return top.isNotEmpty ? top : _tracks;
  }

  void _play() {
    final queue = _playQueue;
    if (queue.isEmpty) return;
    ref.read(playbackProvider.notifier).playQueue(queue, 0);
  }

  void _shuffle() {
    final queue = _playQueue;
    if (queue.isEmpty) return;
    final ctrl = ref.read(playbackProvider.notifier);
    if (!ref.read(playbackProvider).shuffle) ctrl.toggleShuffle();
    ctrl.playQueue(queue, 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final artist = _data?.artist ?? widget.initial;
    final queue = _playQueue;

    return Scaffold(
      backgroundColor: t.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: DetailHero(
              image: artist?.avatar,
              title: artist?.name ?? 'Артист',
              subtitle: _subtitle(artist),
              onMenu: artist == null ? null : () => _menu(artist),
              actions: HeroActions(
                onPlay: queue.isEmpty ? null : _play,
                trailing: [
                  GlassIconButton(
                    icon: SolarIconsOutline.shuffle,
                    size: 46,
                    onTap: queue.isEmpty ? null : _shuffle,
                  ),
                  if (artist != null) _FollowButton(artist: artist),
                ],
              ),
            ),
          ),
          if (_loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            )
          else if (_error case final message?)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: t.sysFavIco),
                ),
              ),
            )
          else
            SliverList.list(children: _sections()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }

  /// Подпись под именем: подписчики и сколько треков загружено.
  String _subtitle(Artist? artist) {
    final parts = <String>[
      if (artist?.followers case final n? when n > 0)
        '${compactCount(n)} подписчиков',
      if (_tracks.isNotEmpty) tracksCount(_tracks.length),
    ];
    return parts.join(' · ');
  }

  List<Widget> _sections() {
    final data = _data;
    if (data == null) return const [];

    final top = data.topTracks;
    final albums = data.albums;
    final similar = data.similarArtists;
    // Очередь для строки трека в смешанной ленте репостов — только треки,
    // сеты в неё не попадают.
    final repostTracks = _reposts
        .whereType<RepostTrack>()
        .map((r) => r.track)
        .toList();

    return [
      if (top.isNotEmpty) ...[
        const SectionTitle('Популярные'),
        EntityCarousel(
          height: 194,
          itemCount: top.length,
          builder: (i) => TrackCard(track: top[i], queue: top, index: i),
        ),
      ],
      if (albums.isNotEmpty) ...[
        const SectionTitle('Альбомы'),
        EntityCarousel(
          height: 194,
          itemCount: albums.length,
          builder: (i) => SetCard(set: albums[i]),
        ),
      ],
      if (_reposts.isNotEmpty) ...[
        const SectionTitle('Репосты'),
        // Лента смешанная: трек играется в очереди из соседних треков ленты,
        // сет — открывается страницей.
        for (final item in _reposts)
          switch (item) {
            RepostTrack(:final track) => TrackRow(
              track: track,
              queue: repostTracks,
              index: repostTracks.indexOf(track),
            ),
            RepostSet(:final playlist) => SetRow(set: playlist),
          },
        if (_repostsCursor != null)
          _MoreButton(busy: _loadingMore == 'reposts', onTap: _moreReposts),
      ],
      if (similar.isNotEmpty) ...[
        const SectionTitle('Похожие исполнители'),
        EntityCarousel(
          height: 168,
          itemCount: similar.length,
          builder: (i) => ArtistCard(artist: similar[i]),
        ),
      ],
      if (_tracks.isNotEmpty) ...[
        const SectionTitle('Треки'),
        for (var i = 0; i < _tracks.length; i++)
          TrackRow(track: _tracks[i], queue: _tracks, index: i),
        if (_tracksCursor != null)
          _MoreButton(busy: _loadingMore == 'tracks', onTap: _moreTracks),
      ],
      if (top.isEmpty && albums.isEmpty && _reposts.isEmpty && _tracks.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'У этого артиста нет доступных треков',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.bloom.muted),
            ),
          ),
        ),
    ];
  }

  Future<void> _menu(Artist artist) async {
    final queue = _playQueue;
    final following = ref.read(libraryProvider).isFollowing(artist.id);
    final link = artist.permalink;
    // Импортируем то, что уже загружено: догружать всю дискографию ради
    // импорта — минуты ожидания на популярном артисте.
    final forImport = _tracks.isNotEmpty ? _tracks : queue;

    await showBloomSheet(
      context: context,
      backdrop: artist.avatar,
      header: SheetLineHeader(
        cover: artist.avatar,
        title: artist.name,
        subtitle: _subtitle(artist),
        circle: true,
      ),
      groups: [
        [
          SheetAction(
            icon: SolarIconsBold.play,
            label: 'Воспроизвести',
            onTap: queue.isEmpty ? null : _play,
          ),
          SheetAction(
            icon: SolarIconsOutline.shuffle,
            label: 'Перемешать',
            onTap: queue.isEmpty ? null : _shuffle,
          ),
        ],
        [
          SheetAction(
            icon: following
                ? SolarIconsBold.userCheckRounded
                : SolarIconsOutline.userPlusRounded,
            label: following ? 'Отписаться' : 'Подписаться',
            onTap: () {
              final on = ref
                  .read(libraryProvider.notifier)
                  .toggleFollow(artist);
              _toast(on ? 'Подписка на ${artist.name}' : 'Подписка снята');
            },
          ),
          SheetAction(
            icon: SolarIconsOutline.import,
            label: 'Треки в новый плейлист',
            onTap: forImport.isEmpty
                ? null
                : () {
                    ref
                        .read(libraryProvider.notifier)
                        .createPlaylist(
                          artist.name,
                          tracks: forImport,
                          cover: artist.avatar,
                        );
                    _toast(
                      'Добавлено: ${artist.name} — ${tracksCount(forImport.length)}',
                    );
                  },
          ),
        ],
        [
          if (link != null && link.isNotEmpty)
            SheetAction(
              icon: SolarIconsOutline.link,
              label: 'Скопировать ссылку',
              onTap: () {
                Clipboard.setData(ClipboardData(text: link));
                _toast('Ссылка скопирована');
              },
            ),
        ],
      ],
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Подписка на артиста — та же, что в библиотеке: активная кнопка заливается
/// акцентом, как чип-фильтр.
class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final following = ref.watch(libraryProvider).isFollowing(artist.id);
    return GlassIconButton(
      icon: following
          ? SolarIconsBold.userCheckRounded
          : SolarIconsOutline.userPlusRounded,
      size: 46,
      background: following ? t.accent : null,
      color: following ? t.accentText : null,
      onTap: () {
        final on = ref.read(libraryProvider.notifier).toggleFollow(artist);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(on ? 'Подписка на ${artist.name}' : 'Подписка снята'),
          ),
        );
      },
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Material(
        color: t.pill,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.iconFg,
                      ),
                    )
                  : Text(
                      'Загрузить ещё',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
