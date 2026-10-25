/// Статистика профиля и достижения: те же правила, что в десктопном
/// `StatsSection`/`achievements.ts`. Считается всё из журнала прослушиваний,
/// старой истории и дневного журнала, поэтому хранилища тут в памяти.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:bloom/core/store/stats_store.dart';
import 'package:bloom/features/profile/achievements.dart';
import 'package:bloom/features/profile/stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

Track _track(
  String id, {
  String artist = 'Artist',
  int seconds = 100,
  MusicSource source = MusicSource.soundcloud,
}) => Track(
  id: id,
  name: 'Song $id',
  artist: artist,
  duration: Duration(seconds: seconds),
  source: source,
);

ProviderContainer _container([Map<String, dynamic>? seed]) {
  // Часы идут вперёд на минуту за обращение: у каждого прослушивания свой
  // момент, как в жизни.
  var now = DateTime(2026, 9, 1).millisecondsSinceEpoch;
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory(seed)),
      dbProvider.overrideWithValue(BloomDb.memory()),
      playLogClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(now += 60000),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Засчитать прослушивание — то же, что делает плеер.
void _listen(ProviderContainer c, Track track) =>
    c.read(playLogProvider.notifier).log(track);

/// [n] прослушиваний одного трека.
void _listenMany(ProviderContainer c, int n) {
  for (var i = 0; i < n; i++) {
    _listen(c, _track('sc:1'));
  }
}

