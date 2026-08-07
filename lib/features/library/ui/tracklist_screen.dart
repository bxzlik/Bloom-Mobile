/// Список треков раздела библиотеки: встроенные «Все треки» / «Любимые» /
/// «История» и пользовательские плейлисты — один экран на всё.
///
/// Раскладка: hero-обложка во всю ширину, название и счётчик поверх неё, ряд
/// «Воспроизвести» + шафл + правка, ниже трек-лист.
///
/// У встроенных разделов своей обложки нет, поэтому берётся коллаж 2×2 из
/// первых треков (как `.home-quick-card` на десктопе), а если и их не хватает —
/// плоский тинт раздела с его цветной иконкой.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/util/format.dart';

/// Сортировка трек-листа — те же режимы, что на десктопе.
enum TrackSort {
  manual('По порядку'),
  name('По названию'),
  artist('По исполнителю'),
  duration('По длительности');

  const TrackSort(this.label);
  final String label;
}

class TracklistScreen extends ConsumerStatefulWidget {
  const TracklistScreen({super.key, required this.listId});

  /// `all` / `fav` / `history` либо id пользовательского плейлиста.
  final String listId;

  @override
  ConsumerState<TracklistScreen> createState() => _TracklistScreenState();
}

class _TracklistScreenState extends ConsumerState<TracklistScreen> {
  TrackSort _sort = TrackSort.manual;
  bool _searchOpen = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final lib = ref.watch(libraryProvider);

    UserPlaylist? playlist;
    if (widget.listId.startsWith('pl_')) {
      for (final p in lib.playlists) {
        if (p.id == widget.listId) {
          playlist = p;
          break;
        }
      }
    }

    final (String title, List<Track> source) = switch (widget.listId) {
      'all' => ('Все треки', lib.allTracks),
      'fav' => ('Любимые', lib.favTracks),
      'history' => ('История', lib.historyTracks),
      _ => (
        playlist?.name ?? 'Плейлист',
        playlist == null ? <Track>[] : lib.tracksOf(playlist),
      ),
    };

