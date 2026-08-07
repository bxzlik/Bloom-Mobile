/// Очередь воспроизведения — шторка поверх плеера.
///
/// Вид тот же, что у остальных шторок (`bloom_sheet`): обложка текущего трека
/// фоном, затемнённая и без размытия, пункты в чёрном полупрозрачном блоке. Но
/// оболочка своя: там `SingleChildScrollView` с колонкой по содержимому, а
/// здесь список должен быть перетаскиваемым и скроллиться сам.
///
/// Состав по десктопу (`QueueBlock.tsx`): шапка со счётчиком и очисткой,
/// плоский список с drag-reorder, смахивание убирает трек. Разбиение на
/// «Прослушано / Далее» — расширенный вид с ПК — отложено.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/util/format.dart';
import '../player_controller.dart';

/// Высота строки — нужна заранее, чтобы открыть список сразу на играющем треке.
const double _rowHeight = 64;

void showQueueSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    // Корневой навигатор — как у всех наших шторок: иначе таб-бар и миниплеер
    // остаются поверх затемнения.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends ConsumerStatefulWidget {
  const _QueueSheet();

  @override
  ConsumerState<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends ConsumerState<_QueueSheet> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Открываемся на играющем треке, а не в начале очереди: на сотне треков
    // иначе непонятно, где ты находишься. Один экран запаса сверху.
    final index = ref.read(playbackProvider).index;
    _scroll = ScrollController(
      initialScrollOffset: index > 2 ? (index - 2) * _rowHeight : 0,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Ключи строк. Один трек может стоять в очереди дважды (повтор в
  /// плейлисте), а `ReorderableListView` падает на дублях — поэтому к id
  /// дописываем номер вхождения.
  List<Key> _keys(List<Track> queue) {
    final seen = <String, int>{};
    return [
      for (final track in queue)
        ValueKey('${track.id}#${seen[track.id] = (seen[track.id] ?? -1) + 1}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final media = MediaQuery.of(context);
    final state = ref.watch(playbackProvider);
    final ctrl = ref.read(playbackProvider.notifier);
    final queue = state.queue;
    final image = coverImage(state.track?.cover);
    final keys = _keys(queue);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.radius * 1.7),
        ),
        child: Stack(
          children: [
            if (image != null)
              Positioned.fill(child: Image(image: image, fit: BoxFit.cover)),
            Positioned.fill(
              child: ColoredBox(
                color: image == null
                    ? t.bg
                    : Colors.black.withValues(alpha: 0.62),
              ),
            ),
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Handle(),
                  _QueueHeader(
                    count: queue.length,
                    shuffle: state.shuffle,
                    onClear: queue.length > 1 ? ctrl.clearExceptCurrent : null,
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(t.radius),
                        clipBehavior: Clip.antiAlias,
                        child: ReorderableListView.builder(
                          scrollController: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          // Ручка своя, справа: иначе долгий тап уходил бы в
                          // перетаскивание и меню трека не открыть.
                          buildDefaultDragHandles: false,
                          itemCount: queue.length,
                          onReorder: ctrl.reorder,
                          proxyDecorator: (child, _, _) => Material(
                            color: Colors.white.withValues(alpha: 0.06),
                            child: child,
                          ),
                          itemBuilder: (context, i) => Dismissible(
                            key: keys[i],
                            direction: DismissDirection.endToStart,
                            background: const _DismissBackground(),
                            onDismissed: (_) => ctrl.removeAt(i),
                            child: _QueueRow(
                              track: queue[i],
                              index: i,
                              current: i == state.index,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.count,
    required this.shuffle,
    required this.onClear,
  });

  final int count;
  final bool shuffle;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Очередь', style: theme.titleLarge),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(tracksCount(count), style: theme.bodyMedium),
                    // Перемешивание показываем здесь же: порядок в списке при
                    // нём не тот, в котором пойдут треки, и это надо видеть.
                    if (shuffle) ...[
                      const SizedBox(width: 8),
                      Icon(
                        SolarIconsOutline.shuffle,
                        size: 14,
                        color: t.accent,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          CircleIconButton(
            icon: SolarIconsOutline.trashBinMinimalistic,
            iconSize: 20,
            // Как на десктопе: чистим всё, КРОМЕ играющего — обрывать
            // воспроизведение кнопка не должна.
            onTap: onClear,
          ),
        ],
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return ColoredBox(
      color: t.sysFavIco.withValues(alpha: 0.22),
      child: Padding(
        padding: const EdgeInsets.only(right: 22),
        child: Align(
          alignment: Alignment.centerRight,
          child: Icon(
            SolarIconsOutline.trashBinMinimalistic,
            size: 20,
            color: t.sysFavIco,
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({
    required this.track,
    required this.index,
    required this.current,
  });

  final Track track;
  final int index;
  final bool current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(playbackProvider.notifier).jumpTo(index),
        onLongPress: () => showTrackActions(context, ref, track),
        child: SizedBox(
          height: _rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Stack(
                  children: [
                    Cover(url: track.cover, size: 44),
                    // Играющий трек отмечаем прямо на обложке: в длинном списке
                    // одного цвета названия мало.
                    if (current)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(t.radius * 0.6),
                          ),
                          child: Icon(
                            SolarIconsBold.play,
                            size: 18,
                            color: t.accent,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: current
                            ? theme.titleMedium?.copyWith(color: t.accent)
                            : theme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  mmss(track.duration),
                  style: theme.bodySmall?.copyWith(color: t.muted),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      SolarIconsOutline.hamburgerMenu,
                      size: 20,
                      color: t.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
