/// Колокольчик уведомлений в шапке главной — порт десктопного `<NotifBell/>`
/// из тайтлбара вместе с бейджем непрочитанных (`.notif-badge`).
///
/// Открытие списка помечает всё прочитанным, как на ПК; делаем это в самом
/// обработчике тапа, а не внутри шторки: правка состояния из `initState`
/// пришлась бы ровно на фазу построения кадра.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../notif_store.dart';
import 'notif_sheet.dart';

class NotifBell extends ConsumerWidget {
  const NotifBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notifUnreadProvider);

    return Stack(
      // Бейдж сидит на самой кромке кнопки и краями выходит наружу — без этого
      // его срезало бы границей стека.
      clipBehavior: Clip.none,
      children: [
        CircleIconButton(
          icon: SolarIconsOutline.bell,
          tooltip: context.l.notifCenterTitle,
          onTap: () {
            ref.read(notifCenterProvider.notifier).markAllRead();
            showNotifSheet(context);
          },
        ),
        if (unread > 0)
          Positioned(top: 1, right: 1, child: _Badge(count: unread)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.accent,
          borderRadius: BorderRadius.circular(9),
          // Кольцо цветом фона — десктопный `box-shadow: 0 0 0 1px var(--bg)`:
          // иначе бейдж сливается с кнопкой, на которой лежит.
          border: Border.all(color: t.bg, width: 1.5),
        ),
        child: Text(
          count > 9 ? '9+' : '$count',
          style: bloomText(
            size: 10,
            weight: 800,
            color: t.accentText,
            height: 1,
          ),
        ),
      ),
    );
  }
}