    final tracks = _apply(source);
    final width = MediaQuery.of(context).size.width;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Hero(
            listId: widget.listId,
            title: title,
            playlist: playlist,
            tracks: source,
            visible: tracks,
            height: width * 0.62,
            sort: _sort,
            onSort: (s) => setState(() => _sort = s),
            searchOpen: _searchOpen,
            query: _query,
            onToggleSearch: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) _query = '';
            }),
            onQuery: (q) => setState(() => _query = q),
          ),
        ),
        if (tracks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text(
                  _query.isNotEmpty
                      ? 'Ничего не нашлось'
                      : switch (widget.listId) {
                          'fav' => 'Пока ничего не залайкано',
                          'history' => 'История пуста',
                          'all' => 'В библиотеке пока пусто',
                          _ => 'В плейлисте пока пусто',
                        },
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: t.muted),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            sliver: SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) =>
                  TrackRow(track: tracks[i], queue: tracks, index: i),
            ),
          ),
      ],
    );
  }

  /// Поиск и сортировка применяются к копии: исходный порядок плейлиста
  /// трогать нельзя, «По порядку» должен уметь вернуть его как было.
  List<Track> _apply(List<Track> source) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? [...source]
        : source
              .where(
                (t) =>
                    t.name.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q),
              )
              .toList();
    switch (_sort) {
      case TrackSort.manual:
        break;
      case TrackSort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case TrackSort.artist:
        list.sort(
          (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        );
      case TrackSort.duration:
        list.sort((a, b) => a.duration.compareTo(b.duration));
    }
    return list;
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.listId,
    required this.title,
    required this.playlist,
    required this.tracks,
    required this.visible,
    required this.height,
    required this.sort,
    required this.onSort,
    required this.searchOpen,
    required this.query,
    required this.onToggleSearch,
    required this.onQuery,
  });

  final String listId;
  final String title;
  final UserPlaylist? playlist;

  /// Полный состав — по нему считается счётчик и запускается воспроизведение.
  final List<Track> tracks;

  /// То, что реально показано (после поиска и сортировки).
  final List<Track> visible;
  final double height;
  final TrackSort sort;
  final ValueChanged<TrackSort> onSort;
  final bool searchOpen;
  final String query;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;

    return SizedBox(
      height: height + 76,
      child: Stack(
        children: [
          // Обложка на всю шапку, включая ряд действий: её скруглённый нижний
          // край и есть граница со списком.
          Positioned.fill(
            child: HeroCover(
              child: _HeroBackground(
                listId: listId,
                playlist: playlist,
                tracks: tracks,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GlassIconButton(
                        icon: SolarIconsOutline.arrowLeft,
                        onTap: () => context.go('/library'),
                      ),
                      const SizedBox(width: 8),
                      _SortButton(sort: sort, onSort: onSort),
                      const Spacer(),
                      GlassIconButton(
                        icon: searchOpen
                            ? SolarIconsOutline.closeCircle
                            : SolarIconsOutline.magnifier,
                        onTap: onToggleSearch,
                      ),
                      if (playlist != null) ...[
                        const SizedBox(width: 8),
                        GlassIconButton(
                          icon: SolarIconsOutline.menuDots,
                          onTap: () =>
                              showPlaylistMenu(context, ref, playlist!, tracks),
                        ),
                      ],
                    ],
                  ),
                  if (searchOpen) ...[
                    const SizedBox(height: 10),
                    _InlineSearch(query: query, onQuery: onQuery),
                  ],
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.headlineSmall?.copyWith(fontSize: 30),
                  ),
                  const SizedBox(height: 4),
                  Text(tracksCount(tracks.length), style: theme.bodyMedium),
                  const SizedBox(height: 14),
                  _Actions(
                    tracks: visible.isEmpty ? tracks : visible,
                    playlist: playlist,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Фон hero: обложка плейлиста → коллаж 2×2 из треков → тинт раздела.
class _HeroBackground extends StatelessWidget {
  const _HeroBackground({
    required this.listId,
    required this.playlist,
    required this.tracks,
  });

  final String listId;
  final UserPlaylist? playlist;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    final cover = coverImage(playlist?.cover);
    if (cover != null) {
      return Image(
        image: cover,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _tint(t),
      );
    }

    final covers = tracks
        .map((x) => x.cover)
        .whereType<String>()
        .take(4)
        .toList();
    if (covers.length == 4) {
      return GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final c in covers)
            Image.network(
              c,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _tint(t),
            ),
        ],
      );
    }
    if (covers.isNotEmpty) {
      return Image.network(
        covers.first,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _tint(t),
      );
    }
    return _tint(t);
  }

  Widget _tint(BloomTokens t) {
    final (Color tint, Color color, IconData icon) = switch (listId) {
      'fav' => (t.sysFavTint, t.sysFavIco, SolarIconsBold.heart),
      'history' => (t.sysHistTint, t.sysHistIco, SolarIconsOutline.clockCircle),
      'all' => (t.sysAllTint, t.sysAllIco, SolarIconsOutline.musicNote),
      _ => (t.ovlBg, t.muted, SolarIconsBold.musicNote),
    };
    return ColoredBox(
      color: tint,
      child: Center(child: Icon(icon, size: 64, color: color)),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onSort});

  final TrackSort sort;
  final ValueChanged<TrackSort> onSort;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return PopupMenuButton<TrackSort>(
      onSelected: onSort,
      color: t.blockColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: t.ovlLine),
      ),
      itemBuilder: (context) => [
        for (final s in TrackSort.values)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (s == sort)
                  Icon(SolarIconsBold.checkCircle, size: 16, color: t.accent),
              ],
            ),
          ),
      ],
      child: IgnorePointer(
        child: GlassIconButton(icon: SolarIconsOutline.tuning_2, onTap: () {}),
      ),
    );
  }
}

class _InlineSearch extends StatelessWidget {
  const _InlineSearch({required this.query, required this.onQuery});

  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GlassSurface(
      shape: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: kHeaderControl,
          child: Row(
            children: [
              const Icon(
                SolarIconsOutline.magnifier,
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  autofocus: true,
                  onChanged: onQuery,
                  cursorColor: t.accent,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'В этом списке',
                    hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.tracks, required this.playlist});

  final List<Track> tracks;
  final UserPlaylist? playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final enabled = tracks.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: Material(
            color: enabled ? t.accent : t.pill,
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled
                  ? () =>
                        ref.read(playbackProvider.notifier).playQueue(tracks, 0)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(SolarIconsBold.play, size: 18, color: t.accentText),
                    const SizedBox(width: 8),
                    Text(
                      'Воспроизвести',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: t.accentText),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GlassIconButton(
          icon: SolarIconsOutline.shuffle,
          size: 46,
          onTap: enabled
              ? () {
                  final ctrl = ref.read(playbackProvider.notifier);
                  if (!ref.read(playbackProvider).shuffle) ctrl.toggleShuffle();
                  ctrl.playQueue(tracks, 0);
                }
              : null,
        ),
        if (playlist case final pl?) ...[
          const SizedBox(width: 10),
          GlassIconButton(
            icon: SolarIconsOutline.penNewSquare,
            size: 46,
            onTap: () => _rename(context, ref, pl),
          ),
        ],
      ],
    );
  }
}

