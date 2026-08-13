/// Статистика профиля и достижения: те же правила, что в десктопном
/// `StatsSection`/`achievements.ts`. Считается всё из истории и дневного
/// журнала, поэтому хранилище тут в памяти.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/stats_store.dart';
import 'package:bloom/features/profile/achievements.dart';
import 'package:bloom/features/profile/stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(JsonStore.memory(seed))],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('повторное прослушивание растит счётчик, а не плодит записи', () {
    final c = _container();
    final lib = c.read(libraryProvider.notifier);
    final track = _track('sc_1');

    lib.pushHistory(track);
    lib.pushHistory(_track('sc_2'));
    lib.pushHistory(track);

    final history = c.read(libraryProvider).history;
    expect(history.length, 2);
    // Трек поднялся наверх и унёс счётчик с собой.
    expect(history.first.trackId, 'sc_1');
    expect(history.first.count, 2);
    expect(c.read(profileStatsProvider).totalPlays, 3);
  });

  test('время прослушивания и средняя длина считаются по счётчику', () {
    final c = _container();
    final lib = c.read(libraryProvider.notifier);
    lib.pushHistory(_track('sc_1', seconds: 200));
    lib.pushHistory(_track('sc_1', seconds: 200));
    lib.pushHistory(_track('sc_2', seconds: 100));

    final stats = c.read(profileStatsProvider);
    expect(stats.listenSec, 500);
    expect(stats.avgSec, 167); // 500 / 3
    expect(stats.uniqueTracks, 2);
  });

  test('площадка берётся из префикса id — даже без самого трека', () {
    final c = _container({
      // История из прошлого запуска: треков площадок в хранилище уже нет.
      'history': [
        {'id': 'ytm_1', 'at': 1, 'n': 3},
        {'id': 'sc_1', 'at': 2, 'n': 1},
      ],
    });

    final stats = c.read(profileStatsProvider);
    expect(stats.totalPlays, 4);
    expect(stats.bySource.first.source, MusicSource.ytmusic);
    expect(stats.bySource.first.plays, 3);
    expect(stats.bySource.length, 2);
    // Треков нет — время посчитать не из чего, но прослушивания не потеряны.
    expect(stats.listenSec, 0);
  });

  test('топ артистов сортируется по прослушиваниям, любимый — первый', () {
    final c = _container();
    final lib = c.read(libraryProvider.notifier);
    lib.pushHistory(_track('sc_1', artist: 'A'));
    lib.pushHistory(_track('sc_2', artist: 'B'));
    lib.pushHistory(_track('sc_2', artist: 'B'));

    final stats = c.read(profileStatsProvider);
    expect(stats.favArtist, 'B');
    expect(stats.topArtists.map((a) => a.plays), [2, 1]);
    expect(stats.uniqueArtists, 2);
  });

  test('стрик держится, пока сегодня ещё не слушали (грейс со вчера)', () {
    final today = DateTime.now();
    String key(int daysAgo) =>
        dayKey(today.subtract(Duration(days: daysAgo)));

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
    final c = _container({
      'history': [
        {'id': 'sc_1', 'at': 1, 'n': 150},
      ],
    });

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
    final c = _container({
      'history': [
        {'id': 'sc_1', 'at': 1, 'n': 150},
      ],
    });
    final unlocked = c.read(unlockedAchievementsProvider.notifier);

    // Сид: бронза «Меломана» уже выполнена, но об этом не уведомляют.
    expect(unlocked.sync(c.read(achievementsProvider)), isEmpty);
    expect(c.read(unlockedAchievementsProvider).seeded, isTrue);
    expect(
      c.read(unlockedAchievementsProvider).at.containsKey(tierKey('listener', 0)),
      isTrue,
    );

    // Дошли до серебра — вот это уже новость.
    c.read(libraryProvider.notifier).setHistoryTracks(const []);
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

  test('очистка статистики обнуляет журнал и достижения', () {
    final c = _container({
      'stats': {
        'activity': {dayKey(DateTime.now()): 5},
        'appMs': 1000,
      },
      'history': [
        {'id': 'sc_1', 'at': 1, 'n': 150},
      ],
    });
    c.read(unlockedAchievementsProvider.notifier).sync(
      c.read(achievementsProvider),
    );

    c.read(libraryProvider.notifier).clearHistory();
    c.read(statsProvider.notifier).clear();
    c.read(unlockedAchievementsProvider.notifier).clear();

    final stats = c.read(profileStatsProvider);
    expect(stats.totalPlays, 0);
    expect(stats.activeDays, 0);
    expect(stats.appSec, 0);
    expect(c.read(unlockedAchievementsProvider).at, isEmpty);
    expect(c.read(unlockedAchievementsProvider).seeded, isFalse);
  });
}
