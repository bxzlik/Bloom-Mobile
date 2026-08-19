/// Общие типы «Волны» — порт `src/wave/types.ts` из десктопного Bloom.
///
/// Отличие от десктопа: `Candidate` несёт готовый [Track], а не сырой ответ
/// SoundCloud. Реестра гостевых треков, живущего в памяти процесса, у нас нет
/// вовсе — очередь плеера хранит сами треки (см. `PlaybackState.queue`),
/// поэтому кандидату незачем таскать сырьё до момента постановки в очередь.
///
/// Жанры при этом лежат ОТДЕЛЬНО от трека: у SoundCloud вкусовой сигнал даёт не
/// только поле `genre`, но и теги, а класть теги в `Track.genres` нельзя — их
/// увидел бы весь остальной интерфейс.
library;

import '../../core/entities/entities.dart';

/// Чем набирается волна.
enum WaveMode {
  /// «Моя волна»: несколько сидов из библиотеки + подмешивание знакомых.
  personal,

  /// Волна по одному треку.
  track,

  /// «Похожие на очередь»: сиды из текущей очереди, без подмешивания.
  queue,

  /// Волна по артисту: сиды из его треков (SoundCloud) либо нативная станция.
  artist,
}

/// Откуда пришёл кандидат — влияет и на фильтры, и на скоринг.
enum WaveOrigin {
  /// `stations/track-stations:<id>` — основная выдача площадки.
  station,

  /// `tracks/<id>/related` — вкусовые рекомендации к сиду.
  related,

  /// Знакомый трек из библиотеки, подмешанный к «Моей волне».
  library,
}

class WaveCandidate {
  const WaveCandidate({
    required this.track,
    required this.origin,
    required this.sourceRank,
    required this.artistKey,
    this.genres = const [],
  });

  final Track track;
  final WaveOrigin origin;

  /// Позиция в ответе площадки: чем меньше, тем выше её собственная оценка.
  final int sourceRank;

  /// Имя артиста, приведённое к нижнему регистру — ключ антиповторов.
  final String artistKey;

  /// Жанры и теги в нижнем регистре.
  final List<String> genres;

  String get id => track.id;

  bool get isLibrary => origin == WaveOrigin.library;
}

/// Память одного сеанса волны: что уже играло, кого поднимать в выдаче и
/// докуда пролистаны станции сидов.
class WaveSession {
  WaveSession({
    required this.mode,
    required this.seeds,
    required this.startedAt,
    List<String>? playedIds,
    Map<String, double>? artistBonus,
  }) : playedIds = playedIds ?? [],
       artistBonus = artistBonus ?? {};

  final WaveMode mode;

  /// Сквозные id треков-сидов.
  final List<String> seeds;
  final int startedAt;

  /// Что уже сыграло в этом сеансе — антиповторы.
  final List<String> playedIds;

  /// Насколько поднимать артиста в выдаче: копится дослушиваниями и падает на
  /// скипах.
  final Map<String, double> artistBonus;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'seeds': seeds,
    'startedAt': startedAt,
    'playedIds': playedIds,
    'artistBonus': artistBonus,
  };

  static WaveSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final mode = WaveMode.values
        .where((m) => m.name == json['mode'])
        .firstOrNull;
    if (mode == null) return null;
    return WaveSession(
      mode: mode,
      seeds: (json['seeds'] as List?)?.whereType<String>().toList() ?? const [],
      startedAt: (json['startedAt'] as num?)?.toInt() ?? 0,
      playedIds:
          (json['playedIds'] as List?)?.whereType<String>().toList() ?? [],
      artistBonus: _numMap(json['artistBonus'], (v) => v.toDouble()),
    );
  }
}

Map<String, T> _numMap<T extends num>(Object? raw, T Function(num) cast) {
  if (raw is! Map) return {};
  return {
    for (final e in raw.entries)
      if (e.key is String && e.value is num)
        e.key as String: cast(e.value as num),
  };
}

/// Чем волна кормится с площадки: своим движком по SoundCloud или нативной
/// станцией Яндекса.
enum WaveEngineKind { soundcloud, yandex }

/// Приговор прослушиванию — порт `classifyCompletion` из `db/history.ts`.
enum WaveVerdict { skip, finish, neutral }

/// Ниже стольких секунд И ниже [_kSkipRatio] доли — это скип, а не «послушал».
/// Оба порога вместе: у трека на десять минут первая минута — ещё не оценка.
const double _kSkipPlayedSec = 20;
const double _kSkipRatio = 0.3;
const double _kFinishRatio = 0.85;

WaveVerdict classifyCompletion(Duration played, Duration total) {
  if (total <= Duration.zero) return WaveVerdict.neutral;
  final playedSec = played.inMilliseconds / 1000;
  final ratio = played.inMilliseconds / total.inMilliseconds;
  if (playedSec < _kSkipPlayedSec && ratio < _kSkipRatio) {
    return WaveVerdict.skip;
  }
  if (ratio >= _kFinishRatio) return WaveVerdict.finish;
  return WaveVerdict.neutral;
}

/// Имя артиста как ключ сравнения — порт `normalizeArtist`.
String normalizeArtist(String? name) => (name ?? '').trim().toLowerCase();
