/// Настройка свайпов — четыре места, у каждого своя пара действий.
///
/// Раскладка по скриншотам пользователя: капсовый заголовок места, под ним
/// плашка-превью (значок действия слева — значок самого места — значок действия
/// справа) и карточка с двумя строками «Свайп влево» / «Свайп вправо».
/// Выбор действия — нижняя шторка с одинаковым для всех мест списком.
///
/// Вид, как всегда, наш: карточки `pill`, значки Solar, галочка у выбранного —
/// та же, что в шторке сортировки.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/ui/track_swipes.dart';
import '../swipe_store.dart';

class SwipesScreen extends ConsumerWidget {
  const SwipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(swipeProvider);

    return SubPage(
      title: context.l.setSwipes,
      onBack: () => context.go('/settings'),
      children: [
        for (final zone in SwipeZone.values) ...[
          if (zone != SwipeZone.values.first) const SizedBox(height: 26),
          SettingsCaption(swipeZoneLabel(context.l, zone).toUpperCase()),
          const SizedBox(height: 10),
          _Preview(zone: zone, pair: settings.of(zone)),
          const SizedBox(height: 12),
          _SidesCard(zone: zone, pair: settings.of(zone)),
        ],
      ],
    );
  }
}

/// Значок самого места — центр плашки-превью.
///
/// У библиотеки он не из шрифта Solar, а тот же SVG, что у её вкладки в
/// таб-баре (глиф `library` в шрифте залит сплошным ящиком, см. `shell.dart`).
Widget _zoneIcon(BuildContext context, SwipeZone zone) {
  final color = context.bloom.muted;
  if (zone == SwipeZone.library) {
    return SvgIcon('assets/icons/library-linear.svg', size: 20, color: color);
  }
  return Icon(
    switch (zone) {
      SwipeZone.queue => SolarIconsOutline.playlistMinimalistic,
      SwipeZone.mini => SolarIconsOutline.musicNote,
      SwipeZone.player => SolarIconsOutline.play,
      SwipeZone.library => SolarIconsOutline.playlistMinimalistic,
    },
    size: 18,
    color: color,
  );
}

/// Плашка-превью: значки стоят со стороны, откуда приходит движение — слева
/// действие свайпа вправо, справа — свайпа влево, посередине само место.
/// Значки тихие: это не кнопки, а картинка.
class _Preview extends StatelessWidget {
  const _Preview({required this.zone, required this.pair});

  final SwipeZone zone;
  final SwipePair pair;

  @override
  Widget build(BuildContext context) {
    return GlassBox(
      child: Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            _PreviewIcon(icon: swipeActionIcon(pair.right)),
            const Spacer(),
            _zoneIcon(context, zone),
            const Spacer(),
            _PreviewIcon(icon: swipeActionIcon(pair.left)),
          ],
        ),
      ),
    );
  }
}

class _PreviewIcon extends StatelessWidget {
  const _PreviewIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 22, color: context.bloom.muted);
}

/// Две строки места: что делает движение влево и что вправо.
class _SidesCard extends ConsumerWidget {
  const _SidesCard({required this.zone, required this.pair});

  final SwipeZone zone;
  final SwipePair pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsGroupCard(
      // Линия начинается под текстом строки: 16 поля + 20 значка + 14 зазора.
      dividerInset: 50,
      rows: [
        _SideRow(zone: zone, isLeft: true, action: pair.left),
        _SideRow(zone: zone, isLeft: false, action: pair.right),
      ],
    );
  }
}

class _SideRow extends ConsumerWidget {
  const _SideRow({
    required this.zone,
    required this.isLeft,
    required this.action,
  });

  final SwipeZone zone;
  final bool isLeft;
  final SwipeAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => _pickAction(context, ref, zone, isLeft, action),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Row(
          children: [
            Icon(
              isLeft
                  ? SolarIconsOutline.arrowLeft
                  : SolarIconsOutline.arrowRight,
              size: 20,
              color: t.muted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLeft ? context.l.swLeft : context.l.swRight,
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  // Ярче общего `bodySmall` — как выбранное в строках «Плеера».
                  Text(
                    swipeActionLabel(context.l, action),
                    style: theme.bodySmall?.copyWith(color: t.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Icon(swipeActionIcon(action), size: 20, color: t.muted),
          ],
        ),
      ),
    );
  }
}

/// Список действий одной шторкой: каждое действие — своим крупным блоком, как в
/// референсе. Шапки нет намеренно: строка, из которой сюда пришли, осталась
/// видна над шторкой, и подписывать выбор второй раз незачем.
Future<void> _pickAction(
  BuildContext context,
  WidgetRef ref,
  SwipeZone zone,
  bool isLeft,
  SwipeAction current,
) {
  final controller = ref.read(swipeProvider.notifier);
  return showBloomSheetChild<void>(
    context: context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in SwipeAction.values)
          _ActionTile(
            action: action,
            selected: action == current,
            onTap: () =>
                controller.setAction(zone, isLeft: isLeft, action: action),
          ),
      ],
    ),
  );
}

/// Строка выбора действия. Своя, а не [SheetAction]: в референсе такие строки
/// заметно крупнее обычных пунктов шторки, у выбранной обводка и кружок под
/// значком.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.selected,
    required this.onTap,
  });

  final SwipeAction action;
  final bool selected;
  final VoidCallback onTap;

  /// Высота строки — по референсу: между пунктами должно быть видно фон
  /// шторки, а сами пункты читаются кнопками, а не списком.
  static const double _height = 72;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Material(
        // Та же заливка, что у блоков шторки ([SheetPanel]).
        color: sheetPanelColor(context),
        borderRadius: BorderRadius.circular(t.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
          child: Container(
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius),
              border: Border.all(
                color: selected ? t.ovlLine2 : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _TileIcon(action: action, selected: selected),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    swipeActionLabel(context.l, action),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (selected)
                  Icon(SolarIconsBold.checkCircle, size: 20, color: t.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок действия: у выбранного — в кружке, как в референсе.
class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.action, required this.selected});

  final SwipeAction action;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final icon = Icon(swipeActionIcon(action), size: 22, color: t.text);
    if (!selected) return SizedBox(width: 38, child: Center(child: icon));
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: icon,
    );
  }
}