/// Шторка «трёх точек» плейлиста — общая для его страницы и плитки в
/// библиотеке.
Future<void> showPlaylistMenu(
  BuildContext context,
  WidgetRef ref,
  UserPlaylist playlist,
  List<Track> tracks,
) async {
  void play({bool shuffle = false}) {
    if (tracks.isEmpty) return;
    final ctrl = ref.read(playbackProvider.notifier);
    if (shuffle && !ref.read(playbackProvider).shuffle) ctrl.toggleShuffle();
    ctrl.playQueue(tracks, 0);
  }

  // У плейлиста без своей обложки её роль играет первый трек — так же, как в
  // hero экрана.
  final cover = playlist.cover ?? (tracks.isEmpty ? null : tracks.first.cover);

  await showBloomSheet(
    context: context,
    backdrop: cover,
    header: SheetCoverHeader(
      cover: cover,
      title: playlist.name,
      subtitle: tracksCount(tracks.length),
    ),
    groups: [
      [
        SheetAction(
          icon: SolarIconsBold.play,
          label: 'Воспроизвести',
          onTap: tracks.isEmpty ? null : play,
        ),
        SheetAction(
          icon: SolarIconsOutline.shuffle,
          label: 'Перемешать',
          onTap: tracks.isEmpty ? null : () => play(shuffle: true),
        ),
      ],
      [
        SheetAction(
          icon: SolarIconsOutline.penNewSquare,
          label: 'Переименовать',
          onTap: () => _rename(context, ref, playlist),
        ),
        SheetAction(
          icon: SolarIconsOutline.gallery,
          label: playlist.cover == null
              ? 'Поставить обложку'
              : 'Сменить обложку',
          onTap: () => _changeCover(ref, playlist),
        ),
        if (playlist.cover != null)
          SheetAction(
            icon: SolarIconsOutline.galleryRemove,
            label: 'Убрать обложку',
            onTap: () {
              deleteCover(playlist.cover);
              ref
                  .read(libraryProvider.notifier)
                  .setPlaylistCover(playlist.id, null);
            },
          ),
      ],
      [
        SheetAction(
          icon: SolarIconsOutline.trashBinMinimalistic,
          label: 'Удалить плейлист',
          danger: true,
          onTap: () {
            // Своя обложка живёт файлом в каталоге приложения — без этого
            // она останется мусором навсегда.
            deleteCover(playlist.cover);
            ref.read(libraryProvider.notifier).deletePlaylist(playlist.id);
            context.go('/library');
          },
        ),
      ],
    ],
  );
}

/// Выбрать новую обложку. Старую свою картинку удаляем только после удачного
/// выбора: отменил галерею — всё осталось как было.
Future<void> _changeCover(WidgetRef ref, UserPlaylist playlist) async {
  // Стор берём ДО галереи: экран может успеть уйти, пока выбирают картинку, и
  // `ref.read` после await уже не сработает.
  final lib = ref.read(libraryProvider.notifier);
  final picked = await pickCover();
  if (picked == null) return;
  await deleteCover(playlist.cover);
  lib.setPlaylistCover(playlist.id, picked);
}

Future<void> _rename(
  BuildContext context,
  WidgetRef ref,
  UserPlaylist playlist,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: playlist.name),
  );
  if (name == null) return;
  ref.read(libraryProvider.notifier).renamePlaylist(playlist.id, name);
}

/// Диалог переименования. Отдельный виджет ради контроллера: освобождать его
/// сразу после `await showDialog` нельзя — диалог ещё закрывается, и поле
/// падает на `_dependents.isEmpty`.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return AlertDialog(
      backgroundColor: t.blockColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: t.ovlLine),
      ),
      title: Text(
        'Переименовать',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        cursorColor: t.accent,
        style: Theme.of(context).textTheme.titleSmall,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Отмена', style: TextStyle(color: t.text2)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text('Сохранить', style: TextStyle(color: t.accent)),
        ),
      ],
    );
  }
}
