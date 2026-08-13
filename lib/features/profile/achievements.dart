/// Достижения профиля — порт десктопного `achievements.ts` + его стора.
///
/// Список декларативный: у каждого достижения три порога (бронза/серебро/
/// золото) и функция, достающая своё число из уже посчитанной статистики.
/// Значения НЕ хранятся — считаются на лету; в файл ложатся только даты
/// разблокировки, чтобы показать «получено 12 августа» и один раз всплыть
/// уведомлением.
///
/// Первый прогон «засеивает» уже выполненное молча (десктопный `seeded`):
/// иначе пользователь с историей при первом же открытии получил бы пачку
/// уведомлений разом.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../core/l10n/l10n.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;
import 'stats.dart';

enum AchTier { bronze, silver, gold }

const List<AchTier> kTierOrder = AchTier.values;

String tierLabel(AppLocalizations l, AchTier tier) => switch (tier) {
  AchTier.bronze => l.achTierBronze,
  AchTier.silver => l.achTierSilver,
  AchTier.gold => l.achTierGold,
};

Color tierColor(AchTier tier) => switch (tier) {
  AchTier.bronze => const Color(0xFFCD7F32),
  AchTier.silver => const Color(0xFFC0C6CF),
  AchTier.gold => const Color(0xFFFFC24B),
};

/// Единица метрики — влияет только на подпись прогресса.
enum AchUnit { count, time }

const int _h = 3600;

class AchDef {
  const AchDef({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
    required this.unit,
    required this.tiers,
    required this.value,
  });

  final String id;
  final IconData icon;

  /// Название и подпись резолвятся при отрисовке: таблица собирается один раз
  /// на весь процесс и обязана пережить смену языка.
  final String Function(AppLocalizations l) name;
  final String Function(AppLocalizations l) description;
  final AchUnit unit;

  /// Три порога по возрастанию.
  final List<int> tiers;

  final int Function(ProfileStats stats) value;
}

/// Тот же состав и те же пороги, что на десктопе.
final List<AchDef> kAchievements = [
  AchDef(
    id: 'listener',
    icon: SolarIconsBold.play,
    name: (l) => l.achListenerName,
    description: (l) => l.achListenerDesc,
    unit: AchUnit.count,
    tiers: const [100, 1000, 10000],
    value: (s) => s.totalPlays,
  ),
  AchDef(
    id: 'time',
    icon: SolarIconsBold.headphonesRound,
    name: (l) => l.achTimeName,
    description: (l) => l.achTimeDesc,
    unit: AchUnit.time,
    tiers: const [10 * _h, 100 * _h, 500 * _h],
    value: (s) => s.listenSec,
  ),
  AchDef(
    id: 'streak',
    icon: SolarIconsBold.fire,
    name: (l) => l.achStreakName,
    description: (l) => l.achStreakDesc,
    unit: AchUnit.count,
    tiers: const [3, 7, 30],
    value: (s) => s.streak,
  ),
  AchDef(
    id: 'marathon',
    icon: SolarIconsBold.medalStar,
    name: (l) => l.achMarathonName,
    description: (l) => l.achMarathonDesc,
    unit: AchUnit.count,
    tiers: const [20, 50, 100],
    value: (s) => s.recordDay,
  ),
  AchDef(
    id: 'veteran',
    icon: SolarIconsBold.crownStar,
    name: (l) => l.achVeteranName,
    description: (l) => l.achVeteranDesc,
    unit: AchUnit.time,
    tiers: const [5 * _h, 50 * _h, 200 * _h],
    value: (s) => s.appSec,
  ),
  AchDef(
    id: 'devotee',
    icon: SolarIconsBold.calendar,
    name: (l) => l.achDevoteeName,
    description: (l) => l.achDevoteeDesc,
    unit: AchUnit.count,
    tiers: const [7, 30, 100],
    value: (s) => s.activeDays,
  ),
];

/// Посчитанное достижение — всё, что нужно карточке.
class AchProgress {
  const AchProgress({
    required this.def,
    required this.value,
    required this.tierReached,
    required this.ratio,
  });

  final AchDef def;
  final int value;

  /// Сколько порогов пройдено, 0..3.
  final int tierReached;

  /// Доля до следующего порога; у взятого целиком — 1.
  final double ratio;

  AchTier? get tier => tierReached > 0 ? kTierOrder[tierReached - 1] : null;

  bool get unlocked => tierReached > 0;
  bool get maxed => tierReached >= def.tiers.length;
  int? get nextTarget => maxed ? null : def.tiers[tierReached];
}

List<AchProgress> buildAchievements(ProfileStats stats) => [
  for (final def in kAchievements) _progress(def, stats),
];

AchProgress _progress(AchDef def, ProfileStats stats) {
  final value = def.value(stats);
  var reached = 0;
  for (final target in def.tiers) {
    if (value >= target) reached++;
  }
  final maxed = reached >= def.tiers.length;
  final prev = reached > 0 ? def.tiers[reached - 1] : 0;
  final next = maxed ? 0 : def.tiers[reached];
  return AchProgress(
    def: def,
    value: value,
    tierReached: reached,
    ratio: maxed ? 1 : ((value - prev) / (next - prev)).clamp(0.0, 1.0),
  );
}

final achievementsProvider = Provider<List<AchProgress>>(
  (ref) => buildAchievements(ref.watch(profileStatsProvider)),
);

/// Ключ разблокировки: достижение и номер порога.
String tierKey(String id, int tierIndex) => '$id:$tierIndex';

@immutable
class UnlockedAchievements {
  const UnlockedAchievements({this.at = const {}, this.seeded = false});

  /// `id:тир` → когда получено.
  final Map<String, int> at;

  /// Прошёл ли молчаливый первый прогон.
  final bool seeded;
}

final unlockedAchievementsProvider =
    NotifierProvider<AchievementsController, UnlockedAchievements>(
      AchievementsController.new,
    );

class AchievementsController extends Notifier<UnlockedAchievements> {
  @override
  UnlockedAchievements build() {
    final raw = ref.read(jsonStoreProvider).readMap('achievements');
    final at = raw['at'];
    return UnlockedAchievements(
      at: at is Map
          ? {
              for (final e in at.entries)
                if (e.key is String && e.value is num)
                  e.key as String: (e.value as num).toInt(),
            }
          : const {},
      seeded: raw['seeded'] == true,
    );
  }

  void _save() {
    ref.read(jsonStoreProvider).write('achievements', {
      'at': state.at,
      'seeded': state.seeded,
    });
  }

  /// Свести хранимое с текущим прогрессом. Возвращает НОВЫЕ разблокировки
  /// (достижение и номер взятого тира) — на первом прогоне список пуст,
  /// сколько бы всего ни засеялось.
  List<({AchProgress ach, AchTier tier})> sync(List<AchProgress> list) {
    final next = {...state.at};
    final fresh = <({AchProgress ach, AchTier tier})>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final a in list) {
      for (var i = 0; i < a.tierReached; i++) {
        final key = tierKey(a.def.id, i);
        if (next.containsKey(key)) continue;
        next[key] = now;
        fresh.add((ach: a, tier: kTierOrder[i]));
      }
    }
    if (fresh.isEmpty && state.seeded) return const [];

    final wasSeeded = state.seeded;
    state = UnlockedAchievements(at: next, seeded: true);
    _save();
    return wasSeeded ? fresh : const [];
  }

  /// Сброс вместе со статистикой.
  void clear() {
    state = const UnlockedAchievements();
    _save();
  }
}
