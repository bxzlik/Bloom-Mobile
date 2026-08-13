/// Список треков раздела библиотеки: встроенные «Все треки» / «Любимые» /
/// «История» и пользовательские плейлисты — один экран на всё.
///
/// Раскладка: hero-обложка во всю ширину, название и счётчик поверх неё, ряд
/// «Воспроизвести» + шафл + правка, ниже трек-лист. Карандаш переводит экран в
/// режим правки — он живёт в [ListEditor] и заменяет собой всю страницу.
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
import '../../../features/offline/file_download.dart';
import '../../../features/offline/offline_actions.dart';
import '../../../features/offline/offline_store.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/sticky_hero.dart';
import '../../../shared/util/format.dart';
import '../lib_order_store.dart';
import '../refresh_playlist.dart';
import 'list_edit.dart';
import 'list_hero.dart';

/// Сортировка трек-листа — те же режимы, что на десктопе.
enum TrackSort {
  manual('По порядку', SolarIconsOutline.playlistMinimalistic),
  name('По названию', SolarIconsOutline.sortByAlphabet),
  artist('По исполнителю', SolarIconsOutline.userRounded),
  duration('По длительности', SolarIconsOutline.sortByTime);

  const TrackSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

class TracklistScreen extends ConsumerStatefulWidget {
  const TracklistScreen({super.key, required this.listId, this.flight});

  /// `all` / `fav` / `history` либо id пользовательского плейлиста.
  final String listId;

  /// Обложка плитки библиотеки, с которой сюда пришли: она перелетает в шапку.
  /// `null` — у плитки обложки не было (в шапке коллаж или тинт раздела) или
  /// список открыт не с плитки.
  final CoverFlight? flight;

  @override
  ConsumerState<TracklistScreen> createState() => _TracklistScreenState();
}

class _TracklistScreenState extends ConsumerState<TracklistScreen> {
  TrackSort _sort = TrackSort.manual;
  bool _searchOpen = false;
  String _query = '';

  /// Экран отдан [ListEditor]: список правится, а не листается.
  bool _editing = false;

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

    if (_editing) {
      return ListEditor(
        listId: widget.listId,
        title: title,
        playlist: playlist,
        // Правится ВЕСЬ список в его собственном порядке: сортировка и поиск
        // на входе в режим сбрасываются.
        tracks: source,
        onClose: () => setState(() => _editing = false),
      );
    }

    final tracks = _apply(source);
    final keys = _canReorder ? _keysFor(tracks) : const <Key>[];
    final width = MediaQuery.of(context).size.width;

