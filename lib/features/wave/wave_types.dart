/// Общие типы «Волны» — как в `Wave` ПК.
library;

import '../../core/entities/entities.dart';

/// Чем набирается волна.
enum WaveMode {
  /// «Моя волна»: сиды из библиотеки (самое слушаемое и лайки) + свои треки.
  personal,

  /// Волна по одному треку.
  track,

  /// «Похожие на очередь»: сиды из текущей очереди.
  queue,

  /// Волна по артисту: сиды из его треков либо станция Яндекса.
  artist,
}

/// Откуда волна берёт треки: радио [station] площадки [provider] (код базы:
/// `sc`, `ytm`, `ym`).
class WaveSeed {
  const WaveSeed(this.provider, this.station);

  final String provider;
  final String station;

  /// Ключ курсора — как у ПК.
  String get key => '$provider|$station';

  @override
  bool operator ==(Object other) =>
      other is WaveSeed &&
      other.provider == provider &&
      other.station == station;

  @override
  int get hashCode => Object.hash(provider, station);
}

/// Идущая волна; переживает перезапуск в kv `wave.session` того же вида, что
/// на ПК.
class WaveRun {
  WaveRun({
    required this.mode,
    required this.seeds,
    this.about = '',
    this.native = false,
    List<String>? played,
    Map<String, int>? bonus,
  }) : played = played ?? [],
       bonus = bonus ?? {};

  final WaveMode mode;

  /// С чего начата: `artist:<ключ>`, `track:<id>`; пусто у «Моей волны» и
  /// очереди.
  final String about;

  /// Одна станция, которая учится сама (Яндекс): её порядок не трогаем.
  final bool native;

  List<WaveSeed> seeds;

  /// Услышанное в этой волне, старое первым.
  final List<String> played;

  /// Ключ артиста → дослушали (+3) и пролистнули (−2) в этой волне.
  final Map<String, int> bonus;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'about': about,
    'native': native,
    'seeds': [
      for (final s in seeds) {'p': s.provider, 's': s.station},
    ],
    'played': played,
    'bonus': bonus,
  };

  static WaveRun? fromJson(Object? json) {
    if (json is! Map) return null;
    final mode = WaveMode.values
        .where((m) => m.name == json['mode'])
        .firstOrNull;
    final seeds = [
      for (final s in (json['seeds'] as List?) ?? const [])
        if (s is Map && s['p'] is String && s['s'] is String)
          WaveSeed(s['p'] as String, s['s'] as String),
    ];
    if (mode == null || seeds.isEmpty) return null;
    final bonus = json['bonus'];
    return WaveRun(
      mode: mode,
      seeds: seeds,
      about: json['about'] as String? ?? '',
      native: json['native'] == true,
      played: (json['played'] as List?)?.whereType<String>().toList(),
      bonus: bonus is Map
          ? {
              for (final e in bonus.entries)
                if (e.key is String && e.value is num)
                  e.key as String: (e.value as num).toInt(),
            }
          : null,
    );
  }
}

/// Кандидат в пачку.
class WaveCandidate {
  WaveCandidate(this.track, this.rank, this.artists, {this.library = false});

  final Track track;

  /// Место в своей станции: 0 — верх … 20.
  final double rank;

  /// Ключи артистов трека (`artistKeys`).
  final Set<String> artists;

  /// Свой трек из библиотеки, подмешанный в «Мою волну».
  final bool library;

  double score = 0;

  String get id => track.id;
}

/// Ниже стольких секунд И ниже доли 0,3 — пролистнули; от 0,85 — дослушали.
/// Оба порога вместе: у трека на десять минут первая минута — ещё не оценка.
int completionStep(Duration played, Duration total) {
  if (total <= Duration.zero) return 0;
  final ratio = played.inMilliseconds / total.inMilliseconds;
  if (played.inMilliseconds < 20000 && ratio < 0.3) return -2;
  return ratio >= 0.85 ? 3 : 0;
}
