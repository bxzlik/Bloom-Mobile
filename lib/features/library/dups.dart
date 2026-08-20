/// «Найти дубли» — один и тот же трек, попавший в список дважды.
///
/// Порт десктопных `computeDupGroups`/`sortGroup` из `LibTracklist`: группируем
/// по нормализованным названию и артисту, группы из одного трека выбрасываем.
/// Внутри группы первым идёт тот, кого стоит оставить: с обложкой → чаще
/// слушали → раньше добавлен. Всё остальное в группе — лишние копии.
///
/// Режим включается из меню плейлиста и живёт в сторе, а не в состоянии экрана:
/// зовут его из шторки, а показывает список, и общаться им больше не через что.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';

/// Ключ, по которому треки считаются одним и тем же: регистр и лишние пробелы
/// не в счёт. Умышленно грубо — это поиск дублей внутри одного списка, а не
/// сопоставление площадок (для того есть матчер).
String dupKey(Track track) => '${_norm(track.name)}|||${_norm(track.artist)}';

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Группы дублей в [pool], каждая — от «оставить» к лишним. Порядок групп — как
/// первое появление трека в списке: так они стоят там же, где человек их видел.
///
/// [addedAt] — когда трек попал в библиотеку (`LibraryState.inLib`): при прочих
/// равных оставляем ту копию, что появилась раньше.
List<List<Track>> dupGroups(
  List<Track> pool, {
  Map<String, int> addedAt = const {},
}) {
  final byKey = <String, List<Track>>{};
  for (final track in pool) {
    byKey.putIfAbsent(dupKey(track), () => <Track>[]).add(track);
  }
  return [
    for (final group in byKey.values)
      if (group.length > 1) sortDupGroup(group, addedAt: addedAt),
  ];
}

/// Порядок внутри группы: с обложкой → больше прослушиваний → добавлен раньше.
/// Первый — тот, кого оставляем.
List<Track> sortDupGroup(
  List<Track> group, {
  Map<String, int> addedAt = const {},
}) {
  final sorted = [...group];
  sorted.sort((a, b) {
    final coverA = (a.cover ?? '').isNotEmpty;
    final coverB = (b.cover ?? '').isNotEmpty;
    if (coverA != coverB) return coverA ? -1 : 1;
    final playsA = a.playCount ?? 0;
    final playsB = b.playCount ?? 0;
    if (playsA != playsB) return playsB - playsA;
    return (addedAt[a.id] ?? 0).compareTo(addedAt[b.id] ?? 0);
  });
  return sorted;
}

/// Лишние копии — всё, кроме первого в каждой группе.
List<Track> extraDups(List<List<Track>> groups) => [
  for (final group in groups) ...group.skip(1),
];

/// В каком списке сейчас включён режим дублей. `null` — ни в каком.
final dupsProvider = NotifierProvider<DupsController, String?>(
  DupsController.new,
);

class DupsController extends Notifier<String?> {
  @override
  String? build() => null;

  void enter(String listId) => state = listId;

  void exit() => state = null;
}
