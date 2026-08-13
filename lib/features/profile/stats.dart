/// Расчёт статистики профиля — порт вычислений из десктопного `StatsSection`.
///
/// Источники ровно те же: история (сколько раз слушали каждый трек), дневной
/// журнал и время в приложении. Ничего своего не персистится — всё считается
/// на лету из [LibraryState] и [StatsState].
///
/// Разбивка по площадкам берётся из ПРЕФИКСА id, а не из поля трека: треки
/// площадок живут в памяти, и после перезапуска половина записей истории уже не
/// резолвится в объект — иначе в «где слушали чаще» остался бы один SoundCloud.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../core/store/stats_store.dart';

/// Строка «Топ треков».
class TrackPlays {
  const TrackPlays(this.track, this.plays);

  final Track track;
  final int plays;
}

/// Строка «Топ исполнителей».
class ArtistPlays {
  const ArtistPlays(this.name, this.plays, this.cover);

  final String name;
  final int plays;

  /// Обложка самого слушаемого его трека — вместо аватара, за которым пришлось
  /// бы лезть на площадку.
  final String? cover;
}

/// Строка «Где слушали чаще».
class SourcePlays {
  const SourcePlays(this.source, this.plays, this.seconds);

  final MusicSource source;
  final int plays;
  final int seconds;
}

class ProfileStats {
  const ProfileStats({
    required this.libraryTracks,
    required this.totalPlays,
    required this.listenSec,
    required this.uniqueTracks,
    required this.uniqueArtists,
    required this.avgSec,
    required this.daySpan,
    required this.recordDay,
    required this.recordDate,
    required this.activeDays,
    required this.streak,
    required this.appSec,
    required this.topTracks,
    required this.topArtists,
    required this.bySource,
    required this.activity,
  });

  /// Сколько треков в библиотеке — единственное число не из истории.
  final int libraryTracks;

  final int totalPlays;
  final int listenSec;
  final int uniqueTracks;
  final int uniqueArtists;

  /// Средняя длина прослушанного трека, секунды.
  final int avgSec;

  /// На сколько дней растянута история — знаменатель «в среднем за день».
  final int daySpan;

  final int recordDay;
  final DateTime? recordDate;

  /// Дней, в которые вообще что-то слушали.
  final int activeDays;

  /// Дней подряд с прослушиваниями, считая от сегодня.
  final int streak;

  final int appSec;

  final List<TrackPlays> topTracks;
  final List<ArtistPlays> topArtists;
  final List<SourcePlays> bySource;

  /// Дневной журнал как есть — для графика и теплокарты.
  final Map<String, int> activity;

  String? get favArtist => topArtists.isEmpty ? null : topArtists.first.name;

  static ProfileStats build(LibraryState lib, StatsState stats) {
    var totalPlays = 0;
    var listenSec = 0;
    final artists = <String, ({int plays, String? cover, int best})>{};
    final sources = <MusicSource, ({int plays, int seconds})>{};
    final rows = <TrackPlays>[];

    var firstTs = DateTime.now().millisecondsSinceEpoch;
    var lastTs = firstTs;

    for (final entry in lib.history) {
      final plays = entry.count;
      totalPlays += plays;

      final source = MusicSource.fromId(entry.trackId);
      final track = lib.tracks[entry.trackId];
      final seconds = track == null ? 0 : track.duration.inSeconds * plays;
      final was = sources[source] ?? (plays: 0, seconds: 0);
      sources[source] = (
        plays: was.plays + plays,
        seconds: was.seconds + seconds,
      );

      if (entry.at > 0) {
        if (entry.at < firstTs) firstTs = entry.at;
        if (entry.at > lastTs) lastTs = entry.at;
      }

      // Дальше нужен сам трек: без него нечего показать в топах и нечего
      // складывать во время прослушивания.
      if (track == null) continue;
      listenSec += seconds;
      if (plays > 0) rows.add(TrackPlays(track, plays));

      final name = track.artist.isEmpty ? 'Unknown Artist' : track.artist;
      final artist = artists[name] ?? (plays: 0, cover: null, best: -1);
      artists[name] = (
        plays: artist.plays + plays,
        cover: track.cover != null && plays > artist.best
            ? track.cover
            : artist.cover,
        best: track.cover != null && plays > artist.best ? plays : artist.best,
      );
    }

    rows.sort((a, b) => b.plays.compareTo(a.plays));

    final topArtists =
        artists.entries
            .where((e) => e.value.plays > 0)
            .map((e) => ArtistPlays(e.key, e.value.plays, e.value.cover))
            .toList()
          ..sort((a, b) => b.plays.compareTo(a.plays));

    final bySource =
        sources.entries
            .where((e) => e.value.plays > 0)
            .map((e) => SourcePlays(e.key, e.value.plays, e.value.seconds))
            .toList()
          ..sort((a, b) => b.plays.compareTo(a.plays));

    var recordDay = 0;
    String? recordKey;
    var activeDays = 0;
    for (final e in stats.activity.entries) {
      if (e.value > 0) activeDays++;
      if (e.value > recordDay) {
        recordDay = e.value;
        recordKey = e.key;
      }
    }

    final span = ((lastTs - firstTs) / 86400000).ceil();

    return ProfileStats(
      libraryTracks: lib.inLib.length,
      totalPlays: totalPlays,
      listenSec: listenSec,
      uniqueTracks: lib.history.length,
      uniqueArtists: artists.length,
      avgSec: totalPlays > 0 ? (listenSec / totalPlays).round() : 0,
      daySpan: span < 1 ? 1 : span,
      recordDay: recordDay,
      recordDate: recordKey == null ? null : DateTime.tryParse(recordKey),
      activeDays: activeDays,
      streak: _streak(stats.activity),
      appSec: (stats.appMs / 1000).round(),
      topTracks: rows.take(10).toList(),
      topArtists: topArtists.take(10).toList(),
      bySource: bySource,
      activity: stats.activity,
    );
  }
}

/// Дней подряд с прослушиваниями. Отсчёт от сегодня, но если сегодня ещё не
/// слушали — от вчера: иначе стрик обнулялся бы каждое утро (десктопный грейс).
int _streak(Map<String, int> log) {
  var cursor = DateTime.now();
  if ((log[dayKey(cursor)] ?? 0) == 0) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while ((log[dayKey(cursor)] ?? 0) > 0) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

final profileStatsProvider = Provider<ProfileStats>((ref) {
  return ProfileStats.build(
    ref.watch(libraryProvider),
    ref.watch(statsProvider),
  );
});

/// «Nч Nм» / «N мин» — десктопный `fmtDurLong`.
String fmtDurLong(int seconds) {
  if (seconds <= 0) return '0 мин';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '$hч $mм' : '$m мин';
}

/// «м:сс» — средняя длина трека.
String fmtClock(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
