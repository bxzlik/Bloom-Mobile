/// Снимок последней сессии плеера — «Продолжить» на главной.
///
/// Порт десктопного `features/player/lib/resume.ts` (там ключ `bloom_resume` в
/// localStorage, здесь — ключ `resume` в bloom.json). На мобилке он нужнее, чем
/// на ПК: система убивает процесс между запусками постоянно, и без снимка
/// карточка «Продолжить» пустовала бы ровно в тот момент, когда она и нужна.
///
/// Отличие от десктопа: очередь храним СНИМКАМИ треков, а не одними id со
/// списком «тех, кого нет в библиотеке». Реестра треков площадок, живущего в
/// памяти процесса, у нас нет вовсе — id трека из поиска после перезапуска
/// разворачивать не во что. Лимит тот же (300 треков), иначе очередь-волна или
/// большой плейлист раздували бы файл.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart';
import 'play_source.dart';
import 'player_controller.dart' show PlayerRepeat;

/// Сколько треков очереди уносим в снимок. Длинная очередь режется с ТЕКУЩЕГО
/// трека (см. [ResumeData.capture]): продолжают слушать вперёд, а не назад.
const int kResumeQueueLimit = 300;

@immutable
class ResumeData {
  const ResumeData({
    required this.queue,
    required this.index,
    required this.position,
    required this.savedAt,
    this.paused = true,
    this.source,
    this.cleared = false,
    this.fullQueue,
    this.shuffle = false,
    this.smartShuffle = false,
    this.repeat = PlayerRepeat.off,
  });

  /// Очередь очистили целиком (удалили последний трек): при запуске в плеер
  /// снимок не поднимаем, но карточка «Продолжить» остаётся. Снимается
  /// следующей записью — она пишет снимок заново, без флага.
  final bool cleared;

  /// Очередь в том виде, какой она была до очистки, — её поднимает карточка
  /// «Продолжить»: очищают обычно чтобы убрать лишнее из плеера, а не чтобы
  /// забыть, что слушали. `null` — очередь не очищали.
  final List<Track>? fullQueue;

  /// Треки очереди снимками. Пустой быть не может — иначе снимка нет вовсе.
  final List<Track> queue;

  /// Номер трека, на котором остановились.
  final int index;

  final Duration position;

  /// Когда сняли — для подписи «X мин. назад».
  final DateTime savedAt;

  /// Стояли на паузе (иначе — играли и приложение закрыли на ходу).
  final bool paused;

  /// Откуда набрана очередь — см. `PlaybackState.source`. Переживает
  /// перезапуск вместе с очередью: пилюля источника в плеере обязана называть
  /// тот же список, что и до убийства процесса.
  final PlaySource? source;

  /// Режимы плеера на момент снимка.
  ///
  /// Без них очередь возвращалась перемешанной (порядок-то сохранён — она и
  /// записана уже в тасованном виде), а флаг — сброшенным: значок перемешки
  /// погас, повтор слетел, и плеер вёл себя не так, как показывал.
  ///
  /// Исходный порядок до перемешки (`_origQueue`) намеренно НЕ храним — это
  /// вторая копия очереди в файле ради действия, которое после перезапуска
  /// совершают единицы. Выключение перемешки без него просто снимает флаг,
  /// оставляя порядок как есть, — `toggleShuffle` этот случай уже держит.
  final bool shuffle;
  final bool smartShuffle;
  final PlayerRepeat repeat;

  Track get track => queue[index];

  /// Окно очереди в [kResumeQueueLimit] треков: обрезка с [index], чтобы
  /// текущий трек всегда попал в кадр. Возвращает окно и номер в нём.
  static (List<Track>, int) _window(List<Track> queue, int index) {
    final from = queue.length <= kResumeQueueLimit
        ? 0
        : (index + kResumeQueueLimit <= queue.length
              ? index
              : queue.length - kResumeQueueLimit);
    return (
      queue.sublist(from, (from + kResumeQueueLimit).clamp(0, queue.length)),
      index - from,
    );
  }

  /// Снимок очереди: обрезка с текущего трека, чтобы он всегда попал в кадр.
  /// [fullQueue] — очередь до очистки, режется тем же окном вокруг текущего.
  static ResumeData capture({
    required List<Track> queue,
    required int index,
    required Duration position,
    required bool paused,
    PlaySource? source,
    List<Track>? fullQueue,
    DateTime? at,
    bool shuffle = false,
    bool smartShuffle = false,
    PlayerRepeat repeat = PlayerRepeat.off,
  }) {
    final (window, at_) = _window(queue, index);
    return ResumeData(
      queue: window,
      index: at_,
      position: position,
      paused: paused,
      source: source,
      savedAt: at ?? DateTime.now(),
      fullQueue: _windowAround(fullQueue, queue[index]),
      shuffle: shuffle,
      smartShuffle: smartShuffle,
      repeat: repeat,
    );
  }

