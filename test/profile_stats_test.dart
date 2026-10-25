/// Статистика профиля, дни, достижения и уровень: те же правила, что в
/// `Stats::recount` ПК. Всё считается из журнала прослушиваний и таблицы
/// дней, поэтому база тут в памяти.
library;

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/db/track_store.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/days_store.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:bloom/features/profile/achievements.dart';
import 'package:bloom/features/profile/level.dart';
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

/// Контейнер над базой [db]. Часы идут вперёд на минуту за обращение: у
/// каждого прослушивания свой момент, как в жизни.
ProviderContainer _container([BloomDb? db]) {
  var now = DateTime(2026, 9, 1).millisecondsSinceEpoch;
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(db ?? BloomDb.memory()),
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

/// День [daysAgo] дней назад, полдень по местному времени.
DateTime _ago(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo, 12);
}

/// Прослушивание в прошлом — строкой прямо в журнал, как пишет плеер.
void _seedPlays(BloomDb db, DateTime at, int n, [String id = 'sc:1']) {
  TrackStore(db).put([_track(id)]);
  for (var i = 0; i < n; i++) {
    db.exec('INSERT INTO plays (ts, track_id) VALUES (?, ?)', [
      at.millisecondsSinceEpoch + i,
      id,
    ]);
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

  test('дни — из журнала: серия с грейсом со вчера, рекорд, дни с музыкой', () {
    final db = BloomDb.memory();
    _seedPlays(db, _ago(1), 4);
    _seedPlays(db, _ago(2), 2);
    _seedPlays(db, _ago(4), 9);
    db.exec('INSERT INTO days (day, app_ms) VALUES (?, ?)', [
      dayKey(_ago(1)),
      3600000,
    ]);
    final c = _container(db);

    final stats = c.read(profileStatsProvider);
    // Вчера и позавчера подряд; на третий день разрыв — серия 2.
    expect(stats.streak, 2);
    expect(stats.longestStreak, 2);
    expect(stats.recordDay, 9);
    expect(stats.activeDays, 3);
    expect(stats.activity[dayKey(_ago(4))], 9);
    expect(stats.appSec, 3600);
  });

  test('«На волне» берёт самую длинную серию: пропуск ступень не отнимает', () {
    final db = BloomDb.memory();
    for (final d in [10, 9, 8, 7]) {
      _seedPlays(db, _ago(d), 1);
    }
    _seedPlays(db, _ago(1), 1);
    final c = _container(db);

    final stats = c.read(profileStatsProvider);
    expect(stats.streak, 1);
    expect(stats.longestStreak, 4);
    final streak = c
        .read(achievementsProvider)
        .firstWhere((a) => a.def.id == 'streak');
    expect(streak.tier, AchTier.bronze); // 3 дня
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

    // Один день с музыкой — до бронзы «Преданности» (7) ещё шесть.
    final devotee = list.firstWhere((a) => a.def.id == 'devotee');
    expect(devotee.unlocked, isFalse);
    expect(devotee.value, 1);
  });

  test('первый прогон засеивает молча, новые анлоки приходят потом', () {
    final db = BloomDb.memory();
    final c = _container(db);
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
    // Отметки в kv под ключами ПК.
    expect(db.getMap('ach.at').containsKey('listener:0'), isTrue);
    expect(db.get('ach.seeded'), isTrue);

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

  test('уровень: 10 за трек, 50 за день, 100/250/500 за ступени, 100·L', () {
    final c = _container();
    _listenMany(c, 150);

    final lv = c.read(levelProvider);
    expect(lv.plays, 1500);
    expect(lv.days, 50); // все 150 — в один день
    // Бронза «Меломана» и все три ступени «Марафонца» (150 за день).
    expect(lv.ach, 100 + 100 + 250 + 500);
    expect(lv.xp, 2500);
    // 100 + 200 + … + 600 = 2100 до седьмого, ещё 700 — до восьмого.
    expect(lv.level, 7);
    expect(lv.from, 2100);
    expect(lv.to, 2800);
  });

  test('уровень: дни подряд дают +10 за каждый предыдущий, до +50', () {
    final db = BloomDb.memory();
    // Семь дней подряд открывали, но ничего не слушали.
    for (var d = 6; d >= 0; d--) {
      db.exec('INSERT INTO days (day) VALUES (?)', [dayKey(_ago(d))]);
    }
    final c = _container(db);

    final lv = c.read(levelProvider);
    expect(lv.days, 50 + 60 + 70 + 80 + 90 + 100 + 100);
    expect(lv.xp, 550);
    expect(lv.level, 3); // 100 + 200 = 300 до третьего, 600 — до четвёртого
    expect(lv.from, 300);
    expect(lv.to, 600);
  });

  test(
    'визит и время в приложении — в таблице дней, переживают перезапуск',
    () {
      final db = BloomDb.memory();
      final c = _container(db);
      c.read(daysProvider.notifier)
        ..visit()
        ..visit()
        ..addUsage(1500)
        ..addUsage(500);

      expect(c.read(daysProvider).visited.length, 1);
      expect(c.read(daysProvider).appMs, 2000);

      final again = _container(db);
      expect(again.read(daysProvider).appMs, 2000);
      expect(again.read(levelProvider).days, 50);
    },
  );

  test('очистка с уровнем: XP откладываются, журнал и отметки уходят', () {
    final db = BloomDb.memory();
    final c = _container(db);
    _listenMany(c, 150);
    c
        .read(unlockedAchievementsProvider.notifier)
        .sync(c.read(achievementsProvider));
    final before = c.read(levelProvider).xp;

    c.read(statsClearProvider.notifier).clear(keepLevel: true);

    final stats = c.read(profileStatsProvider);
    expect(stats.totalPlays, 0);
    expect(stats.activeDays, 0);
    expect(stats.appSec, 0);
    expect(c.read(unlockedAchievementsProvider).at, isEmpty);
    // Первый прогон уже был — взятое заново придёт уведомлением.
    expect(c.read(unlockedAchievementsProvider).seeded, isTrue);
    expect(db.get('level.banked'), before);
    // Сегодняшний визит остаётся: приложение открыто.
    expect(c.read(levelProvider).xp, before + 50);
  });

  test('очистка без уровня: остаётся только сегодняшний визит', () {
    final c = _container();
    _listenMany(c, 150);

    c.read(statsClearProvider.notifier).clear(keepLevel: false);

    final lv = c.read(levelProvider);
    expect(lv.banked, 0);
    expect(lv.xp, 50);
    expect(lv.level, 1);
  });
}
