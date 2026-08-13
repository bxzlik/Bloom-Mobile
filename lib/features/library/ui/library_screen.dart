/// Библиотека. Раскладка из референса: лента системных плиток, ряд чипов
/// (`+`, `↻`, фильтры) и сетка в две колонки.
///
/// Своей кнопки импорта здесь нет: как и на десктопе, ссылка вставляется в
/// поле поиска — он же и разбирает её (плейлист, альбом, трек, аккаунт).
/// Кнопка `↻` рядом с `+` — не импорт, а обновление уже импортированного.
///
/// Состав — как в десктопном Bloom: три встроенных раздела (Все треки /
/// Любимые / История) плюс плейлисты и подписки. Отдельных «Альбомов» нет и на
/// десктопе — импортированный альбом лежит среди плейлистов. Папок тоже нет:
/// они приходят от folder_watcher'а, локальных файлов на мобилке пока не бывает.
///
/// Вид системных плиток тоже десктопный — плоский тинт и цветная иконка
/// (`--sys-*-tint` / `--sys-*-ico`), а не заливка в полный цвет.
///
/// Порядок плиток — десктопный `unifiedOrderStore`: четыре режима сортировки,
/// закреплённые сверху, а в режиме «По умолчанию» плитки таскаются пальцем.
/// Долгий тап при этом делит работу: отпустил на месте — меню, потянул —
/// перестановка (см. `_DragCell`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/util/format.dart';
import '../../detail/detail_nav.dart';
import '../../offline/offline_actions.dart';
import '../lib_order_store.dart';
import '../pl_auto_store.dart';
import 'create_playlist_sheet.dart';
import 'pl_auto_sheet.dart';
import 'tracklist_screen.dart';

enum LibFilter { all, playlists, artists }

const _filterLabels = {
  LibFilter.all: 'Все',
  LibFilter.playlists: 'Плейлисты',
  LibFilter.artists: 'Артисты',
};

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

/// Запись общего списка библиотеки — плейлист или артист. Порядок и сортировка
/// работают с ними одинаково, как с `UnifiedEntry` на десктопе.
class _Entry {
  _Entry.playlist(UserPlaylist this.playlist)
    : follow = null,
      key = libKeyOfPlaylist(playlist.id),
      name = playlist.name,
      rank = kLibRankPlaylist;

  _Entry.artist(FollowedArtist this.follow)
    : playlist = null,
      key = libKeyOfArtist(follow.artist.id),
      name = follow.artist.name,
      rank = kLibRankArtist;

  final UserPlaylist? playlist;
  final FollowedArtist? follow;
  final String key;
  final String name;
  final int rank;
}

/// Отступы сетки — по ним же считается ширина плитки для «летящей» копии.
const double _gridPad = 16;
const double _gridGap = 14;

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibFilter _filter = LibFilter.all;

  /// Переставить плитку и запомнить новый порядок целиком.
  void _move(List<_Entry> entries, int from, int to) {
    final keys = entries.map((e) => e.key).toList();
    keys.insert(to, keys.removeAt(from));
    ref.read(libOrderProvider.notifier).setOrder(keys);
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final order = ref.watch(libOrderProvider);

    final showPlaylists =
        _filter == LibFilter.all || _filter == LibFilter.playlists;
    final showArtists =
        _filter == LibFilter.all || _filter == LibFilter.artists;

    // Импортированный альбом — такой же плейлист и стоит в общем ряду.
    final entries = order.arrange(
      [
        if (showPlaylists) ...lib.playlists.map(_Entry.playlist),
        if (showArtists) ...lib.follows.map(_Entry.artist),
      ],
      key: (e) => e.key,
      name: (e) => e.name,
      rank: (e) => e.rank,
    );

    // Таскать плитки можно только там, где порядок и правда пользовательский:
    // в отфильтрованном списке видно не всё, и записать его как порядок целиком
    // нельзя. Ровно та же оговорка стоит у `useSortable` на десктопе.
    final draggable = order.sort == LibSort.manual && _filter == LibFilter.all;
    final tileWidth =
        (MediaQuery.sizeOf(context).width - _gridPad * 2 - _gridGap) / 2;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _SystemTiles(lib: lib)),
          // Просвет вместо снятой строки импорта: чипы иначе липнут к плиткам.
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: _Chips(
              active: _filter,
              onPick: (f) => setState(() => _filter = f),
            ),
          ),
          if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(filter: _filter),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                _gridPad,
                4,
                _gridPad,
                _gridPad,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: _gridGap,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final entry = entries[i];
                  final pinned = order.isPinned(entry.key);
                  final playlist = entry.playlist;
                  final tile = playlist != null
                      ? _SetTile(playlist: playlist, lib: lib, pinned: pinned)
                      : _ArtistTile(followed: entry.follow!, pinned: pinned);
                  return _DragCell(
                    key: ValueKey(entry.key),
                    index: i,
                    width: tileWidth,
                    enabled: draggable,
                    // Закреплённые живут отдельной группой наверху — как
                    // `getGroupRank` на ПК: перемешать их с остальными значило
                    // бы уронить плитку туда, откуда её тут же вынесет вверх.
                    accepts: (from) =>
                        order.isPinned(entries[from].key) == pinned,
                    onMove: (from, to) => _move(entries, from, to),
                    onMenu: () => playlist != null
                        ? showPlaylistMenu(
                            context,
                            ref,
                            playlist,
                            lib.tracksOf(playlist),
                          )
                        : _showArtistMenu(context, ref, entry.follow!),
                    child: tile,
                  );
                }, childCount: entries.length),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ячейка сетки, которую можно взять пальцем и переставить.