  static List<Track>? _windowAround(List<Track>? full, Track current) {
    if (full == null || full.isEmpty) return null;
    final at = full.indexWhere((t) => t.id == current.id);
    return _window(full, at < 0 ? 0 : at).$1;
  }

  /// Тот же снимок с пометкой «очередь очистили» и очередью до очистки.
  ResumeData markedCleared(List<Track>? full) => ResumeData(
    queue: queue,
    index: index,
    position: position,
    savedAt: savedAt,
    paused: paused,
    source: source,
    cleared: true,
    fullQueue: _windowAround(full, track) ?? fullQueue,
    shuffle: shuffle,
    smartShuffle: smartShuffle,
    repeat: repeat,
  );

  /// Снимок для карточки «Продолжить»: очередь целиком, какой она была до
  /// очистки. Номер ищем по треку — он относится к урезанной очереди. Трека в
  /// полной очереди не нашлось — играем её с начала и без позиции: позиция была
  /// у другого трека.
  ResumeData forContinue() {
    final full = fullQueue;
    if (full == null || full.isEmpty) return this;
    final at = full.indexWhere((t) => t.id == track.id);
    return ResumeData(
      queue: full,
      index: at < 0 ? 0 : at,
      position: at < 0 ? Duration.zero : position,
      savedAt: savedAt,
      paused: paused,
      source: source,
      shuffle: shuffle,
      smartShuffle: smartShuffle,
      repeat: repeat,
    );
  }

  Map<String, dynamic> toJson() => {
    'queue': queue.map((t) => t.toJson()).toList(),
    'index': index,
    'posMs': position.inMilliseconds,
    'savedAt': savedAt.millisecondsSinceEpoch,
    'paused': paused,
    if (source != null) 'source': source!.toJson(),
    if (cleared) 'cleared': true,
    if (fullQueue != null)
      'fullQueue': fullQueue!.map((t) => t.toJson()).toList(),
    if (shuffle) 'shuffle': true,
    if (smartShuffle) 'smartShuffle': true,
    if (repeat != PlayerRepeat.off) 'repeat': repeat.name,
  };

  static ResumeData? fromJson(Object? json) {
    if (json is! Map) return null;
    final queue = (json['queue'] as List?)
        ?.map(Track.fromJson)
        .whereType<Track>()
        .toList();
    if (queue == null || queue.isEmpty) return null;
    final index = (json['index'] as num?)?.toInt() ?? 0;
    // Битый номер — не повод терять весь снимок: играть начнём с начала.
    final safe = index >= 0 && index < queue.length ? index : 0;
    return ResumeData(
      queue: queue,
      index: safe,
      position: Duration(milliseconds: (json['posMs'] as num?)?.toInt() ?? 0),
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['savedAt'] as num?)?.toInt() ?? 0,
      ),
      paused: json['paused'] as bool? ?? true,
      source: PlaySource.fromJson(json['source']),
      cleared: json['cleared'] == true,
      fullQueue: switch (json['fullQueue']) {
        final List raw => [for (final t in raw) ?Track.fromJson(t)],
        _ => null,
      },
      shuffle: json['shuffle'] == true,
      // Умная перемешка — подвид обычной и без неё не живёт (см. `copyWith`).
      smartShuffle: json['shuffle'] == true && json['smartShuffle'] == true,
      repeat:
          PlayerRepeat.values
              .where((m) => m.name == json['repeat'])
              .firstOrNull ??
          PlayerRepeat.off,
    );
  }
}

/// Ключ снимка в bloom.json.
const String kResumeKey = 'resume';

final resumeProvider = NotifierProvider<ResumeController, ResumeData?>(
  ResumeController.new,
);

/// Снимок сессии: на диске и в состоянии.
///
/// Состояние обновляется КАЖДОЙ записью, но карточка «Продолжить» подписывается
/// на него только когда живого трека нет (иначе тик записи раз в несколько
/// секунд перерисовывал бы её впустую). Зато когда очередь обрывают —
/// смахнули шторку, — карточка тут же показывает последний снимок и слушать
/// можно продолжить с того же места.
class ResumeController extends Notifier<ResumeData?> {
  JsonStore get _store => ref.read(jsonStoreProvider);

  @override
  ResumeData? build() => ResumeData.fromJson(_store.read(kResumeKey));

  void save(ResumeData data) {
    state = data;
    _store.write(kResumeKey, data.toJson());
  }

  void clear() {
    state = null;
    _store.write(kResumeKey, null);
  }

  /// Очередь очистили целиком. Запись при пустой очереди ничего не пишет, так
  /// что снимок помечаем явно — иначе удалённый трек возвращался после
  /// перезапуска. Сам снимок не стираем: из него рисуется «Продолжить».
  void markCleared({List<Track>? fullQueue}) {
    final data = state;
    if (data == null) return;
    save(data.markedCleared(fullQueue));
  }
}
