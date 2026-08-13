/// Действия офлайна с обратной связью — то, что на ПК делают `download.ts`
/// вместе с тостами: сам стор молча возвращает результат, а сообщать о нём
/// пользователю приходится здесь.
///
/// Мессенджер передаётся снаружи, а не берётся из `context`: шторка действий
/// закрывается ДО вызова обработчика, и её `context` к моменту снекбара уже
/// отвязан от дерева.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'file_download.dart';
import 'offline_store.dart';

/// Скачать трек или убрать его копию — «Слушать офлайн» / «Убрать из офлайна».
///
/// Переводы передаются рядом с мессенджером и по той же причине: шторка
/// действий закрывается раньше, чем приходит результат, и брать их из её
/// `context` в этот момент уже нельзя.
Future<void> toggleTrackOffline(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  Track track,
) async {
  final offline = ref.read(offlineProvider.notifier);
  if (offline.has(track.id)) {
    await offline.remove(track.id);
    messenger.toast(l.ofRemoved);
    return;
  }
  // Один тост на всю операцию: вертушка меняется на галочку прямо в нём, а не
  // сменой двух тостов подряд.
  final toast = messenger.busyToast(l.ofSaving);
  final error = await offline.download(track);
  toast.finish(
    error == null
        ? l.ofAvailable(track.name)
        : describeOfflineFailure(l, error),
    kind: error == null ? ToastKind.success : ToastKind.error,
  );
}

/// Скачать список целиком (плейлист, «Любимые», «Все треки»).
///
/// [sourceId] — id списка (`listId` его экрана): по нему индикатор пакета
/// понимает, на чьей странице ему показываться.
Future<void> downloadListOffline(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  String sourceId,
  List<Track> tracks,
) async {
  final toast = messenger.busyToast(
    l.ofSaving,
    content: (view) => BatchToastBody(view: view),
  );
  final result = await ref
      .read(offlineProvider.notifier)
      .downloadAll(sourceId, tracks);
  toast.finish(switch (result) {
    null => l.ofNothingToSave,
    final r when r.busy => l.ofBusyWithAnother,
    final r => batchSummary(l, r),
  }, kind: result == null || result.busy ? ToastKind.warn : ToastKind.success);
}

/// «Скачать файлом» — второе скачивание десктопа: трек ложится туда, где его
/// видно вне Bloom (на Android — общая «Музыка/Bloom», на iOS — папка
/// приложения в «Файлах»).
Future<void> saveTrackFile(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  Track track,
) async {
  final toast = messenger.busyToast(l.ofDownloadingTrack);
  try {
    final path = await saveTrackAsFile(ref, track);
    toast.finish(l.ofSaved(path ?? saveTargetLabel(l)));
  } catch (e) {
    toast.finish(
      describeSaveError(l, readableSaveError(e)),
      kind: ToastKind.error,
    );
  }
}

/// Сохранить файлами весь список.
Future<void> saveListFiles(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  String sourceId,
  List<Track> tracks,
) async {
  // Тот же индикатор пакета, что у офлайн-копий (см. `beginBatch`), — значит и
  // тост тот же.
  final toast = messenger.busyToast(
    l.ofDownloadingFiles,
    content: (view) => BatchToastBody(view: view),
  );
  final result = await saveListAsFiles(ref, sourceId, tracks);
  toast.finish(
    result.total == 0
        ? l.ofNothingToDownload
        : batchSummary(
            l,
            BatchResult(total: result.total, failed: result.failed),
          ),
    kind: result.total == 0
        ? ToastKind.warn
        : result.failed == 0
        ? ToastKind.success
        : ToastKind.warn,
  );
}

/// Убрать офлайн-копии всех треков списка.
Future<void> removeListOffline(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  List<Track> tracks,
) async {
  final n = await ref.read(offlineProvider.notifier).removeAll(tracks);
  messenger.toast(
    n == 0 ? l.ofNoCopies : l.ofRemovedCount(n),
    kind: n == 0 ? ToastKind.warn : ToastKind.info,
  );
}

/// Офлайн-состояние списка: сколько его скачиваемых треков уже лежит на
/// устройстве. Порт `usePlaylistOffline` с десктопа.
///
/// Состояние передаётся аргументом, а не читается изнутри: зовут и из `build`
/// (там нужен `watch`, чтобы тег обновлялся по ходу загрузки), и из
/// обработчика шторки (там можно только `read`).
({bool any, bool all, int cached, int total}) listOfflineState(
  OfflineState state,
  OfflineController offline,
  List<Track> tracks,
) {
  final downloadable = tracks.where(offline.canDownload).toList();
  final cached = downloadable.where((t) => state.has(t.id)).length;
  return (
    any: cached > 0,
    all: downloadable.isNotEmpty && cached == downloadable.length,
    cached: cached,
    total: downloadable.length,
  );
}

