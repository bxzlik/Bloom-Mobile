/// «Перенести на площадку» — копия плейлиста, собранная из треков другой
/// площадки.
///
/// Порт десктопного `convertPlaylist.ts`: каждый трек ищется на целевой
/// площадке по «название + артист», выдача ранжируется общим матчером
/// ([rankMatches]). Уверенные совпадения подставляются сами, спорные и
/// ненайденные ждут решения человека. Исходный плейлист не меняется — результат
/// это ВСЕГДА новый плейлист (в отличие от «Сменить площадку», которая заменяет
/// запись библиотеки на месте).
library;

import '../../core/entities/entities.dart';
import '../../core/providers/match.dart';
import '../../core/providers/music_provider.dart';

/// Сколько кандидатов показываем в ручном выборе.
const int kConvertCandLimit = 5;

/// Сколько треков ищем одновременно — щадим API площадок. Последовательный скан
/// сотни треков ощущался бы вечностью, а полный параллелизм упирается в лимиты.
const int kConvertConcurrency = 3;

enum ConvertStatus {
  /// Трек уже на целевой площадке — переносить нечего.
  same,

  /// Найдено уверенно (счёт ≥ [kAutoMatchScore]).
  exact,

  /// Кандидаты есть, но ни один не уверенный — нужен ручной выбор.
  ambiguous,

  /// Ничего похожего либо площадка ответила ошибкой.
  notfound,
}

class ConvertItem {
  const ConvertItem({
    required this.src,
    required this.status,
    this.cands = const [],
    this.failed = false,
  });

  /// Исходный трек из плейлиста.
  final Track src;

  final ConvertStatus status;

  /// Отранжированные кандидаты (пусто у `same` и `notfound`).
  final List<ScoredMatch> cands;

  /// Площадка ответила ошибкой — это не то же самое, что честное «не нашлось».
  final bool failed;
}

/// Чем трек войдёт в новый плейлист.
sealed class ConvertDecision {
  const ConvertDecision();
}

/// Оставить исходный трек как есть.
class KeepOriginal extends ConvertDecision {
  const KeepOriginal();
}

/// Взять найденную версию с целевой площадки.
class TakeMatch extends ConvertDecision {
  const TakeMatch(this.track);
  final Track track;
}

/// Не включать трек в новый плейлист.
class SkipTrack extends ConvertDecision {
  const SkipTrack();
}

/// Прогнать треки через поиск на целевой площадке.
///
/// [onProgress] зовётся после КАЖДОГО трека — для полосы прогресса.
/// [cancelled] прерывает скан: уже обработанные возвращаются, остальные не
/// запрашиваются (экран закрыли — сеть не молотит впустую).
Future<List<ConvertItem>> scanPlaylistConversion(
  MusicProvider provider,
  List<Track> tracks, {
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final total = tracks.length;
  final out = List<ConvertItem?>.filled(total, null);
  var cursor = 0;
  var done = 0;

  Future<void> runOne(int i) async {
    final src = tracks[i];
    if (src.source == provider.source) {
      out[i] = ConvertItem(src: src, status: ConvertStatus.same);
      return;
    }
    var failed = false;
    var found = const <Track>[];
    try {
      found = (await provider.search(
        '${src.name} ${src.artist}'.trim(),
      )).tracks;
    } catch (_) {
      failed = true;
    }
    // Своя же выдача может вернуть треки других площадок — берём только те, что
    // реально с целевой.
    final cands = rankMatches(
      [
        for (final t in found)
          if (t.source == provider.source) t,
      ],
      src,
      limit: kConvertCandLimit,
      min: kMinMatchScore,
    );
    out[i] = ConvertItem(
      src: src,
      status: cands.isEmpty
          ? ConvertStatus.notfound
          : cands.first.score >= kAutoMatchScore
          ? ConvertStatus.exact
          : ConvertStatus.ambiguous,
      cands: cands,
      failed: failed,
    );
  }

  // Пул воркеров: порядок результатов сохраняется (пишем по индексу), но
  // запросов в полёте не больше [kConvertConcurrency].
  Future<void> worker() async {
    while (true) {
      if (cancelled?.call() ?? false) return;
      final i = cursor++;
      if (i >= total) return;
      await runOne(i);
      done++;
      onProgress?.call(done, total);
    }
  }

  await Future.wait([
    for (
      var i = 0;
      i < (total < kConvertConcurrency ? total : kConvertConcurrency);
      i++
    )
      worker(),
  ]);
  return out.whereType<ConvertItem>().toList();
}

/// Что подставляется само: уверенное совпадение — новой версией, всё
/// остальное остаётся оригиналом, пока человек не решит иначе.
Map<String, ConvertDecision> defaultDecisions(List<ConvertItem> items) => {
  for (final item in items)
    item.src.id: item.status == ConvertStatus.exact && item.cands.isNotEmpty
        ? TakeMatch(item.cands.first.track)
        : const KeepOriginal(),
};

/// Состав нового плейлиста по принятым решениям, в порядке исходного.
List<Track> convertResult(
  List<ConvertItem> items,
  Map<String, ConvertDecision> decisions,
) => [
  for (final item in items)
    ?switch (decisions[item.src.id] ?? const KeepOriginal()) {
      TakeMatch(:final track) => track,
      KeepOriginal() => item.src,
      // Пропущенный не попадает в список вовсе — null-элемент выпадает.
      SkipTrack() => null,
    },
];

/// Сколько треков куда попало — строка со счётом под списком.
({int moved, int kept, int skipped}) convertStats(
  List<ConvertItem> items,
  Map<String, ConvertDecision> decisions,
) {
  var moved = 0;
  var kept = 0;
  var skipped = 0;
  for (final item in items) {
    switch (decisions[item.src.id] ?? const KeepOriginal()) {
      case TakeMatch():
        moved++;
      case KeepOriginal():
        kept++;
      case SkipTrack():
        skipped++;
    }
  }
  return (moved: moved, kept: kept, skipped: skipped);
}
