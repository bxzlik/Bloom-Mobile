/// Сборка «Итогов» из журнала прослушиваний — порт десктопного
/// `features/wrapped/lib/aggregate.ts`.
///
/// Чистая функция: события + снимки треков → всё, что показывают слайды. Один
/// проход по журналу, события идут по возрастанию `ts`.
///
/// Время прослушивания — ОЦЕНКА: Σ длительность трека × число прослушиваний.
/// Прослушивание засчитывается на ~90% трека, поэтому оценка близка к правде,
/// но замером не является.
library;

import 'package:flutter/foundation.dart';

import '../../core/entities/entities.dart';
import '../../core/store/stats_store.dart' show dayKey;
import 'periods.dart';
import 'play_log.dart';

@immutable
class WrappedTrack {
  const WrappedTrack({
    required this.id,
    required this.name,
    required this.artist,
    required this.cover,
    required this.source,
    required this.plays,
    required this.seconds,
  });

  final String id;
  final String name;
  final String artist;
  final String? cover;
  final MusicSource source;
  final int plays;

  /// Оценка времени, отданного этому треку за период.
  final int seconds;

  WrappedTrack _plus(int seconds) => WrappedTrack(
    id: id,
    name: name,
    artist: artist,
    cover: cover,
    source: source,
    plays: plays + 1,
    seconds: this.seconds + seconds,
  );
}

@immutable
class WrappedArtist {
  const WrappedArtist({
    required this.name,
    required this.plays,
    required this.cover,
  });

  final String name;
  final int plays;

  /// Обложка самого заслушанного его трека за период — вместо аватара, за
  /// которым пришлось бы лезть на площадку (аватар догружается в интерфейсе).
  final String? cover;
}

@immutable
class WrappedSource {
  const WrappedSource({
    required this.source,
    required this.plays,
    required this.seconds,
  });

  final MusicSource source;
  final int plays;
  final int seconds;
}

@immutable
class WrappedRecordDay {
  const WrappedRecordDay(this.date, this.plays);

  final DateTime date;
  final int plays;
}

@immutable
class WrappedData {
  const WrappedData({
    required this.range,
    required this.plays,
    required this.uniqueTracks,
    required this.uniqueArtists,
    required this.seconds,
    required this.topTracks,
    required this.topArtists,
    required this.sources,
    required this.newArtists,
    required this.newArtistsCount,
    required this.newTracksCount,
    required this.recordDay,
    required this.hours,
    required this.peakHour,
    required this.nightShare,
    required this.activeDays,
    required this.streak,
  });

  final PeriodRange range;

  /// Всего засчитанных прослушиваний за период.
  final int plays;
  final int uniqueTracks;
  final int uniqueArtists;

  /// Оценка времени прослушивания, секунды.
  final int seconds;

  final List<WrappedTrack> topTracks;
  final List<WrappedArtist> topArtists;
  final List<WrappedSource> sources;

  /// Артисты, впервые появившиеся в журнале в этом периоде.
  final List<WrappedArtist> newArtists;
  final int newArtistsCount;
  final int newTracksCount;

  /// Самый «залипательный» день периода.
  final WrappedRecordDay? recordDay;

  /// Гистограмма по часам суток (24 значения, локальное время).
  final List<int> hours;
  final int peakHour;

  /// Доля прослушиваний с 00:00 до 05:59 — «ночной слушатель».
  final double nightShare;

  /// Дней, в которые вообще что-то играло.
  final int activeDays;

  /// Самая длинная серия дней подряд внутри периода.
  final int streak;

  bool get isEmpty => plays == 0;
}

/// Сколько строк показываем в топах — десктопный `slice(0, 5)`.
const int kWrappedTopSize = 5;

/// Ключ группировки артиста: регистр и лишние пробелы не должны плодить дубли.
String _artistKey(String name) => name.trim().toLowerCase();