///
/// Своя, а не `ReorderableListView`: тот умеет только список, а библиотека —
/// сетка в две колонки. Достаточно пары `LongPressDraggable` + `DragTarget`:
/// плитка уезжает на место той, над которой её отпустили.
///
/// Долгий тап делает две вещи сразу, как на рабочем столе iOS: плитка
/// приподнимается под пальцем, но если её отпустить на месте — открывается
/// меню, а не перестановка. Иначе меню было бы негде держать: своей кнопки на
/// плитке нет, а долгий тап занят.
class _DragCell extends StatefulWidget {
  const _DragCell({
    super.key,
    required this.index,
    required this.width,
    required this.enabled,
    required this.accepts,
    required this.onMove,
    required this.onMenu,
    required this.child,
  });

  final int index;
  final double width;
  final bool enabled;
  final bool Function(int from) accepts;
  final void Function(int from, int to) onMove;
  final VoidCallback onMenu;
  final Widget child;

  @override
  State<_DragCell> createState() => _DragCellState();
}

class _DragCellState extends State<_DragCell> {
  /// Сколько палец прошёл за перетаскивание. Меньше порога — это был не
  /// перенос, а удержание, и вместо перестановки открывается меню.
  double _travel = 0;

  static const double _slop = 12;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return GestureDetector(
        onLongPress: widget.onMenu,
        // Плитка сама ловит тап; удержание должно доходить сюда даже мимо
        // её собственных жестов.
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      );
    }
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) =>
          d.data != widget.index && widget.accepts(d.data),
      onAcceptWithDetails: (d) => widget.onMove(d.data, widget.index),
      builder: (context, candidate, _) {
        final hovered = candidate.isNotEmpty;
        return LongPressDraggable<int>(
          data: widget.index,
          onDragStarted: () {
            _travel = 0;
            HapticFeedback.selectionClick();
          },
          onDragUpdate: (d) => _travel += d.delta.distance,
          onDragEnd: (d) {
            if (!d.wasAccepted && _travel < _slop) widget.onMenu();
          },
          // Копия под пальцем берёт ширину ячейки: в оверлее сетки нет и
          // размер плитке задать больше нечем.
          feedback: Material(
            type: MaterialType.transparency,
            child: Opacity(
              opacity: 0.9,
              child: SizedBox(width: widget.width, child: widget.child),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: widget.child),
          // Цель перетаскивания подсказывается только сжатием плитки: рамка
          // вокруг обложки читалась как чужой элемент.
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: hovered ? 0.94 : 1,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Три встроенных раздела лентой — как на десктопе.
class _SystemTiles extends StatelessWidget {
  const _SystemTiles({required this.lib});

  final LibraryState lib;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        children: [
          // Иконки — те же, что в десктопном сайдбаре: нота, сердце, часы.
          _SystemTile(
            title: 'Все треки',
            count: lib.inLib.length,
            icon: SolarIconsOutline.musicNote,
            tint: t.sysAllTint,
            color: t.sysAllIco,
            onTap: () => context.go('/library/list/all'),
          ),
          const SizedBox(width: 12),
          _SystemTile(
            title: 'Любимые',
            count: lib.favs.length,
            icon: SolarIconsBold.heart,
            tint: t.sysFavTint,
            color: t.sysFavIco,
            onTap: () => context.go('/library/list/fav'),
          ),
          const SizedBox(width: 12),
          _SystemTile(
            title: 'История',
            count: lib.history.length,
            icon: SolarIconsOutline.clockCircle,
            tint: t.sysHistTint,
            color: t.sysHistIco,
            onTap: () => context.go('/library/list/history'),
          ),
        ],
      ),
    );
  }
}

