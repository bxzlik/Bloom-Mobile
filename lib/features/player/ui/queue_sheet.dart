/// Очередь воспроизведения — шторка поверх плеера.
///
/// Оболочка своя, не `bloom_sheet`: очередь — это длинный список, а не десяток
/// пунктов. Поэтому ни обложки фоном, ни блока вокруг списка — сплошной фон
/// темы, строки ровно те же, что в плейлистах (`TrackRow`), и шторка тянется
/// до самого верха экрана, а не до доли высоты.
///
/// Состав по десктопу (`QueueBlock.tsx`): шапка со счётчиком и очисткой,
/// плоский список с drag-reorder за обложку, смахивание убирает трек.
/// Разбиение на «Прослушано / Далее» — расширенный вид с ПК — отложено.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/util/format.dart';
import '../player_controller.dart';

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
      initialScrollOffset: index > 2 ? (index - 2) * kTrackRowHeight : 0,
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
    final keys = _keys(queue);

    // Смахнули последний трек — очередь пуста, показывать в шторке нечего.
    // Плеер под нами закроется сам (см. `FullPlayerPage`), но закрыться первой
    // должна шторка: действие произошло в ней.
    ref.listen(playbackProvider, (_, next) {
      if (next.queue.isNotEmpty) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
    });

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.radius * 1.7),
        ),
        child: ColoredBox(
          color: t.bg,
          child: SafeArea(
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
                  child: ReorderableListView.builder(
                    scrollController: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    // Ручек по умолчанию нет: тянучка своя — на обложке, как в
                    // десктопном `QueueBlock` (handle на `.trcov`).
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
              ],
            ),
          ),
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
                    // Перемешивание показываем здесь же: список ниже уже стоит
                    // в перемешанном порядке, и надо понимать, почему.
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
    return Material(
      color: Colors.transparent,
      child: TrackRowShell(
        track: track,
        // Не по id: один трек может стоять в очереди дважды, играет — тот, что
        // стоит на текущей позиции.
        active: current,
        onTap: () => ref.read(playbackProvider.notifier).jumpTo(index),
        onMenu: () => showTrackActions(context, ref, track),
        dragIndex: index,
      ),
    );
  }
}
