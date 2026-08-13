/// Режим правки списка библиотеки: чекбоксы у строк, перетаскивание, нижняя
/// панель действий над выделением, правка имени и обложки плейлиста.
///
/// Всё, что меняет САМ список — состав, порядок, имя, обложку, — копится в
/// черновике и записывается разом по ✓; ✕ выбрасывает черновик целиком. А вот
/// «в плейлист» и «в любимые» пишут в ДРУГИЕ списки, и откатывать их этим ✕
/// было бы нечем — они применяются сразу.
///
/// Что значит «убрать» — зависит от списка: из плейлиста трек просто уходит, из
/// «Любимых» снимается лайк, из «Истории» пропадает запись, а из «Всех треков»
/// он удаляется НАСКВОЗЬ (как пункт «Удалить трек»), поэтому там перед записью
/// ещё и переспрашиваем.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../features/offline/offline_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/sticky_hero.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/util/format.dart';
import 'list_hero.dart';

class ListEditor extends ConsumerStatefulWidget {
  const ListEditor({
    super.key,
    required this.listId,
    required this.title,
    required this.playlist,
    required this.tracks,
    required this.onClose,
  });

  /// `all` / `fav` / `history` либо id пользовательского плейлиста.
  final String listId;

  final String title;

  /// `null` — встроенный раздел: имя и обложка у него не правятся.
  final UserPlaylist? playlist;

  /// Исходный состав в его собственном порядке — БЕЗ поиска и сортировки:
  /// править половину списка, да ещё и не в том порядке, нельзя.
  final List<Track> tracks;

  /// Выйти из режима правки — и по ✓, и по ✕.
  final VoidCallback onClose;