void main() {
  test('повторное прослушивание растит счётчик, а не плодит записи', () {
    final c = _container();
    final track = _track('sc:1');

    _listen(c, track);
    _listen(c, _track('sc:2'));
    _listen(c, track);

    final rows = c.read(playStatsProvider).historyRows();
    expect(rows.length, 2);
    // Трек поднялся наверх и унёс счётчик с собой.
    expect(rows.first.id, 'sc:1');
    expect(rows.first.count, 2);
    expect(c.read(profileStatsProvider).totalPlays, 3);
  });

  test('время прослушивания и средняя длина считаются по счётчику', () {
    final c = _container();
    _listen(c, _track('sc:1', seconds: 200));
    _listen(c, _track('sc:1', seconds: 200));
    _listen(c, _track('sc:2', seconds: 100));

    final stats = c.read(profileStatsProvider);
    expect(stats.listenSec, 500);
    expect(stats.avgSec, 167); // 500 / 3
    expect(stats.uniqueTracks, 2);
  });

  test('трек, которого нет в библиотеке, в топе остаётся — по снимку', () {
    final c = _container();
    _listen(c, _track('sc:1', artist: 'A'));
    _listen(c, _track('sc:1', artist: 'A'));

    // Библиотека пуста: трек только слушали, но не сохраняли.
    final stats = c.read(profileStatsProvider);
    expect(stats.topTracks.single.track.id, 'sc:1');
    expect(stats.topTracks.single.plays, 2);
    expect(stats.favArtist, 'A');
  });

  test('прослушивания раскладываются по площадкам', () {
    final c = _container();
    for (var i = 0; i < 3; i++) {
      _listen(c, _track('ytm:1', source: MusicSource.ytmusic));
    }
    _listen(c, _track('sc:1'));

    final stats = c.read(profileStatsProvider);
    expect(stats.totalPlays, 4);
    expect(stats.bySource.first.source, MusicSource.ytmusic);
    expect(stats.bySource.first.plays, 3);
    expect(stats.bySource.length, 2);
  });

  test('топ артистов сортируется по прослушиваниям, любимый — первый', () {
    final c = _container();
    _listen(c, _track('sc:1', artist: 'A'));
    _listen(c, _track('sc:2', artist: 'B'));
    _listen(c, _track('sc:2', artist: 'B'));

    final stats = c.read(profileStatsProvider);
    expect(stats.favArtist, 'B');
    expect(stats.topArtists.map((a) => a.plays), [2, 1]);
    expect(stats.uniqueArtists, 2);
  });

  test('мультиартистный трек идёт в зачёт каждому участнику', () {
    final c = _container();
    _listen(c, _track('sc:1', artist: 'reidenshi, Øneheart'));
    _listen(c, _track('sc:2', artist: 'Øneheart'));
    _listen(c, _track('sc:2', artist: 'Øneheart'));

    final stats = c.read(profileStatsProvider);
    // Склеенного имени в топе нет — по нему не нашлись бы ни аватар, ни
    // страница артиста.
    expect(stats.topArtists.map((a) => a.name), ['Øneheart', 'reidenshi']);
    expect(stats.topArtists.map((a) => a.plays), [3, 1]);
    expect(stats.uniqueArtists, 2);
    expect(stats.favArtist, 'Øneheart');
    expect(stats.topArtists.last.source, MusicSource.soundcloud);
  });

  test('стрик держится, пока сегодня ещё не слушали (грейс со вчера)', () {
    final today = DateTime.now();
    String key(int daysAgo) => dayKey(today.subtract(Duration(days: daysAgo)));

    final c = _container({
      'stats': {
        'activity': {key(1): 4, key(2): 2, key(4): 9},
        'appMs': 3600000,
      },
    });

    final stats = c.read(profileStatsProvider);
    // Вчера и позавчера подряд; на третий день разрыв — стрик 2.
    expect(stats.streak, 2);
    expect(stats.recordDay, 9);
    expect(stats.activeDays, 3);
    expect(stats.appSec, 3600);
  });

  test('достижения: тиры, прогресс до следующего и максимум', () {
    final c = _container();
    _listenMany(c, 150);

    final list = c.read(achievementsProvider);
    final listener = list.firstWhere((a) => a.def.id == 'listener');
    // 150 прослушиваний — бронза (100) взята, до серебра (1000) далеко.
    expect(listener.tierReached, 1);
    expect(listener.tier, AchTier.bronze);
    expect(listener.nextTarget, 1000);
    expect(listener.ratio, closeTo((150 - 100) / (1000 - 100), 0.001));
    expect(listener.maxed, isFalse);

    // Ни одного активного дня — достижение за активные дни ещё не начато.
    final devotee = list.firstWhere((a) => a.def.id == 'devotee');
    expect(devotee.unlocked, isFalse);
    expect(devotee.ratio, 0);
  });

  test('первый прогон засеивает молча, новые анлоки приходят потом', () {
    final c = _container();
    _listenMany(c, 150);
    final unlocked = c.read(unlockedAchievementsProvider.notifier);

    // Сид: бронза «Меломана» уже выполнена, но об этом не уведомляют.
    expect(unlocked.sync(c.read(achievementsProvider)), isEmpty);
    expect(c.read(unlockedAchievementsProvider).seeded, isTrue);
    expect(
      c
          .read(unlockedAchievementsProvider)
          .at
          .containsKey(tierKey('listener', 0)),
      isTrue,
    );

    // Дошли до серебра — вот это уже новость.
    final grown = [
      for (final a in c.read(achievementsProvider))
        if (a.def.id == 'listener')
          AchProgress(def: a.def, value: 1200, tierReached: 2, ratio: 1)
        else
          a,
    ];
    final fresh = unlocked.sync(grown);
    expect(fresh.single.ach.def.id, 'listener');
    expect(fresh.single.tier, AchTier.silver);
  });

  test('очистка статистики обнуляет журналы и достижения', () {
    final c = _container({
      'stats': {
        'activity': {dayKey(DateTime.now()): 5},
        'appMs': 1000,
      },
    });
    _listen(c, _track('sc:2'));
    c
        .read(unlockedAchievementsProvider.notifier)
        .sync(c.read(achievementsProvider));

    // Ровно то, что делает «Очистить» в шторке статистики.
    c.read(statsProvider.notifier).clear();
    c.read(unlockedAchievementsProvider.notifier).clear();
    c.read(playLogProvider.notifier).clear();

    final stats = c.read(profileStatsProvider);
    expect(stats.totalPlays, 0);
    expect(stats.activeDays, 0);
    expect(stats.appSec, 0);
    expect(c.read(unlockedAchievementsProvider).at, isEmpty);
    expect(c.read(unlockedAchievementsProvider).seeded, isFalse);
  });
}