    return CustomScrollView(
      slivers: [
        _Hero(
          listId: widget.listId,
          title: title,
          playlist: playlist,
          tracks: source,
          visible: tracks,
          // Летим только на свою обложку: коллаж 2×2 собирается из чужих
          // картинок, и обложке плитки в нём места нет.
          flight: playlist?.cover == null ? null : widget.flight,
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
          onEdit: () => setState(() {
            _editing = true;
            _searchOpen = false;
            _query = '';
            _sort = TrackSort.manual;
          }),
        ),
        // Ход пакетной загрузки больше не строка под шапкой: он в тосте
        // (`BatchToastBody`) и виден с любого экрана, а не только отсюда.
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
        // Свой порядок списка — строки можно двигать: зажать обложку и тащить,
        // как в очереди и на десктопе.
        else if (_canReorder)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            sliver: SliverReorderableList(
              itemCount: tracks.length,
              onReorder: (from, to) => _reorder(source, from, to),
              proxyDecorator: (child, _, _) => Material(
                color: t.pill,
                elevation: 6,
                borderRadius: BorderRadius.circular(t.radius * 0.85),
                child: child,
              ),
              itemBuilder: (context, i) => TrackRow(
                key: keys[i],
                track: tracks[i],
                queue: tracks,
                index: i,
                sourceId: widget.listId,
                dragIndex: i,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            sliver: SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) => TrackRow(
                track: tracks[i],
                queue: tracks,
                index: i,
                sourceId: widget.listId,
              ),
            ),
          ),
      ],
    );
  }

  /// Тянуть строки можно, только когда на экране собственный порядок списка:
  /// при сортировке и поиске видно не его, и перестановка легла бы не туда.
  bool get _canReorder => _sort == TrackSort.manual && _query.isEmpty;

  /// Ключи строк: один трек может стоять в списке дважды, а `ReorderableList`
  /// на дублях падает — дописываем номер вхождения (как в очереди).
  List<Key> _keysFor(List<Track> tracks) {
    final seen = <String, int>{};
    return [
      for (final track in tracks)
        ValueKey('${track.id}#${seen[track.id] = (seen[track.id] ?? -1) + 1}'),
    ];
  }

  /// Новый порядок уезжает в хранилище целиком — теми же ручками, что и режим
  /// правки: состав не меняется, меняются только места.
  void _reorder(List<Track> source, int from, int to) {
    // Индекс вставки считается ДО изъятия строки — всё, что ниже, уже сдвинуто.
    if (to > from) to--;
    final next = [...source];
    next.insert(to, next.removeAt(from));
    final ids = [for (final track in next) track.id];
    final lib = ref.read(libraryProvider.notifier);
    switch (widget.listId) {
      case 'all':
        lib.setLibraryTracks(ids);
      case 'fav':
        lib.setFavTracks(ids);
      case 'history':
        lib.setHistoryTracks(ids);
      default:
        lib.setPlaylistTracks(widget.listId, ids);
    }
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
    required this.flight,
    required this.height,
    required this.sort,
    required this.onSort,
    required this.searchOpen,
    required this.query,
    required this.onToggleSearch,
    required this.onQuery,
    required this.onEdit,
  });

  final String listId;
  final String title;
  final UserPlaylist? playlist;

  /// Полный состав — по нему считается счётчик и запускается воспроизведение.
  final List<Track> tracks;

  /// То, что реально показано (после поиска и сортировки).
  final List<Track> visible;

  /// Обложка плитки, с которой пришли, — цель перелёта.
  final CoverFlight? flight;

  final double height;
  final TrackSort sort;
  final ValueChanged<TrackSort> onSort;
  final bool searchOpen;
  final String query;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQuery;

  /// Уйти в режим правки — карандаш в ряду действий.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    // Обложка для шторок: у плейлиста своя, у встроенных разделов её роль
    // играет первый трек — так же, как в фоне hero.
    final cover =
        playlist?.cover ?? (tracks.isEmpty ? null : tracks.first.cover);

    return StickyHero(
      height: height + 76,
      flying: flight != null,
      // Обложка на всю шапку, включая ряд действий: её скруглённый нижний
      // край и есть граница со списком.
      background: HeroCover(
        child: CoverHero(
          tag: flight?.tag,
          shape: BorderRadius.vertical(bottom: Radius.circular(t.radius * 1.5)),
          child: ListHeroBackground(
            listId: listId,
            cover: playlist?.cover,
            tracks: tracks,
          ),
        ),
      ),
      // Открытый поиск едет вместе с кнопками: искать по списку, глядя на него,
      // и есть смысл только в прокрученном виде.
      barHeight: searchOpen ? kHeaderControl * 2 + 10 : kHeaderControl,
      bar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassIconButton(
                icon: SolarIconsOutline.arrowLeft,
                onTap: () => context.go('/library'),
              ),
              const SizedBox(width: 8),
              _SortButton(
                sort: sort,
                onSort: onSort,
                title: title,
                cover: cover,
              ),
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
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.headlineSmall?.copyWith(fontSize: 30),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(tracksCount(tracks.length), style: theme.bodyMedium),
              // Сколько из списка уже на устройстве — та же подпись, что в
              // шапке плейлиста на десктопе. Только у плейлиста: у «Всех
              // треков» / «Любимых» / «Истории» на ПК её нет.
              if (playlist != null) OfflineTag(tracks: tracks),
            ],
          ),
          const SizedBox(height: 14),
          _Actions(
            listId: listId,
            tracks: visible.isEmpty ? tracks : visible,
            onEdit: onEdit,
          ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.sort,
    required this.onSort,
    required this.title,
    required this.cover,
  });

  final TrackSort sort;
  final ValueChanged<TrackSort> onSort;

  /// Название списка — уходит в подпись шапки шторки.
  final String title;
  final String? cover;

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: SolarIconsOutline.tuning_2,
      onTap: () => showSortSheet(context, title, cover, sort, onSort),
    );
  }
}

