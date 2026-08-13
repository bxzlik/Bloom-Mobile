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
import '../../core/store/library_store.dart' show jsonStoreProvider;

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
    this.sourceId,
  });

  /// Треки очереди снимками. Пустой быть не может — иначе снимка нет вовсе.
  final List<Track> queue;

  /// Номер трека, на котором остановились.
  final int index;

  final Duration position;

  /// Когда сняли — для подписи «X мин. назад».
  final DateTime savedAt;

  /// Стояли на паузе (иначе — играли и приложение закрыли на ходу).
  final bool paused;

  /// Откуда набрана очередь — см. `PlaybackState.sourceId`.
  final String? sourceId;

  Track get track => queue[index];

  /// Снимок очереди: обрезка с текущего трека, чтобы он всегда попал в кадр.
  static ResumeData capture({
    required List<Track> queue,
    required int index,
    required Duration position,
    required bool paused,
    String? sourceId,
    DateTime? at,
  }) {
    final from = queue.length <= kResumeQueueLimit
        ? 0
        : (index + kResumeQueueLimit <= queue.length
              ? index
              : queue.length - kResumeQueueLimit);
    return ResumeData(
      queue: queue.sublist(from, (from + kResumeQueueLimit).clamp(0, queue.length)),
      index: index - from,
      position: position,
      paused: paused,
      sourceId: sourceId,
      savedAt: at ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'queue': queue.map((t) => t.toJson()).toList(),
    'index': index,
    'posMs': position.inMilliseconds,
    'savedAt': savedAt.millisecondsSinceEpoch,
    'paused': paused,
    if (sourceId != null) 'sourceId': sourceId,
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
      sourceId: json['sourceId'] as String?,
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
}
