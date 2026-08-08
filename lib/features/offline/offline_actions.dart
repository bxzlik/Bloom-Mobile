/// Действия офлайна с обратной связью — то, что на ПК делают `download.ts`
/// вместе с тостами: сам стор молча возвращает результат, а сообщать о нём
/// пользователю приходится здесь.
///
/// Мессенджер передаётся снаружи, а не берётся из `context`: шторка действий
/// закрывается ДО вызова обработчика, и её `context` к моменту снекбара уже
/// отвязан от дерева.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import 'file_download.dart';
import 'offline_store.dart';

/// Скачать трек или убрать его копию — «Слушать офлайн» / «Убрать из офлайна».
Future<void> toggleTrackOffline(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  Track track,
) async {
  final offline = ref.read(offlineProvider.notifier);
  if (offline.has(track.id)) {
    await offline.remove(track.id);
    messenger.showSnackBar(const SnackBar(content: Text('Убрано из офлайна')));
    return;
  }
  messenger.showSnackBar(
    const SnackBar(content: Text('Сохранение для офлайна…')),
  );
  final error = await offline.download(track);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(error ?? 'Доступно офлайн: ${track.name}')),
    );
}

/// Скачать список целиком (плейлист, «Любимые», «Все треки»).
Future<void> downloadListOffline(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  String title,
  List<Track> tracks,
) async {
  final result = await ref
      .read(offlineProvider.notifier)
      .downloadAll(title, tracks);
  messenger.showSnackBar(
    SnackBar(content: Text(result ?? 'Здесь нечего сохранять офлайн')),
  );
}

/// «Скачать файлом» — второе скачивание десктопа: трек ложится туда, где его
/// видно вне Bloom (на Android — общая «Музыка/Bloom», на iOS — папка
/// приложения в «Файлах»).
Future<void> saveTrackFile(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  Track track,
) async {
  messenger.showSnackBar(const SnackBar(content: Text('Скачиваю трек…')));
  try {
    final path = await saveTrackAsFile(ref, track);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Сохранено: $path')));
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(readableSaveError(e))));
  }
}

/// Сохранить файлами весь список.
Future<void> saveListFiles(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  String title,
  List<Track> tracks,
) async {
  final result = await saveListAsFiles(ref, title, tracks);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.total == 0
            ? 'Здесь нечего скачивать'
            : batchSummary(result.total, result.failed),
      ),
    ),
  );
}

/// Убрать офлайн-копии всех треков списка.
Future<void> removeListOffline(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  List<Track> tracks,
) async {
  final n = await ref.read(offlineProvider.notifier).removeAll(tracks);
  messenger.showSnackBar(
    SnackBar(
      content: Text(n == 0 ? 'Офлайн-копий не было' : 'Убрано из офлайна: $n'),
    ),
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

/// Ход пакетной загрузки — то, что на ПК показывает баннер: сколько треков из
/// скольких сохранено и кнопка «прервать». Общий для обоих скачиваний; пока
/// пакета нет, не занимает ни пикселя.
class OfflineBatchBar extends ConsumerWidget {
  const OfflineBatchBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(offlineProvider.select((s) => s.batch));
    if (batch == null) return const SizedBox.shrink();
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              value: batch.done / batch.total,
              strokeWidth: 2,
              color: t.accent,
              backgroundColor: t.ovlLine,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Сохраняю: ${batch.done}/${batch.total}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => ref.read(offlineProvider.notifier).cancelBatch(),
            child: Text('Прервать', style: TextStyle(color: t.text2)),
          ),
        ],
      ),
    );
  }
}

/// Индикатор «доступно офлайн» для подписи списка: скачан целиком — «офлайн»,
/// частично — «N/M». Пока ни одного трека нет, не рисуется вовсе. Цвет — как у
/// самой подписи, акцентом не выделяется (порт `PlaylistOfflineTag`).
class OfflineTag extends ConsumerWidget {
  const OfflineTag({super.key, required this.tracks, this.dot = true});

  final List<Track> tracks;

  /// Ставить ли точку-разделитель перед тегом.
  final bool dot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = listOfflineState(
      ref.watch(offlineProvider),
      ref.read(offlineProvider.notifier),
      tracks,
    );
    if (!status.any) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.bodyMedium;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) Text(' · ', style: style),
        // Та же дискета, что в строке трека и в теге плейлиста на десктопе.
        Icon(SolarIconsOutline.diskette, size: 13, color: style?.color),
        const SizedBox(width: 3),
        Text(
          status.all ? 'офлайн' : '${status.cached}/${status.total}',
          style: style,
        ),
      ],
    );
  }
}
