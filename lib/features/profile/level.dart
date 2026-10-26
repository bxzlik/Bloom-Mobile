/// Уровень слушателя — порт уровня `Stats::recount` ПК.
///
/// XP: 10 за засчитанное прослушивание; 50 за день, когда Bloom открывали или
/// что-то слушали, +10 за каждый день подряд перед ним (до +50); 100 / 250 /
/// 500 за бронзу / серебро / золото достижения. С уровня L на L + 1 — 100·L.
/// XP нигде не хранится: пересчитывается из строк, поэтому «Очистить
/// статистику» может отложить то, что они дали (kv `level.banked`).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/store/days_store.dart';
import '../../core/store/play_log.dart';
import '../../core/store/play_stats.dart';
import '../../core/sync/sync_log.dart';
import '../home/for_you.dart';
import '../home/similar_to.dart';
import 'achievements.dart';
import 'stats.dart';

const int kXpPerPlay = 10;
const int kXpPerDay = 50;
const int _kXpPerRunDay = 10; // каждый день подряд перед этим…
const int _kRunCap = 5; // …но не больше стольких
const List<int> kTierXp = [100, 250, 500];

const String _kBanked = 'level.banked';

@immutable
class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.xp,
    required this.from,
    required this.to,
    required this.plays,
    required this.days,
    required this.ach,
    required this.banked,
  });

  final int level;
  final int xp;

  /// XP, с которых начался этот уровень, и с которых начнётся следующий.
  final int from;
  final int to;

  /// Сколько дали прослушивания, дни, достижения и отложенное при очистке.
  final int plays;
  final int days;
  final int ach;
  final int banked;
}

/// Уровень по строкам: [plays] прослушиваний, дни [days] (`YYYY-MM-DD`,
/// когда открывали или слушали), взятые ступени [achievements], отложенные
/// [banked].
LevelInfo computeLevel({
  required int plays,
  required Iterable<String> days,
  required List<AchProgress> achievements,
  required int banked,
}) {
  var dayXp = 0, run = 0;
  DateTime? prev;
  for (final d in sortedDays(days.toSet())) {
    run = prev != null && nextDay(prev) == d ? run + 1 : 0;
    prev = d;
    dayXp += kXpPerDay + _kXpPerRunDay * (run < _kRunCap ? run : _kRunCap);
  }
  var achXp = 0;
  for (final a in achievements) {
    for (var t = 0; t < a.tierReached; t++) {
      achXp += kTierXp[t];
    }
  }
  final playXp = kXpPerPlay * plays;
  final xp = playXp + dayXp + achXp + banked;

  var level = 1, from = 0;
  while (xp >= from + 100 * level) {
    from += 100 * level;
    level++;
  }
  return LevelInfo(
    level: level,
    xp: xp,
    from: from,
    to: from + 100 * level,
    plays: playXp,
    days: dayXp,
    ach: achXp,
    banked: banked,
  );
}

final levelProvider = Provider<LevelInfo>(
  (ref) => computeLevel(
    plays: ref.watch(playLogProvider).events.length,
    // День засчитан, если приложение открывали или что-то слушали.
    days: [
      ...ref.watch(playStatsProvider).perDay.keys,
      ...ref.watch(daysProvider).visited,
    ],
    achievements: ref.watch(achievementsProvider),
    banked: ref.watch(levelBankedProvider),
  ),
);

/// Отложенные XP (kv `level.banked`). Пишет их только [StatsClearController].
final levelBankedProvider = NotifierProvider<LevelBankedController, int>(
  LevelBankedController.new,
);

class LevelBankedController extends Notifier<int> {
  BloomDb get _db => ref.read(dbProvider);

  @override
  int build() => (_db.get(_kBanked, 0) as num?)?.toInt() ?? 0;

  void _bank(int xp) {
    _db.set(_kBanked, xp);
    state = xp;
  }
}

/// «Очистить статистику» в шторке статистики.
final statsClearProvider = NotifierProvider<StatsClearController, void>(
  StatsClearController.new,
);

class StatsClearController extends Notifier<void> {
  @override
  void build() {}

  /// Одной транзакцией, как `Stats::clear` ПК: прослушивания, дни и отметки
  /// достижений. [keepLevel] откладывает XP, которые они дали, — уровень
  /// остаётся, где был.
  void clear({required bool keepLevel}) {
    final banked = keepLevel ? ref.read(levelProvider).xp : 0;
    final db = ref.read(dbProvider);
    db.tx(() {
      ref.read(playLogProvider.notifier).clear();
      ref.read(daysProvider.notifier).clear();
      ref.read(unlockedAchievementsProvider.notifier).clear();
      ref.read(levelBankedProvider.notifier)._bank(banked);
      SyncLog(db).markCleared(banked);
    });
    // Витрины главной собраны по сидам из стёртого топа — пересобираем сразу
    // (на ПК их сбрасывает сигнал `Stats::cleared`).
    ref.read(forYouProvider.notifier).reset();
    ref.read(similarToProvider.notifier).reset();
  }
}
