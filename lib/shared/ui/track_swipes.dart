/// Свайпы по треку: что происходит, когда строку списка или карточку плеера
/// утянули в сторону.
///
/// Одно место на все четыре зоны ([SwipeZone]) — строка библиотеки, строка
/// очереди, миниплеер и плеер отличаются только тем, откуда берётся трек и что
/// значит «удалить». Сам жест рисуют [SwipeRow] (списки) и `TrackFlick`
/// (плеер).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/store/library_store.dart';
import '../../features/library/local_tracks.dart';
import '../../features/offline/offline_actions.dart';
import '../../features/offline/offline_store.dart';
import '../../features/player/player_controller.dart';
import '../../features/player/track_swap_dir.dart';
import '../../features/settings/swipe_store.dart';
import 'bloom_toast.dart';
import 'swipe_row.dart';

/// Значок действия — он же в настройках, в списке выбора и на плашке.
IconData swipeActionIcon(SwipeAction action) => switch (action) {
  SwipeAction.none => SolarIconsOutline.forbiddenCircle,
  SwipeAction.like => SolarIconsOutline.heart,
  SwipeAction.queue => SolarIconsOutline.addCircle,
  SwipeAction.playNext => SolarIconsOutline.skipNext,
  SwipeAction.next => SolarIconsOutline.skipNext,
  SwipeAction.prev => SolarIconsOutline.skipPrevious,
  SwipeAction.download => SolarIconsOutline.diskette,
  SwipeAction.delete => SolarIconsOutline.trashBinMinimalistic,
};

String swipeActionLabel(AppLocalizations l, SwipeAction action) =>
    switch (action) {
      SwipeAction.none => l.swActNone,
      SwipeAction.like => l.swActLike,
      SwipeAction.queue => l.swActQueue,
      SwipeAction.playNext => l.swActPlayNext,
      SwipeAction.next => l.swActNext,
      SwipeAction.prev => l.swActPrev,
      SwipeAction.download => l.swActDownload,
      SwipeAction.delete => l.swActDelete,
    };

String swipeZoneLabel(AppLocalizations l, SwipeZone zone) => switch (zone) {
  SwipeZone.library => l.swZoneLibrary,
  SwipeZone.queue => l.swZoneQueue,
  SwipeZone.mini => l.swZoneMini,
  SwipeZone.player => l.swZonePlayer,
};

/// Строка списка со свайпами из настроек.
///
/// [listId] — раздел библиотеки, из которого строка (`all` / `fav` / `history`
/// / id плейлиста): по нему «Удалить» понимает, откуда убирать. [queueIndex] —
/// номер строки в очереди, там удаляют не из списка, а из самой очереди.
class TrackSwipe extends ConsumerWidget {
  const TrackSwipe({
    super.key,
    required this.zone,
    required this.track,
    required this.child,
    this.listId,
    this.queueIndex,
  });

  final SwipeZone zone;
  final Track track;
  final String? listId;
  final int? queueIndex;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(swipeProvider).of(zone);
    return SwipeRow(
      left: _panel(context, ref, pair.right),
      right: _panel(context, ref, pair.left),
      child: child,
    );
  }

  /// Плашка одного направления; `null` — действия нет, строка в эту сторону не
  /// двигается.
  SwipePanel? _panel(BuildContext context, WidgetRef ref, SwipeAction action) {
    if (action == SwipeAction.none) return null;
    // «Удалить» — единственное, после чего строки не станет: остальные жесты
    // возвращают её на место.
    final removes =
        action == SwipeAction.delete && (queueIndex != null || listId != null);
    return SwipePanel(
      icon: swipeActionIcon(action),
      danger: action == SwipeAction.delete,
      dismiss: removes,
      onFire: () => runSwipeAction(
        context,
        ref,
        action,
        track: track,
        listId: listId,
        queueIndex: queueIndex,
      ),
    );
  }
}

/// Сделать то, что назначено на жест.
void runSwipeAction(
  BuildContext context,
  WidgetRef ref,
  SwipeAction action, {
  required Track track,
  String? listId,
  int? queueIndex,
  bool fromFlick = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l;
  final player = ref.read(playbackProvider.notifier);

  switch (action) {
    case SwipeAction.none:
      return;
    case SwipeAction.like:
      final on = ref.read(libraryProvider.notifier).toggleFav(track);
      messenger.toast(on ? l.swLiked : l.swUnliked);
    case SwipeAction.queue:
      messenger.toast(
        player.addToQueue(track) ? l.swAddedToQueue : l.swAlreadyInQueue,
      );
    case SwipeAction.playNext:
      player.playNext(track);
      messenger.toast(l.swPlaysNext);
    // Смену «под пальцем» слои `TrackSwap` не анимируют: содержимое уже увёл
    // за край сам жест (см. `markSwapSilent`). Флаг одноразовый, поэтому
    // ставится только здесь — на действиях, которые трек точно сменят.
    case SwipeAction.next:
      if (fromFlick) markSwapSilent();
      unawaited(player.next());
    case SwipeAction.prev:
      if (fromFlick) markSwapSilent();
      unawaited(player.prev());
    case SwipeAction.download:
      unawaited(toggleTrackOffline(messenger, l, ref, track));
    case SwipeAction.delete:
      if (queueIndex != null) {
        unawaited(player.removeAt(queueIndex));
        return;
      }
      if (listId != null) {
        _removeFromList(messenger, l, ref, listId, track);
        return;
      }
      // Плеер и миниплеер: списка за ними нет, убирать можно только из очереди.
      final index = ref.read(playbackProvider).index;
      if (index >= 0) unawaited(player.removeAt(index));
  }
}

/// Убрать трек из раздела библиотеки — теми же ручками, что и режим правки
/// списка, и с «Отменить» в тосте.
///
/// Из «Всех треков» трек уходит НАСКВОЗЬ (см. [LibraryController.deleteTrack]),
/// поэтому отмена возвращает снимок всей библиотеки: по частям такое удаление
/// не собрать. Офлайн-копию удаляем только когда отменять уже поздно.
void _removeFromList(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  String listId,
  Track track,
) {
  final lib = ref.read(libraryProvider.notifier);
  final state = ref.read(libraryProvider);
  final before = lib.snapshot();

  switch (listId) {
    case 'all':
      lib.deleteTrack(track.id);
    case 'fav':
      lib.setFavTracks([
        for (final t in state.favTracks)
          if (t.id != track.id) t.id,
      ]);
    case 'history':
      lib.setHistoryTracks([
        for (final h in state.history)
          if (h.trackId != track.id) h.trackId,
      ]);
    default:
      lib.removeTrackFromPlaylist(listId, track.id);
  }

  final offline = ref.read(offlineProvider.notifier);
  messenger.toast(
    l.swRemoved,
    action: ToastAction(
      fn: () => lib.restoreSnapshot(before),
      // Файлы удаляем только когда отменять уже поздно: «Отменить» вернёт
      // снимок библиотеки, а стёртую копию своего трека — нет.
      onExpire: listId == 'all'
          ? () {
              unawaited(offline.remove(track.id));
              unawaited(forgetLocalTracks([track]));
            }
          : null,
    ),
  );
}
