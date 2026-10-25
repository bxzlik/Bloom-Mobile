/// Уровень на профиле — порт `LevelBadge` и `LevelModal` ПК.
///
/// [LevelBadge] — щит в акценте с номером перед ником; тап открывает шторку:
/// щит, «Уровень N», строка о нём, полоса XP со щитом следующего уровня на
/// конце, сколько до него и из чего XP набираются — с тем, сколько дал каждый
/// источник. Наград нет.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart' show SvgIcon;
import '../../../shared/ui/bloom_sheet.dart';
import '../level.dart';

Future<void> showLevelSheet(BuildContext context) =>
    showBloomSheetChild<void>(context: context, child: const LevelSheet());

/// Щит с номером. Меняется только число; длинным числам — шрифт мельче, щит
/// не растёт.
class LevelBadge extends ConsumerWidget {
  const LevelBadge({super.key, this.size = 28, this.level, this.onTap});

  final double size;

  /// Свой номер — щит следующего уровня на полосе; `null` — текущий.
  final int? level;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final n = level ?? ref.watch(levelProvider.select((l) => l.level));
    final digits = '$n'.length;
    final fs = size * (digits < 2 ? 0.42 : (digits < 3 ? 0.36 : 0.29));
    final badge = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Настоящий Solar-SVG, как на ПК: глиф `shield` из шрифта пакета
          // нарисован с перекрестьем, и цифра на нём не читается.
          SvgIcon('assets/icons/shield-bold.svg', size: size, color: t.accent),
          // Щит тяжелее сверху: число чуть выше середины.
          Transform.translate(
            offset: Offset(0, -size * 0.03),
            child: Text(
              '$n',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: t.accentText,
                fontSize: fs.roundToDouble(),
                height: 1,
                letterSpacing: -0.02 * fs,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return badge;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: badge,
    );
  }
}

class LevelSheet extends ConsumerWidget {
  const LevelSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final lv = ref.watch(levelProvider);
    final into = lv.xp - lv.from;
    final span = lv.to - lv.from;
    final rest = span - into;
    final fmt = NumberFormat.decimalPattern(
      Localizations.localeOf(context).languageCode,
    ).format;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Center(child: LevelBadge(size: 56)),
        const SizedBox(height: 14),
        Text(
          l.levelTitle(lv.level),
          textAlign: TextAlign.center,
          style: theme.titleLarge,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            l.levelDesc,
            textAlign: TextAlign.center,
            style: theme.bodyMedium?.copyWith(color: t.text2, height: 1.35),
          ),
        ),
        const SizedBox(height: 22),
        // Полоса: сколько пройдено в этом уровне, щит следующего на конце.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: sheetPanelColor(context),
              borderRadius: BorderRadius.circular(t.radius * 0.8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (into / span).clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.text.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(t.radius * 0.8),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.levelXp(fmt(into), fmt(span)),
                          style: theme.titleSmall,
                        ),
                      ),
                      LevelBadge(size: 24, level: lv.level + 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            '${l.levelToNext(lv.level + 1, fmt(rest))} · '
            '${l.levelTracks((rest / kXpPerPlay).ceil())}',
            style: theme.bodySmall?.copyWith(color: t.muted),
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Text(
            l.levelHow.toUpperCase(),
            style: theme.labelSmall?.copyWith(
              color: t.text2,
              letterSpacing: 1.2,
            ),
          ),
        ),
        _Source(
          icon: SolarIconsOutline.headphonesRound,
          title: l.levelPlays,
          sub: l.levelPlaysSub(kXpPerPlay),
          xp: fmt(lv.plays),
        ),
        _Source(
          icon: SolarIconsOutline.calendar,
          title: l.levelDays,
          sub: l.levelDaysSub(kXpPerDay),
          xp: fmt(lv.days),
        ),
        _Source(
          icon: SolarIconsOutline.medalStar,
          title: l.levelAch,
          sub: l.levelAchSub(kTierXp[0], kTierXp[1], kTierXp[2]),
          xp: fmt(lv.ach),
        ),
        if (lv.banked > 0)
          _Source(
            icon: SolarIconsOutline.chart,
            title: l.levelBanked,
            sub: l.levelBankedSub,
            xp: fmt(lv.banked),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Material(
            color: sheetPanelColor(context),
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(
                  l.levelOk,
                  textAlign: TextAlign.center,
                  style: theme.titleSmall,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Один источник XP: значок, что это и сколько платит, сколько дал.
class _Source extends StatelessWidget {
  const _Source({
    required this.icon,
    required this.title,
    required this.sub,
    required this.xp,
  });

  final IconData icon;
  final String title;
  final String sub;
  final String xp;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.iconFg),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('$xp XP', style: theme.titleSmall?.copyWith(color: t.text2)),
          ],
        ),
      ),
    );
  }
}
