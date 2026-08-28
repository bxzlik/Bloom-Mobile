/// Настройки → «Аудио».
///
/// С десктопной секции `AudioSection.tsx` пока не перенесено ничего: кроссфейд
/// и нормализация громкости живут там в WebAudio-графе, которого у нас нет, а
/// «Устройство вывода» на телефоне выбирает сама система (наушники, колонка,
/// bluetooth) — экрана для этого приложению не положено.
///
/// Здесь — «Запуск»: что делать с прошлой сессией, когда приложение открыли
/// заново. Десктопная `settings.system.autoplay` живёт на ПК в «Системе», но на
/// телефоне пользователь выбрал ей место тут, рядом со звуком; вторая строка —
/// «Восстановление очереди» — мобильная и новая (на ПК её ещё нет).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../shared/ui/subpage_header.dart';
import 'settings_rows.dart';

class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return SubPage(
      title: l.setAudio,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.sysStartup.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsToggleRow(
              icon: SolarIconsOutline.playlistMinimalistic,
              title: l.audRestoreTitle,
              subtitle: l.audRestoreSub,
              value: settings.restoreQueue,
              onChanged: controller.setRestoreQueue,
            ),
            // Автовоспроизведение включает восстановление само (см.
            // `SettingsController.setAutoplay`): играть, ничего не восстановив,
            // всё равно нечего.
            SettingsToggleRow(
              icon: SolarIconsOutline.play,
              title: l.audAutoplayTitle,
              subtitle: l.audAutoplaySub,
              value: settings.autoplay,
              onChanged: controller.setAutoplay,
            ),
          ],
        ),
      ],
    );
  }
}