WrappedData buildWrapped(PlayLog log, PeriodRange range) {
  final from = range.fromMs;
  final to = range.toMs;

  // Что уже звучало ДО периода — нужно для «открытий» (новых артистов и
  // треков).
  final seenTracks = <String>{};
  final seenArtists = <String>{};

  final trackAgg = <String, WrappedTrack>{};
  final artistAgg = <String, WrappedArtist>{};
  // Сколько прослушиваний было у трека, от которого взята обложка артиста.
  final artistBest = <String, int>{};
  final srcAgg = <MusicSource, WrappedSource>{};
  final dayAgg = <String, int>{};
  final hours = List<int>.filled(24, 0);

  var plays = 0;
  var seconds = 0;
  var newTracksCount = 0;
  final newArtistKeys = <String>{};

  for (final e in log.events) {
    if (e.ts < from) {
      seenTracks.add(e.id);
      final before = log.meta[e.id];
      if (before != null && before.artist.isNotEmpty) {
        seenArtists.add(_artistKey(before.artist));
      }
      continue;
    }
    // События отсортированы по ts — дальше только «будущее».
    if (e.ts >= to) break;

    final m = log.meta[e.id];
    final name = m?.name ?? '';
    final artist = m?.artist ?? '';
    final cover = m?.cover;
    final sec = m?.seconds ?? 0;
    final source = MusicSource.fromId(e.id);

    plays++;
    seconds += sec;

    final was = trackAgg[e.id];
    if (was != null) {
      trackAgg[e.id] = was._plus(sec);
    } else {
      trackAgg[e.id] = WrappedTrack(
        id: e.id,
        name: name,
        artist: artist,
        cover: cover,
        source: source,
        plays: 1,
        seconds: sec,
      );
      if (!seenTracks.contains(e.id)) newTracksCount++;
    }

    if (artist.isNotEmpty) {
      final key = _artistKey(artist);
      final a = artistAgg[key];
      if (a == null) {
        artistAgg[key] = WrappedArtist(name: artist, plays: 1, cover: cover);
        artistBest[key] = cover != null ? 1 : -1;
        if (!seenArtists.contains(key)) newArtistKeys.add(key);
      } else {
        // Обложка артиста — от его самого заслушанного трека в периоде.
        final trackPlays = trackAgg[e.id]!.plays;
        final better = cover != null && trackPlays > (artistBest[key] ?? -1);
        artistAgg[key] = WrappedArtist(
          name: a.name,
          plays: a.plays + 1,
          cover: better ? cover : a.cover,
        );
        if (better) artistBest[key] = trackPlays;
      }
    }

    final s = srcAgg[source];
    srcAgg[source] = WrappedSource(
      source: source,
      plays: (s?.plays ?? 0) + 1,
      seconds: (s?.seconds ?? 0) + sec,
    );

    final at = DateTime.fromMillisecondsSinceEpoch(e.ts);
    final key = dayKey(at);
    dayAgg[key] = (dayAgg[key] ?? 0) + 1;
    hours[at.hour]++;
  }

  final topTracks = trackAgg.values.toList()
    ..sort((a, b) {
      final byPlays = b.plays.compareTo(a.plays);
      return byPlays != 0 ? byPlays : b.seconds.compareTo(a.seconds);
    });

  final artists = artistAgg.values.toList();
  final topArtists = [...artists]..sort((a, b) => b.plays.compareTo(a.plays));
  final newArtists =
      artists.where((a) => newArtistKeys.contains(_artistKey(a.name))).toList()
        ..sort((a, b) => b.plays.compareTo(a.plays));

  final sources = srcAgg.values.toList()
    ..sort((a, b) => b.plays.compareTo(a.plays));

  // Рекордный день.
  WrappedRecordDay? recordDay;
  for (final e in dayAgg.entries) {
    if (recordDay != null && e.value <= recordDay.plays) continue;
    final date = DateTime.parse(e.key);
    recordDay = WrappedRecordDay(date, e.value);
  }

  // Самая длинная серия дней подряд внутри периода.
  final days = dayAgg.keys.toList()..sort();
  var streak = 0;
  var run = 0;
  DateTime? prev;
  for (final key in days) {
    final date = DateTime.parse(key);
    run = prev != null && date.difference(prev).inDays == 1 ? run + 1 : 1;
    prev = date;
    if (run > streak) streak = run;
  }

  var peakHour = 0;
  for (var h = 1; h < 24; h++) {
    if (hours[h] > hours[peakHour]) peakHour = h;
  }
  final night = hours.take(6).fold(0, (s, n) => s + n);

  return WrappedData(
    range: range,
    plays: plays,
    uniqueTracks: trackAgg.length,
    uniqueArtists: artistAgg.length,
    seconds: seconds,
    topTracks: topTracks.take(kWrappedTopSize).toList(),
    topArtists: topArtists.take(kWrappedTopSize).toList(),
    sources: sources,
    newArtists: newArtists.take(kWrappedTopSize).toList(),
    newArtistsCount: newArtistKeys.length,
    newTracksCount: newTracksCount,
    recordDay: recordDay,
    hours: hours,
    peakHour: peakHour,
    nightShare: plays > 0 ? night / plays : 0,
    activeDays: dayAgg.length,
    streak: streak,
  );
}