class _SystemTile extends StatelessWidget {
  const _SystemTile({
    required this.title,
    required this.count,
    required this.icon,
    required this.tint,
    required this.color,
    required this.onTap,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color tint;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Material(
      color: tint,
      borderRadius: BorderRadius.circular(t.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 190,
          padding: const EdgeInsets.all(14),
          alignment: Alignment.bottomLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 24, color: color),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.titleMedium),
                  const SizedBox(height: 2),
                  Text(tracksCount(count), style: theme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chips extends ConsumerWidget {
  const _Chips({required this.active, required this.onPick});

  final LibFilter active;
  final ValueChanged<LibFilter> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    // Подсветка кнопок — десктопный `sort-active`: расписание включено,
    // сортировка не «по умолчанию».
    final autoOn = ref.watch(plAutoProvider).enabled;
    final sort = ref.watch(libOrderProvider).sort;

    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Кнопки в `Center`: в горизонтальном списке высота приходит жёсткой,
          // и без него круг растянулся бы в овал на всю высоту ряда.
          Center(
            child: CircleIconButton(
              icon: SolarIconsOutline.addCircle,
              size: kChipHeight,
              iconSize: 22,
              tooltip: 'Создать плейлист',
              onTap: () => showCreatePlaylistSheet(context, ref),
            ),
          ),
          const SizedBox(width: 8),
          Center(
            child: CircleIconButton(
              icon: SolarIconsOutline.refresh,
              size: kChipHeight,
              iconSize: 20,
              tooltip: 'Авто-обновление плейлистов',
              background: autoOn ? t.accent : null,
              color: autoOn ? t.accentText : null,
              onTap: () => showPlAutoSheet(context, ref),
            ),
          ),
          const SizedBox(width: 8),
          Center(
            child: CircleIconButton(
              icon: SolarIconsOutline.sort,
              size: kChipHeight,
              iconSize: 20,
              tooltip: 'Сортировка',
              background: sort == LibSort.manual ? null : t.accent,
              color: sort == LibSort.manual ? null : t.accentText,
              onTap: () => _showSortSheet(context, ref),
            ),
          ),
          const SizedBox(width: 12),
          for (final f in LibFilter.values) ...[
            _FilterChip(
              label: _filterLabels[f]!,
              active: f == active,
              onTap: () => onPick(f),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(width: 8, child: ColoredBox(color: t.bg)),
        ],
      ),
    );
  }
}

/// Выбор сортировки библиотеки — та же нижняя шторка, что у сортировки списка
/// треков (десктопное `LibSortMenu`).
Future<void> _showSortSheet(BuildContext context, WidgetRef ref) {
  final t = context.bloom;
  final active = ref.read(libOrderProvider).sort;
  return showBloomSheet(
    context: context,
    header: const SheetLineHeader(
      cover: null,
      title: 'Сортировка',
      subtitle: 'Библиотека',
    ),
    groups: [
      [
        for (final sort in LibSort.values)
          SheetAction(
            icon: sort.icon,
            label: sort.label,
            onTap: () => ref.read(libOrderProvider.notifier).setSort(sort),
            trailing: sort == active
                ? Icon(SolarIconsBold.checkCircle, size: 18, color: t.accent)
                : null,
          ),
      ],
      // Подсказка про перетаскивание: без неё ручной порядок не найти — он
      // прячется в долгом тапе.
      const [
        SheetAction(
          icon: SolarIconsOutline.infoCircle,
          label: 'В «По умолчанию» плитку можно зажать и перетащить',
        ),
      ],
    ],
  );
}

/// Меню плитки артиста — у плейлиста для этого есть свой `showPlaylistMenu`.
Future<void> _showArtistMenu(
  BuildContext context,
  WidgetRef ref,
  FollowedArtist followed,
) {
  final artist = followed.artist;
  final key = libKeyOfArtist(artist.id);
  final pinned = ref.read(libOrderProvider).isPinned(key);
  final messenger = ScaffoldMessenger.of(context);

  return showBloomSheet(
    context: context,
    backdrop: artist.avatar,
    header: SheetLineHeader(
      cover: artist.avatar,
      title: artist.name,
      subtitle: 'Артист',
      circle: true,
    ),
    groups: [
      [
        SheetAction(
          icon: SolarIconsOutline.pin,
          label: pinned ? 'Открепить' : 'Закрепить',
          onTap: () => ref.read(libOrderProvider.notifier).togglePin(key),
        ),
      ],
      [
        SheetAction(
          icon: SolarIconsBold.userCheckRounded,
          label: 'Отписаться',
          danger: true,
          onTap: () {
            ref.read(libraryProvider.notifier).toggleFollow(artist);
            messenger.toast('Подписка снята');
          },
        ),
      ],
    ],
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final fg = active ? t.accentText : t.text2;
    return Center(
      child: SizedBox(
        height: kChipHeight,
        child: Material(
          color: active ? t.accent : t.pill,
          borderRadius: BorderRadius.circular(999),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: fg),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetTile extends ConsumerStatefulWidget {
  const _SetTile({
    required this.playlist,
    required this.lib,
    required this.pinned,
  });

  final UserPlaylist playlist;
  final LibraryState lib;
  final bool pinned;

  @override
  ConsumerState<_SetTile> createState() => _SetTileState();
}

class _SetTileState extends ConsumerState<_SetTile> {
  /// Метка перелёта обложки в шапку плейлиста — своя у каждой плитки.
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final lib = widget.lib;
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final tracks = lib.tracksOf(playlist);
    // Своей обложки нет — и на плитке, и в шапке списка стоит один и тот же
    // коллаж из треков. Лететь ему незачем: перелёт возит одну картинку, а
    // коллаж на концах разной формы всё равно собирался бы заново.
    final cover = playlist.cover;
    final flight = cover == null || cover.isEmpty
        ? null
        : CoverFlight(tag: _tag, image: cover);

    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        onTap: () => context.go('/library/list/${playlist.id}', extra: flight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Плитки библиотеки крупные — на них скругление обложки заметно
            // острее, чем в каруселях, поэтому радиус здесь свой, побольше.
            Cover(
              url: playlist.cover,
              size: box.maxWidth,
              radius: t.radius * 1.3,
              flight: flight,
              overlay: SetEqualizer(setId: playlist.id),
              covers: tracks.map((track) => track.cover),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.pinned) ...[
                  Icon(SolarIconsBold.pin, size: 13, color: t.accent),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                // Счётчик ужимается первым: тег офлайна короткий и должен
                // оставаться целым, даже если название списка длинное.
                Flexible(
                  child: Text(
                    tracksCount(playlist.trackIds.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall,
                  ),
                ),
                OfflineTag(tracks: tracks, style: theme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistTile extends ConsumerStatefulWidget {
  const _ArtistTile({required this.followed, required this.pinned});

  final FollowedArtist followed;
  final bool pinned;

  @override
  ConsumerState<_ArtistTile> createState() => _ArtistTileState();
}

class _ArtistTileState extends ConsumerState<_ArtistTile> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final artist = widget.followed.artist;
    final avatar = artist.avatar;
    final flight = avatar == null || avatar.isEmpty
        ? null
        : CoverFlight(tag: _tag, image: avatar);

    return GestureDetector(
      onTap: () =>
          openArtist(context, artist.id, initial: artist, flight: flight),
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Cover(
              url: artist.avatar,
              size: box.maxWidth,
              circle: true,
              flight: flight,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.pinned) ...[
                  Icon(SolarIconsBold.pin, size: 13, color: t.accent),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.titleSmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});

  final LibFilter filter;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final text = switch (filter) {
      LibFilter.artists => 'Подписок пока нет',
      LibFilter.playlists => 'Плейлистов пока нет',
      LibFilter.all => 'Создай плейлист или вставь ссылку в поиск',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: t.muted),
        ),
      ),
    );
  }
}
