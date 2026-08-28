/// Шторка центра уведомлений — порт десктопной панели `.notif-panel`
/// (`NotifBell.tsx` + `shared/styles/notifications.css`).
///
/// На телефоне это шторка снизу, а не выпадашка из-под кнопки: панель шириной
/// 264 упирается в край экрана, а шторка — наш общий способ показать список
/// поверх (очередь, дизлайки волны, скорость). Всё остальное десктопное:
/// круглый значок вида слева, заголовок со временем справа, тело под ними.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../library/history_format.dart';
import '../notif_store.dart';

void showNotifSheet(BuildContext context) =>
    showBloomModal<void>(context: context, builder: (_) => const _NotifSheet());

class _NotifSheet extends ConsumerWidget {
  const _NotifSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final items = ref.watch(notifCenterProvider);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.radius * 1.7),
        ),
        child: SheetSurface(
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetHandle(),
                _Header(count: items.length),
                if (items.isEmpty)
                  const _Empty()
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _Card(item: items[i]),
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

class _Header extends ConsumerWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l.notifCenterTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          // Убрать всю историю разом. Пустой список чистить нечего — кнопка
          // гаснет (тот же приём, что у дизлайков волны).
          CircleIconButton(
            icon: SolarIconsOutline.trashBinMinimalistic,
            iconSize: 20,
            tooltip: context.l.commonClear,
            onTap: count == 0
                ? null
                : () => ref.read(notifCenterProvider.notifier).clear(),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 30, 24, 46),
    child: Text(
      context.l.notifCenterEmpty,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.bloom.muted),
    ),
  );
}

/// Карточка события — десктопный `.notif-card`.
class _Card extends StatelessWidget {
  const _Card({required this.item});

  final NotifItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final color = notifKindColor(item.kind, t);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
            child: Icon(_glyph(item.kind), size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        notifTitleText(context.l, item.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      historyTime(context, item.ts),
                      style: theme.bodySmall?.copyWith(
                        color: t.text2.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(item.body, style: theme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Значки видов — те же, что в десктопном `KIND_ICON`.
  static IconData _glyph(NotifKind kind) => switch (kind) {
    NotifKind.error => SolarIconsOutline.dangerCircle,
    NotifKind.success => Icons.check_rounded,
    NotifKind.info => SolarIconsOutline.infoCircle,
  };
}

/// Цвета видов — значения из `notifications.css`. Свои, не тостовые: там своя
/// палитра (`search-misc.css`), и совпадать они не обязаны.
Color notifKindColor(NotifKind kind, BloomTokens t) => switch (kind) {
  NotifKind.error => const Color(0xFFFF6B6B),
  NotifKind.success => const Color(0xFF4ADE80),
  NotifKind.info => t.text2,
};