/// Тело тоста пакетной загрузки: счётчик «N/M», полоса снизу как индикатор
/// прогресса (вместо отсчёта) и «Прервать». Раньше это была строка под шапкой
/// списка — теперь тост, поэтому ход загрузки видно с любого экрана, а не
/// только на той странице, откуда её запустили.
///
/// Пакет в сторе один на приложение, поэтому сверять `sourceId` не с чем: если
/// пакет идёт — он и есть наш.
class BatchToastBody extends ConsumerWidget {
  const BatchToastBody({super.key, required this.view});

  /// Состояние тоста от [ToastHandle]: до `finish()` тут «идёт работа», после —
  /// готовый итог, и счётчик пакета уже не при чём.
  final ValueListenable<ToastView> view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(offlineProvider.select((s) => s.batch));

    return ValueListenableBuilder(
      valueListenable: view,
      builder: (_, v, _) {
        final live = v.busy && batch != null;
        return BloomToastCard(
          text: live
              ? context.l.ofSavingProgress(batch.done, batch.total)
              : v.text,
          kind: v.kind,
          busy: v.busy,
          progress: live && batch.total > 0 ? batch.done / batch.total : null,
          barDuration: v.barDuration,
          actionLabel: live ? context.l.ofAbort : null,
          onAction: live
              ? () => ref.read(offlineProvider.notifier).cancelBatch()
              : null,
        );
      },
    );
  }
}

/// Индикатор «доступно офлайн» для подписи списка: скачан целиком — «офлайн»,
/// частично — «N/M». Пока ни одного трека нет, не рисуется вовсе. Цвет — как у
/// самой подписи, акцентом не выделяется (порт `PlaylistOfflineTag`).
class OfflineTag extends ConsumerWidget {
  const OfflineTag({
    super.key,
    required this.tracks,
    this.dot = true,
    this.style,
  });

  final List<Track> tracks;

  /// Ставить ли точку-разделитель перед тегом.
  final bool dot;

  /// Стиль подписи, к которой тег приписывается. По умолчанию — `bodyMedium`
  /// шапки списка; на плитках библиотеки подпись мельче, и стиль приходит свой.
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = listOfflineState(
      ref.watch(offlineProvider),
      ref.read(offlineProvider.notifier),
      tracks,
    );
    if (!status.any) return const SizedBox.shrink();
    final style = this.style ?? Theme.of(context).textTheme.bodyMedium;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) Text(' · ', style: style),
        // Та же дискета, что в строке трека и в теге плейлиста на десктопе.
        Icon(
          SolarIconsOutline.diskette,
          size: style?.fontSize ?? 13,
          color: style?.color,
        ),
        const SizedBox(width: 3),
        Text(
          status.all
              ? context.l.commonOfflineBadge
              : '${status.cached}/${status.total}',
          style: style,
        ),
      ],
    );
  }
}

/// Причина отказа офлайна — фразой. Живёт здесь, а не в сторе: только у UI
/// есть язык интерфейса.
String describeOfflineFailure(AppLocalizations l, OfflineFailure failure) =>
    switch (failure.kind) {
      OfflineFailureKind.noStorage => l.ofNoStorage,
      OfflineFailureKind.notSavable => l.ofCantSaveTrack,
      OfflineFailureKind.streamOnly => l.ofStreamOnly,
      OfflineFailureKind.drm => l.ofDrm,
      OfflineFailureKind.noFileLink => l.ofNoFileLink,
      OfflineFailureKind.noConnection => l.ofNoConnection,
      OfflineFailureKind.unknown => l.ofSaveFailed(failure.detail ?? ''),
    };

/// То же для сохранения файлом.
String describeSaveError(AppLocalizations l, DownloadFailure failure) =>
    switch (failure.kind) {
      DownloadFailureKind.notDownloadable => l.fdCantDownload,
      DownloadFailureKind.needPermission => l.fdNeedPermission,
      DownloadFailureKind.noConnection => l.ofNoConnection,
      DownloadFailureKind.unknown => failure.detail ?? l.fdSaveFailed,
    };

/// Итог пакетной загрузки фразой.
String batchSummary(AppLocalizations l, BatchResult r) {
  if (r.failed == 0) return l.ofDownloadedAll(r.ok);
  if (r.ok == 0) return l.ofDownloadedNone;
  return l.ofDownloadedPartial(r.ok, r.total, r.failed);
}
