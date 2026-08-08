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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/util/format.dart';
import '../../detail/detail_nav.dart';
import 'refresh_imported.dart';
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

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibFilter _filter = LibFilter.all;

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);

    final showPlaylists =
        _filter == LibFilter.all || _filter == LibFilter.playlists;
    final showArtists =
        _filter == LibFilter.all || _filter == LibFilter.artists;

    // Импортированный альбом — такой же плейлист и стоит в общем ряду.
    final tiles = <Widget>[
      if (showPlaylists)
        ...lib.playlists.map((p) => _SetTile(playlist: p, lib: lib)),
      if (showArtists) ...lib.follows.map((f) => _ArtistTile(followed: f)),
    ];

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
          if (tiles.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(filter: _filter),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => tiles[i],
                  childCount: tiles.length,
                ),
              ),
            ),
        ],
      ),
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
              onTap: () => _createPlaylist(context, ref),
            ),
          ),
          const SizedBox(width: 8),
          Center(
            child: CircleIconButton(
              icon: SolarIconsOutline.refresh,
              size: kChipHeight,
              iconSize: 20,
              tooltip: 'Обновить импортированные',
              onTap: () => refreshImported(context, ref),
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

Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<({String name, String? cover})>(
    context: context,
    builder: (_) => const _CreatePlaylistDialog(),
  );
  if (result == null) return;
  ref
      .read(libraryProvider.notifier)
      .createPlaylist(result.name, cover: result.cover);
}

/// Диалог «Новый плейлист»: обложка из галереи и название.
///
/// Отдельный виджет, а не пачка полей рядом с `showDialog`: контроллер поля
/// должен жить ровно столько же, сколько диалог. Если освобождать его сразу
/// после `await`, диалог в этот момент ещё доигрывает закрытие и падает на
/// `_dependents.isEmpty`.
class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final _controller = TextEditingController();
  String? _cover;
  bool _picking = false;
  bool _submitted = false;

  @override
  void dispose() {
    // Обложка копируется на диск в момент выбора. Если плейлист так и не
    // создали (отмена, «назад», тап мимо) — файл надо убрать за собой.
    if (!_submitted) deleteCover(_cover);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    final picked = await pickCover();
    if (!mounted) return;
    // Отмена выбора не должна стирать уже выбранную обложку.
    if (picked != null) deleteCover(_cover);
    setState(() {
      _picking = false;
      if (picked != null) _cover = picked;
    });
  }

  void _clear() {
    deleteCover(_cover);
    setState(() => _cover = null);
  }

  void _submit() {
    _submitted = true;
    Navigator.of(context).pop((name: _controller.text, cover: _cover));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: t.blockColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: t.ovlLine),
      ),
      title: Text('Новый плейлист', style: theme.titleLarge),
      // Скролл — чтобы с поднятой клавиатурой на невысоком экране обложка и
      // поле не упирались в края диалога.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _CoverPicker(
                cover: _cover,
                busy: _picking,
                onTap: _pick,
                onClear: _cover == null ? null : _clear,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              cursorColor: t.accent,
              style: theme.titleSmall,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Название',
                hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: t.border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: t.accent),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Отмена', style: TextStyle(color: t.text2)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('Создать', style: TextStyle(color: t.accent)),
        ),
      ],
    );
  }
}

/// Квадрат обложки в диалоге: пустой — пунктир с иконкой галереи, выбранный —
/// сама картинка с крестиком.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.cover,
    required this.busy,
    required this.onTap,
    required this.onClear,
  });

  final String? cover;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  static const double _size = 128;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Stack(
      clipBehavior: Clip.none, // крестик заходит за угол квадрата
      children: [
        GestureDetector(
          onTap: busy ? null : onTap,
          child: cover != null
              ? Cover(url: cover, size: _size)
              : Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: t.ovlBg,
                    borderRadius: BorderRadius.circular(t.radius * 0.72),
                    border: Border.all(color: t.border),
                  ),
                  child: busy
                      ? Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.accent,
                            ),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              SolarIconsOutline.galleryAdd,
                              size: 26,
                              color: t.muted,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Обложка',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(color: t.muted),
                            ),
                          ],
                        ),
                ),
        ),
        if (onClear != null)
          Positioned(
            top: -6,
            right: -6,
            child: CircleIconButton(
              icon: SolarIconsOutline.closeCircle,
              size: 30,
              iconSize: 16,
              background: t.blockColor,
              onTap: onClear,
            ),
          ),
      ],
    );
  }
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
  const _SetTile({required this.playlist, required this.lib});

  final UserPlaylist playlist;
  final LibraryState lib;

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
    // Своей обложки нет — в шапке списка стоит коллаж из треков, и лететь туда
    // заглушке незачем.
    final cover = playlist.cover;
    final flight = cover == null || cover.isEmpty
        ? null
        : CoverFlight(tag: _tag, image: cover);

    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        onTap: () => context.go('/library/list/${playlist.id}', extra: flight),
        // Длинный тап — та же шторка «трёх точек», что на странице плейлиста.
        onLongPress: () =>
            showPlaylistMenu(context, ref, playlist, lib.tracksOf(playlist)),
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
              tracksCount(playlist.trackIds.length),
              maxLines: 1,
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistTile extends StatefulWidget {
  const _ArtistTile({required this.followed});

  final FollowedArtist followed;

  @override
  State<_ArtistTile> createState() => _ArtistTileState();
}

class _ArtistTileState extends State<_ArtistTile> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
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
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.titleSmall,
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
