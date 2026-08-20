/// Очередь воспроизведения — шторка поверх плеера.
///
/// Оболочка своя, не `bloom_sheet`: очередь — это длинный список, а не десяток
/// пунктов. Поэтому ни обложки фоном, ни блока вокруг списка — сплошной фон
/// темы, строки ровно те же, что в плейлистах (`TrackRow`), и шторка тянется
/// до самого верха экрана, а не до доли высоты.
///
/// Состав по десктопу (`QueueBlock.tsx`): шапка со счётчиком и очисткой,
/// плоский список с drag-reorder за обложку, смахивание убирает трек. Что
/// именно делает смахивание, задаётся в настройках («Свайпы» → «Очередь»);
/// по умолчанию оба направления удаляют, как в референсе.
/// Разбиение на «Прослушано / Далее» — расширенный вид с ПК — отложено.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../features/wave/wave_actions.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/ui/track_swipes.dart';
import '../player_controller.dart';

void showQueueSheet(BuildContext context) {
  // Корневой навигатор и стекло затемнения — общие у всех наших шторок
  // (`showBloomModal`): иначе таб-бар и миниплеер остаются поверх затемнения.
  showBloomModal<void>(context: context, builder: (_) => const _QueueSheet());
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
        child: SheetSurface(
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetHandle(),
                _QueueHeader(
                  count: queue.length,
                  shuffle: state.shuffle,
                  onClear: queue.length > 1 ? ctrl.clearExceptCurrent : null,
                  // «Похожие на очередь» продолжают её подбором. Шторку
                  // закрываем: очередь под ней сменится целиком, и стоять на
                  // её старом списке уже незачем.
                  onWave: queue.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          startWaveFromQueue(context, ref, queue);
                        },
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
                    itemBuilder: (context, i) => TrackSwipe(
                      key: keys[i],
                      zone: SwipeZone.queue,
                      track: queue[i],
                      queueIndex: i,
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

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.count,
    required this.shuffle,
    required this.onClear,
    required this.onWave,
  });

  final int count;
  final bool shuffle;
  final VoidCallback? onClear;
  final VoidCallback? onWave;

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
                Text(context.l.playerQueue, style: theme.titleLarge),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(context.l.tracksCount(count), style: theme.bodyMedium),
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
            icon: SolarIconsOutline.playStream,
            iconSize: 20,
            onTap: onWave,
          ),
          const SizedBox(width: 8),
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
        // Номер строки, а не поиск по id: один трек может стоять в очереди
        // дважды, и «Убрать из очереди» обязано убрать именно эту строку.
        onMenu: () => showTrackActions(context, ref, track, queueIndex: index),
        dragIndex: index,
      ),
    );
  }
}
