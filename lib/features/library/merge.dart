/// «Объединить с…» — собрать из нескольких плейлистов один новый.
///
/// Порт десктопного `MergeModal`: исходный плейлист идёт первым, за ним
/// выбранные в порядке выбора; повторы схлопываются по id, если не выключить.
/// Исходные плейлисты не меняются — результат это ВСЕГДА новый плейлист (их
/// удаление — отдельная галочка, а не побочный эффект слияния).
library;

import '../../core/entities/entities.dart';

/// Состав нового плейлиста. [lists] — исходные списки по порядку.
///
/// Повторы считаем по id: один и тот же трек с разных площадок — разные записи
/// библиотеки, и схлопывать их здесь нельзя (для этого есть «Найти дубли»,
/// который сравнивает названия).
List<Track> mergeTracks(List<List<Track>> lists, {required bool dedup}) {
  final out = <Track>[];
  final seen = <String>{};
  for (final list in lists) {
    for (final track in list) {
      if (dedup && !seen.add(track.id)) continue;
      out.add(track);
    }
  }
  return out;
}

/// Сколько повторов уберёт слияние — для строки со счётом в шторке.
int mergeDupCount(List<List<Track>> lists) {
  final total = lists.fold<int>(0, (sum, list) => sum + list.length);
  return total - mergeTracks(lists, dedup: true).length;
}
