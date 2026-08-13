/// Вкладка «Достижения» — порт десктопной `AchievementsSection`.
///
/// Значения считаются на лету из той же статистики; отсюда ничего не пишется,
/// кроме дат разблокировки (их ведёт [AchievementsController]). Карточка
/// показывает медаль в цвете взятого тира, три пипса уровней, полосу прогресса
/// и «сколько сейчас / сколько до следующего».
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../achievements.dart';
import '../stats.dart';

class AchievementsSection extends ConsumerWidget {
  const AchievementsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final list = ref.watch(achievementsProvider);
    final unlocked = ref.watch(unlockedAchievementsProvider);

    final done = list.fold(0, (n, a) => n + a.tierReached);
    final total = list.length * kTierOrder.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(SolarIconsOutline.medalStar, size: 16, color: t.iconFg),
            const SizedBox(width: 8),
            Text('Достижения', style: theme.titleSmall),
            const Spacer(),
            Text(
              '$done/$total',
              style: theme.titleSmall?.copyWith(color: t.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final a in list) ...[
          _AchCard(
            progress: a,
            // Дата последнего взятого тира — она и подписывается.
            unlockedAt: unlocked.at[tierKey(a.def.id, a.tierReached - 1)],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AchCard extends StatelessWidget {
  const _AchCard({required this.progress, this.unlockedAt});

  final AchProgress progress;
  final int? unlockedAt;

  static const List<String> _months = [
    'янв',
    'фев',
    'мар',
    'апр',
    'мая',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];

  String _fmt(int value) => progress.def.unit == AchUnit.time
      ? fmtDurLong(value)
      : '$value';

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final a = progress;
    final medal = a.tier == null ? t.muted : tierColor(a.tier!);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.pill,
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Медаль гаснет, пока не взят ни один тир, — то же, что класс `on`
          // на десктопе.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: medal.withValues(alpha: a.unlocked ? 0.16 : 0.06),
              borderRadius: BorderRadius.circular(t.radius * 0.7),
            ),
            child: Icon(
              a.def.icon,
              size: 22,
              color: a.unlocked ? medal : t.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.def.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleSmall,
                      ),
                    ),
                    for (var i = 0; i < kTierOrder.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < a.tierReached
                                ? tierColor(kTierOrder[i])
                                : t.track,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  a.def.description,
                  style: theme.bodySmall?.copyWith(color: t.muted),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: a.ratio,
                    minHeight: 5,
                    backgroundColor: t.track,
                    valueColor: AlwaysStoppedAnimation(
                      a.unlocked ? medal : t.text.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      a.maxed
                          ? 'Максимум'
                          : '${_fmt(a.value)} / ${_fmt(a.nextTarget!)}',
                      style: theme.bodySmall?.copyWith(
                        color: a.maxed ? tierColor(AchTier.gold) : t.text2,
                      ),
                    ),
                    const Spacer(),
                    if (unlockedAt case final at?)
                      Text(
                        'получено ${_date(at)}',
                        style: theme.bodySmall?.copyWith(
                          color: t.muted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }
}
