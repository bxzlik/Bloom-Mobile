/// «История» и «Любимые» на главной — две компактные плашки в ряд.
///
/// Раскладку задал пользователь скриншотом (миниатюра слева, название и
/// счётчик справа); крупные карточки десктопного `QuickGrid` с коллажем во всю
/// площадь на телефоне съедали пол-экрана. Названия разделов и переходы —
/// наши, библиотечные.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/cover_collage.dart';

class QuickCards extends ConsumerWidget {
  const QuickCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final t = context.bloom;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _QuickCard(
              covers: lib.favTracks.map((tr) => tr.cover),
              icon: SolarIconsBold.heart,
              tint: t.sysFavTint,
              iconColor: t.sysFavIco,
              title: context.l.commonFavorites,
              count: lib.favs.length,
              onTap: () => context.go('/library/list/fav'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickCard(
              covers: lib.historyTracks.map((tr) => tr.cover),
              // Значки — те же, что у плиток библиотеки: залитое сердце и
              // КОНТУРНЫЕ часы. Bold-часы здесь превращались в глухой кружок.
              icon: SolarIconsOutline.clockCircle,
              tint: t.sysHistTint,
              iconColor: t.sysHistIco,
              title: context.l.commonHistory,
              count: lib.history.length,
              onTap: () => context.go('/library/list/history'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.covers,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.count,
    required this.onTap,
  });

  final Iterable<String?> covers;
  final IconData icon;

  /// Заливка раздела — та же, что у плиток библиотеки. Здесь она видна только
  /// под миниатюрой: пустой раздел показывает свою иконку на ней.
  final Color tint;
  final Color iconColor;
  final String title;
  final int count;
  final VoidCallback onTap;

  static const double _height = 80;
  static const double _thumb = 56;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final empty = count == 0;

    return GestureDetector(
      onTap: empty ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: empty ? 0.6 : 1,
        child: Container(
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.blockColor,
            border: Border.all(color: t.ovlLine),
            borderRadius: BorderRadius.circular(t.radius),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(t.radius * 0.72),
                child: SizedBox(
                  width: _thumb,
                  height: _thumb,
                  child: CoverCollage(
                    covers: covers,
                    // Обложек нет — на их месте тинт раздела со своим значком,
                    // как у плиток библиотеки.
                    fallback: ColoredBox(
                      color: tint,
                      child: Icon(icon, size: 22, color: iconColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.l.tracksCount(count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
