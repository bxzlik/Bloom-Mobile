/// «История» и «Любимые» на главной — две компактные плашки в ряд.
///
/// Раскладку задал пользователь скриншотом (стопка обложек слева, название и
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
import '../../../core/store/history_store.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/glass.dart';
import 'cover_fan.dart';

class QuickCards extends ConsumerWidget {
  const QuickCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final history = ref.watch(historyProvider);
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
              covers: history.map((item) => item.track.cover),
              // Значки — те же, что у плиток библиотеки: залитое сердце и
              // КОНТУРНЫЕ часы. Bold-часы здесь превращались в глухой кружок.
              icon: SolarIconsOutline.clockCircle,
              tint: t.sysHistTint,
              iconColor: t.sysHistIco,
              title: context.l.commonHistory,
              // Лимита в 200 больше нет — число снова что-то значит.
              count: history.length,
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

  /// Заливка раздела — та же, что у плиток библиотеки. Видна только у
  /// раздела без обложек: на ней его значок.
  final Color tint;
  final Color iconColor;
  final String title;

  /// Сколько треков в разделе. Пустой раздел карточка гасит и не открывает.
  final int count;
  final VoidCallback onTap;

  static const double _height = 64;

  /// Стопка: место под неё, передняя и задние обложки, вынос задних. Задние
  /// лишь выглядывают из-за передней и не вылезают из своего места.
  static const double _fanWidth = 66;
  static const double _front = 42;
  static const double _back = 36;
  static const double _shift = 11;

  /// Яркость задних обложек. У «Вся подборка» 0.55 — на мелкой стопке так
  /// темно, что задних почти не видно.
  static const double _backDim = 0.8;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final empty = count == 0;
    // Три последних трека раздела со своей обложкой: верхняя — самый свежий.
    final picked = covers.whereType<String>().take(3).toList();

    return GestureDetector(
      onTap: empty ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: empty ? 0.6 : 1,
        child: GlassBox(
          color: t.blockColor,
          borderSide: BorderSide(color: t.ovlLine),
          child: Container(
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                picked.isEmpty
                    // Обложек нет — тинт раздела со своим значком, как у
                    // плиток библиотеки.
                    ? SizedBox(
                        width: _fanWidth,
                        child: Center(
                          child: Container(
                            width: _front,
                            height: _front,
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(tint, t.blockColor),
                              borderRadius: BorderRadius.circular(
                                t.radius * 0.72,
                              ),
                            ),
                            child: Icon(icon, size: 20, color: iconColor),
                          ),
                        ),
                      )
                    : CoverFan(
                        front: picked.first,
                        left: picked.length > 1 ? picked[1] : null,
                        right: picked.length > 2 ? picked[2] : null,
                        width: _fanWidth,
                        height: _height,
                        frontSize: _front,
                        backSize: _back,
                        shift: _shift,
                        dim: _backDim,
                        shadowScale: 0.35,
                      ),
                const SizedBox(width: 10),
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
      ),
    );
  }
}