  @override
  ConsumerState<ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends ConsumerState<ListEditor> {
  late final List<String> _idsWas = [for (final t in widget.tracks) t.id];

  late final List<Track> _tracks = [...widget.tracks];
  late String _name = widget.title;
  late String? _cover = widget.playlist?.cover;

  final Set<String> _selected = {};

  /// Идёт правка названия — нижняя панель на это время становится полем ввода.
  bool _renaming = false;

  UserPlaylist? get _playlist => widget.playlist;

  List<String> get _ids => [for (final t in _tracks) t.id];

  List<Track> get _selectedTracks => [
    for (final t in _tracks)
      if (_selected.contains(t.id)) t,
  ];

  bool get _allSelected =>
      _tracks.isNotEmpty && _selected.length == _tracks.length;

  bool get _dirty =>
      _name != widget.title ||
      _cover != _playlist?.cover ||
      !listEquals(_ids, _idsWas);

  // ── Правка ────────────────────────────────────────────────────────────────

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _toggleAll() => setState(() {
    final all = _allSelected;
    _selected.clear();
    if (!all) _selected.addAll(_ids);
  });

  void _reorder(int from, int to) => setState(() {
    // Индекс вставки считается ДО изъятия строки — всё, что ниже, уже сдвинуто.
    if (to > from) to--;
    _tracks.insert(to, _tracks.removeAt(from));
  });

  void _removeSelected() => setState(() {
    _tracks.removeWhere((t) => _selected.contains(t.id));
    _selected.clear();
  });

  /// Лайк выделенному — сразу, не в черновик: «Любимые» это другой список.
  void _favSelected() {
    final lib = ref.read(libraryProvider.notifier);
    final was = ref.read(libraryProvider);
    final batch = _selectedTracks;
    var added = 0;
    for (final track in batch) {
      if (was.isFav(track.id)) continue;
      lib.toggleFav(track);
      added++;
    }
    setState(_selected.clear);
    showToast(
      context,
      added == 0 ? 'Уже в любимых' : 'В любимые: ${tracksCount(added)}',
      kind: added == 0 ? ToastKind.warn : ToastKind.success,
    );
  }

  Future<void> _addSelectedToPlaylist() async {
    final batch = _selectedTracks;
    await showAddTracksToPlaylistSheet(context, ref, batch, newName: _name);
    if (!mounted) return;
    setState(_selected.clear);
  }

  /// Новая обложка сохраняется файлом сразу, поэтому предыдущий ВЫБОР (не
  /// исходную обложку плейлиста) чистим тут же: он уже никому не нужен.
  Future<void> _pickCover() async {
    final picked = await pickCover();
    if (picked == null || !mounted) return;
    final stale = _cover != _playlist?.cover ? _cover : null;
    setState(() => _cover = picked);
    unawaited(deleteCover(stale));
  }

  // ── Выход ─────────────────────────────────────────────────────────────────

  Future<void> _commit() async {
    final lib = ref.read(libraryProvider.notifier);
    final left = _ids.toSet();
    final gone = [
      for (final id in _idsWas)
        if (!left.contains(id)) id,
    ];

    switch (widget.listId) {
      case 'all':
        // Тут удаление НАСКВОЗЬ, поэтому спрашиваем — как `confirm()` в
        // десктопном `deleteUploadedTrack`.
        if (gone.isNotEmpty && !await _confirmPurge(gone.length)) return;
        // Офлайн-копии удалённых треков — мусор, на который никто не сошлётся.
        final offline = ref.read(offlineProvider.notifier);
        for (final id in gone) {
          unawaited(offline.remove(id));
        }
        lib.setLibraryTracks(_ids);
      case 'fav':
        lib.setFavTracks(_ids);
      case 'history':
        lib.setHistoryTracks(_ids);
      default:
        final pl = _playlist;
        if (pl != null) {
          lib.setPlaylistTracks(pl.id, _ids);
          if (_name.trim().isNotEmpty) lib.renamePlaylist(pl.id, _name);
          if (_cover != pl.cover) {
            lib.setPlaylistCover(pl.id, _cover);
            // Старая своя картинка живёт файлом в каталоге приложения.
            unawaited(deleteCover(pl.cover));
          }
        }
    }
    widget.onClose();
  }

  Future<void> _cancel() async {
    if (_dirty && !await _confirmDrop()) return;
    // Выбранная, но не записанная обложка — файл, на который теперь никто не
    // ссылается.
    if (_cover != _playlist?.cover) unawaited(deleteCover(_cover));
    widget.onClose();
  }

  Future<bool> _confirmPurge(int count) => _ask(
    title: 'Удалить ${tracksCount(count)}?',
    body: 'Они пропадут из библиотеки, любимых, плейлистов и истории.',
    yes: 'Удалить',
    danger: true,
  );

  Future<bool> _confirmDrop() => _ask(
    title: 'Отменить правку?',
    body: 'Всё, что вы наменяли в списке, не сохранится.',
    yes: 'Отменить',
    danger: true,
  );

  Future<bool> _ask({
    required String title,
    required String body,
    required String yes,
    bool danger = false,
  }) async {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.blockColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius),
          side: BorderSide(color: t.ovlLine),
        ),
        title: Text(title, style: theme.titleLarge),
        content: Text(body, style: theme.bodyMedium?.copyWith(color: t.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Назад', style: TextStyle(color: t.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              yes,
              style: TextStyle(color: danger ? t.sysFavIco : t.accent),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ── Раскладка ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final width = MediaQuery.sizeOf(context).width;

    return PopScope(
      // Системное «назад» в режиме правки — это ✕, а не выход со страницы.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _EditHero(
                listId: widget.listId,
                name: _name,
                cover: _cover,
                tracks: _tracks,
                // Своя обложка и своё имя есть только у плейлиста.
                editable: _playlist != null,
                height: width * 0.62,
                onCancel: _cancel,
                onDone: _commit,
                onCover: _pickCover,
                onRename: () => setState(() => _renaming = true),
              ),
              SliverPadding(
                // Снизу — место под плавающую панель: последняя строка не
                // должна оставаться под ней.
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 92),
                sliver: SliverReorderableList(
                  itemCount: _tracks.length,
                  onReorder: _reorder,
                  proxyDecorator: (child, _, _) => Material(
                    color: t.pill,
                    elevation: 6,
                    borderRadius: BorderRadius.circular(t.radius * 0.85),
                    child: child,
                  ),
                  itemBuilder: (context, i) {
                    final track = _tracks[i];
                    return _EditRow(
                      key: ValueKey(track.id),
                      index: i,
                      track: track,
                      selected: _selected.contains(track.id),
                      onTap: () => _toggle(track.id),
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _renaming
                ? _RenameBar(
                    initial: _name,
                    onCancel: () => setState(() => _renaming = false),
                    onDone: (value) => setState(() {
                      final name = value.trim();
                      if (name.isNotEmpty) _name = name;
                      _renaming = false;
                    }),
                  )
                : _EditBar(
                    count: _selected.length,
                    allSelected: _allSelected,
                    // В «Любимых» лайк уже стоит у каждой строки — там его
                    // место занимает корзина, она же «снять лайк».
                    canFav: widget.listId != 'fav',
                    onToggleAll: _tracks.isEmpty ? null : _toggleAll,
                    onAdd: _addSelectedToPlaylist,
                    onFav: _favSelected,
                    onRemove: _removeSelected,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Шапка режима правки: та же обложка, но вместо «назад/сортировка/поиск» —
/// ✕ и ✓, по центру кнопка выбора картинки, у названия карандаш. Ряда
/// «Воспроизвести» здесь нет, но высота шапки та же, что и на обычном экране:
/// вход в правку не должен её дёргать. Название с подписью просто опускаются
/// на освободившееся место — к нижнему краю обложки.
///
/// Как и обычная шапка списка — слайвер: ряд ✕/✓ остаётся у верхнего края.
class _EditHero extends StatelessWidget {
  const _EditHero({
    required this.listId,
    required this.name,
    required this.cover,
    required this.tracks,
    required this.editable,
    required this.height,
    required this.onCancel,
    required this.onDone,
    required this.onCover,
    required this.onRename,
  });

  final String listId;
  final String name;
  final String? cover;
  final List<Track> tracks;

  /// Можно ли править имя и обложку (только у плейлиста).
  final bool editable;

  final double height;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onCover;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return StickyHero(
      // Те же `+ 76`, что и у обычной шапки списка (ряд «Воспроизвести»): её
      // высота считается от одной и той же [height].
      height: height + 76,
      background: Stack(
        fit: StackFit.expand,
        children: [
          HeroCover(
            child: ListHeroBackground(
              listId: listId,
              cover: cover,
              tracks: tracks,
            ),
          ),
          if (editable)
            Center(
              child: GlassIconButton(
                icon: SolarIconsOutline.gallery,
                size: 66,
                iconSize: 28,
                onTap: onCover,
              ),
            ),
        ],
      ),
      // ✕ и ✓ остаются наверху: закончить правку длинного списка иначе можно
      // только пролистав его обратно.
      barHeight: kHeaderControl,
      bar: Row(
        children: [
          GlassIconButton(icon: Icons.close_rounded, onTap: onCancel),
          const Spacer(),
          GlassIconButton(icon: Icons.check_rounded, onTap: onDone),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.headlineSmall?.copyWith(fontSize: 30),
                ),
              ),
              if (editable) ...[
                const SizedBox(width: 8),
                // Карандаш прямо у названия, без подложки: это часть
                // заголовка, а не ещё одна кнопка шапки.
                InkResponse(
                  onTap: onRename,
                  radius: 22,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      SolarIconsOutline.pen,
                      size: 21,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(tracksCount(tracks.length), style: theme.bodyMedium),
        ],
      ),
    );
  }
}

/// Строка списка в режиме правки: чекбокс, обложка, название и длительность.
/// Тап по строке выделяет её, а не заводит трек, — играть из режима правки
/// нечего. Тянучка — обложка, как в обычном списке и в очереди: отдельной ручке
/// в строке уже нечего делать.
class _EditRow extends StatelessWidget {
  const _EditRow({
    super.key,
    required this.index,
    required this.track,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final Track track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            _Check(on: selected),
            const SizedBox(width: 12),
            ReorderableDelayedDragStartListener(
              index: index,
              child: Cover(url: track.cover, size: 52),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: t.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            DurationPill(track: track, active: false),
          ],
        ),
      ),
    );
  }
}

/// Квадратик выбора. Свой, а не material `Checkbox`: тому не отключить
/// служебные отступы и он тянет за собой свою палитру.
class _Check extends StatelessWidget {
  const _Check({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: on ? t.accent : Colors.transparent,
        border: Border.all(color: on ? t.accent : t.muted, width: 1.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: on
          ? Icon(Icons.check_rounded, size: 15, color: t.accentText)
          : null,
    );
  }
}

/// Плавающая панель режима правки. Пока никого не выбрали, в ней только
/// «выбрать все» — остальным действиям не над чем работать.
class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.count,
    required this.allSelected,
    required this.canFav,
    required this.onToggleAll,
    required this.onAdd,
    required this.onFav,
    required this.onRemove,
  });

  final int count;
  final bool allSelected;
  final bool canFav;
  final VoidCallback? onToggleAll;
  final VoidCallback onAdd;
  final VoidCallback onFav;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final some = count > 0;

    return _BarShell(
      child: Row(
        children: [
          if (some)
            Text('$count', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          _BarIcon(
            icon: allSelected
                ? SolarIconsBold.checklistMinimalistic
                : SolarIconsOutline.checklistMinimalistic,
            color: allSelected ? t.accent : null,
            onTap: onToggleAll,
          ),
          if (some) ...[
            _BarIcon(icon: SolarIconsOutline.plus, onTap: onAdd),
            if (canFav) _BarIcon(icon: SolarIconsOutline.heart, onTap: onFav),
            const SizedBox(width: 4),
            _BarIcon(
              icon: SolarIconsOutline.trashBinMinimalistic,
              color: t.sysFavIco,
              background: t.sysFavIco.withValues(alpha: 0.16),
              onTap: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

/// Та же панель, ставшая полем ввода: ✕ бросает правку названия, ✓ принимает.
class _RenameBar extends StatefulWidget {
  const _RenameBar({
    required this.initial,
    required this.onCancel,
    required this.onDone,
  });

  final String initial;
  final VoidCallback onCancel;
  final ValueChanged<String> onDone;

  @override
  State<_RenameBar> createState() => _RenameBarState();
}

class _RenameBarState extends State<_RenameBar> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return _BarShell(
      child: Row(
        children: [
          _BarIcon(icon: Icons.close_rounded, onTap: widget.onCancel),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              cursorColor: t.accent,
              style: Theme.of(context).textTheme.titleMedium,
              textInputAction: TextInputAction.done,
              onSubmitted: widget.onDone,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _BarIcon(
            icon: Icons.check_rounded,
            onTap: () => widget.onDone(_controller.text),
          ),
        ],
      ),
    );
  }
}

/// Пилюля, в которой живут обе нижние панели.
class _BarShell extends StatelessWidget {
  const _BarShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      // Сплошная подложка «хрома», как у кнопок шапки: панель висит над
      // списком, и просвечивающие сквозь неё строки читались бы кашей.
      color: t.pill,
      elevation: 8,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.onTap,
    this.color,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  /// Своя заливка — у корзины: удаление в этой панели единственное опасное.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      color: background ?? Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 23,
            color: onTap == null ? t.muted : (color ?? t.text),
          ),
        ),
      ),
    );
  }
}
