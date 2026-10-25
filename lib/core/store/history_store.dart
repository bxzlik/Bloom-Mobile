/// Список «История» — представление над журналом прослушиваний, а не своё
/// хранилище. Из истории ничего не удаляется: ни целиком, ни поштучно — как
/// на ПК, она показывает журнал как есть.
///
/// Трек для строки — из библиотеки, а если его там нет, снимок из базы: он
/// хранится на каждый когда-либо игранный трек, так что старая строка не
/// пропадает, даже когда трека давно нет нигде.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entities/entities.dart';
import 'library_store.dart';
import 'play_stats.dart';

/// Ряды «Истории» без треков — тем, кому нужны только id и время (волна).
final historyRowsProvider = Provider<List<HistoryRow>>(
  (ref) => ref.watch(playStatsProvider).historyRows(),
);

/// Строка «Истории» вместе с треком, которым её показать и заиграть.
@immutable
class HistoryItem {
  const HistoryItem(this.row, this.track);

  final HistoryRow row;
  final Track track;
}

/// Строки «Истории», свежие сверху.
final historyProvider = Provider<List<HistoryItem>>((ref) {
  final stats = ref.watch(playStatsProvider);
  final lib = ref.watch(libraryProvider);
  return [
    for (final row in ref.watch(historyRowsProvider))
      if (resolveHistoryTrack(row.id, lib, stats) case final track?)
        HistoryItem(row, track),
  ];
});

/// Трек строки истории: библиотека → снимок из базы.
Track? resolveHistoryTrack(String id, LibraryState lib, PlayStats stats) =>
    lib.tracks[id] ?? stats.tracks[id];

/// Сводка для подписи «Истории»: сколько треков и сколько НАСЛУШАНО — длина
/// трека на число прослушиваний, а не сумма длин, как у остальных списков:
/// трек, отыгранный десять раз, и правда занял в десять раз больше времени.
({int tracks, Duration listened}) historyTotals(List<HistoryItem> items) {
  var seconds = 0;
  for (final item in items) {
    seconds += item.track.duration.inSeconds * item.row.count;
  }
  return (tracks: items.length, listened: Duration(seconds: seconds));
}