/// Выбор сортировки списка — такая же нижняя шторка, как по удержанию трека, а
/// не всплывающее меню: на телефоне до низа экрана рука достаёт, до угла шапки
/// нет.
Future<void> showSortSheet(
  BuildContext context,
  String title,
  String? cover,
  TrackSort sort,
  ValueChanged<TrackSort> onSort,
) {
  final t = context.bloom;
  return showBloomSheet(
    context: context,
    backdrop: cover,
    header: SheetLineHeader(cover: cover, title: 'Сортировка', subtitle: title),
    groups: [
      [
        for (final s in TrackSort.values)
          SheetAction(
            icon: s.icon,
            label: s.label,
            onTap: () => onSort(s),
            trailing: s == sort
                ? Icon(SolarIconsBold.checkCircle, size: 18, color: t.accent)
                : null,
          ),
      ],
    ],
  );
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
  const _Actions({
    required this.listId,
    required this.tracks,
    required this.onEdit,
  });

  /// `all` / `fav` / `history` / id плейлиста — он же источник очереди.
  final String listId;

  final List<Track> tracks;

  /// Карандаш есть у ЛЮБОГО списка библиотеки: править состав и порядок можно
  /// и во встроенных разделах, просто имя с обложкой там не свои.
  final VoidCallback onEdit;

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
                  ? () => ref
                        .read(playbackProvider.notifier)
                        .playQueue(tracks, 0, sourceId: listId)
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
              ? () => ref
                    .read(playbackProvider.notifier)
                    .playQueueShuffled(tracks, sourceId: listId)
              : null,
        ),
        const SizedBox(width: 10),
        GlassIconButton(
          icon: SolarIconsOutline.penNewSquare,
          size: 46,
          onTap: onEdit,
        ),
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
    if (shuffle) {
      ctrl.playQueueShuffled(tracks, sourceId: playlist.id);
    } else {
      ctrl.playQueue(tracks, 0, sourceId: playlist.id);
    }
  }

  // У плейлиста без своей обложки её роль играет первый трек — так же, как в
  // hero экрана.
  final cover = playlist.cover ?? (tracks.isEmpty ? null : tracks.first.cover);

  // Закреплённость читаем тут же, до открытия: в обработчиках пунктов `watch`
  // уже недоступен.
  final orderKey = libKeyOfPlaylist(playlist.id);
  final pinned = ref.read(libOrderProvider).isPinned(orderKey);

  // Офлайн-состав считаем до открытия шторки: в её обработчиках `watch` уже
  // недоступен, а `read` внутри пункта дал бы состояние на момент нажатия.
  final offlineStatus = listOfflineState(
    ref.read(offlineProvider),
    ref.read(offlineProvider.notifier),
    tracks,
  );
  final messenger = ScaffoldMessenger.of(context);

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
        // Пакет ЭТОГО плейлиста качается прямо сейчас — единственное, что
        // здесь уместно, это его остановить. Чужой пакет пунктов не меняет:
        // остановить его отсюда было бы неожиданно, а `downloadAll` сам
        // ответит, что уже качает другой список.
        if (ref.read(offlineProvider).batch?.sourceId == playlist.id)
          SheetAction(
            icon: SolarIconsOutline.closeCircle,
            label: 'Прервать сохранение',
            onTap: () => ref.read(offlineProvider.notifier).cancelBatch(),
          )
        // Скачать целиком есть смысл, пока в списке остались несохранённые
        // треки; когда всё на устройстве — пункт становится «убрать».
        else if (offlineStatus.total > 0) ...[
          SheetAction(
            icon: offlineStatus.all
                ? SolarIconsBold.checkCircle
                : SolarIconsOutline.diskette,
            label: offlineStatus.all
                ? 'Убрать из офлайна'
                : 'Слушать офлайн (${offlineStatus.total - offlineStatus.cached})',
            onTap: () => offlineStatus.all
                ? removeListOffline(messenger, ref, tracks)
                : downloadListOffline(messenger, ref, playlist.id, tracks),
          ),
          if (canSaveFiles)
            SheetAction(
              icon: SolarIconsOutline.downloadMinimalistic,
              label: 'Скачать файлами (${offlineStatus.total})',
              onTap: () => saveListFiles(messenger, ref, playlist.id, tracks),
            ),
        ],
        // Тот же «Обновить треки», что кнопкой в шапке: в шторку он попадает
        // и с плитки библиотеки, где шапки нет.
        if (playlist.sourceUrl != null)
          SheetAction(
            icon: SolarIconsOutline.refresh,
            label: 'Обновить треки',
            onTap: () => refreshOnePlaylist(messenger, ref, playlist),
          ),
        SheetAction(
          icon: SolarIconsOutline.pin,
          label: pinned ? 'Открепить' : 'Закрепить',
          onTap: () => ref.read(libOrderProvider.notifier).togglePin(orderKey),
        ),
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
            // Удаляем сразу и даём «Отменить» в тосте — как `PlMenu` на ПК:
            // плейлист это всего лишь список id, вернуть его дёшево, а сами
            // треки в библиотеке не трогаются.
            final lib = ref.read(libraryProvider.notifier);
            final index = ref
                .read(libraryProvider)
                .playlists
                .indexWhere((p) => p.id == playlist.id);
            lib.deletePlaylist(playlist.id);
            context.go('/library');
            messenger.toast(
              'Плейлист «${playlist.name}» удалён',
              action: ToastAction(
                fn: () => lib.restorePlaylist(index, playlist),
                // Своя обложка живёт файлом в каталоге приложения; удаляем её
                // только когда отменять уже нечего, иначе возвращённый
                // плейлист остался бы без картинки.
                onExpire: () => deleteCover(playlist.cover),
              ),
            );
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
