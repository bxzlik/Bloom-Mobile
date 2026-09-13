/// Список «История» — представление над журналом прослушиваний, а не своё
/// хранилище (порт десктопных `historyStore.ts` + `historyTracks.ts`, 3.0).
///
/// Раньше это был `LibraryState.history` с лимитом 200 уникальных треков и
/// вытеснением по давности, а сами треки держало хранилище библиотеки. Теперь
/// строки выводятся из [PlayStats], а трек для строки ищется по цепочке
/// «библиотека → снимок журнала»: снимок хранится на каждый когда-либо игранный
/// трек, так что старая строка не пропадает, даже когда трека давно нет нигде.
///
/// Своё здесь осталось одно — что человек спрятал ([HistoryHide]). Скрытие
/// статистику НЕ трогает: «Итоги», профиль и сиды волны считаются по журналу
/// целиком.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entities/entities.dart';
import 'library_store.dart';
import 'play_log.dart';
import 'play_stats.dart';

/// Ключ отметок скрытия в `bloom.json`.
const String kHistoryHiddenKey = 'historyHidden';

final historyHideProvider =
    NotifierProvider<HistoryHideController, HistoryHide>(
      HistoryHideController.new,
    );

class HistoryHideController extends Notifier<HistoryHide> {
  @override
  HistoryHide build() =>
      HistoryHide.fromJson(ref.read(jsonStoreProvider).read(kHistoryHiddenKey));

  /// Часы те же, что у журнала: отметку сравнивают с его событиями.
  int get _now => ref.read(playLogClockProvider)().millisecondsSinceEpoch;

  void _save() =>
      ref.read(jsonStoreProvider).write(kHistoryHiddenKey, state.toJson());

  /// Убрать треки из списка (события в журнале остаются).
  void hide(Iterable<String> ids) {
    if (ids.isEmpty) return;
    final at = _now;
    state = HistoryHide(
      before: state.before,
      byId: {...state.byId, for (final id in ids) id: at},
    );
    _save();
  }

  /// Очистить список целиком. Точечные отметки больше не нужны — общий рубеж
  /// их перекрывает.
  void clear() {
    state = HistoryHide(before: _now);
    _save();
  }

  /// Вернуть отметки как были — «Отменить» после смахивания строки.
  void restore(HistoryHide snapshot) {
    state = snapshot;
    _save();
  }

  /// Смена площадки: отметка переезжает вместе с прослушиваниями, иначе
  /// спрятанный трек вернулся бы в список под новым id.
  void renameTrack(String oldId, String newId) {
    final at = state.byId[oldId];
    if (at == null) return;
    state = HistoryHide(
      before: state.before,
      byId: {
        for (final e in state.byId.entries)
          if (e.key == oldId) newId: e.value else e.key: e.value,
      },
    );
    _save();
  }

  /// Забыть отметки — вместе с очисткой статистики: журнал пуст, прятать нечего.
  void reset() {
    state = const HistoryHide();
    ref.read(jsonStoreProvider).removeAll(const [kHistoryHiddenKey]);
  }
}

/// Ряды «Истории» без треков — тем, кому нужны только id и время (волна).
final historyRowsProvider = Provider<List<HistoryRow>>(
  (ref) =>
      ref.watch(playStatsProvider).historyRows(ref.watch(historyHideProvider)),
);

/// Строка «Истории» вместе с треком, которым её показать и заиграть.
@immutable
class HistoryItem {
  const HistoryItem(this.row, this.track);

  final HistoryRow row;
  final Track track;
}

/// Видимые строки «Истории», свежие сверху. Строки без трека выпадают: своего
/// файла, которого больше нет в библиотеке, поднять нечем.
final historyProvider = Provider<List<HistoryItem>>((ref) {
  final stats = ref.watch(playStatsProvider);
  final lib = ref.watch(libraryProvider);
  return [
    for (final row in ref.watch(historyRowsProvider))
      if (resolveHistoryTrack(row.id, lib, stats) case final track?)
        HistoryItem(row, track),
  ];
});

/// Трек строки истории: библиотека → снимок журнала.
Track? resolveHistoryTrack(String id, LibraryState lib, PlayStats stats) =>
    lib.tracks[id] ?? trackFromPlayMeta(id, stats.meta[id]);

/// Трек из снимка журнала — не только показываемый, но и ИГРАБЕЛЬНЫЙ: площадке
/// хватает сквозного id, сырьё для стрима она дотянет сама (SoundCloud —
/// `resolveTrackById`, Яндекс и YouTube Music резолвят по id и так). Своего
/// файла снимком не поднять — у него нет ни ссылки, ни пути.
Track? trackFromPlayMeta(String id, PlayMeta? meta) {
  if (meta == null) return null;
  final source = MusicSource.fromId(id);
  if (source == MusicSource.local) return null;
  return Track(
    id: id,
    name: meta.name,
    artist: meta.artist,
    duration: Duration(seconds: meta.seconds),
    source: source,
    cover: meta.cover,
  );
}

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

/// Снимки журнала для записей старой истории — один раз на запуске.
///
/// Треки старой истории держало хранилище библиотеки, и первая же его чистка
/// теперь их выбросит: история больше не ссылка на хранилище. Без снимка такая
/// строка пропала бы из списка — у тех, что игрались до появления журнала,
/// снимка нет. Берём, что ещё лежит в библиотеке; повторный вызов ничего не
/// добавляет.
void adoptLegacySnapshots({
  required List<HistoryEntry> legacy,
  required LibraryState lib,
  required PlayLogController log,
}) {
  log.adoptMeta({
    for (final h in legacy)
      if (lib.tracks[h.trackId] case final track?)
        h.trackId: PlayMeta.of(track),
  });
}
