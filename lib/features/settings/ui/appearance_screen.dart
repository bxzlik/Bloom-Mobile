/// Внешний вид: тема, акцент, скругления.
///
/// Тема — ровно три цвета пресета; акцент и радиус живут отдельно и при смене
/// темы НЕ сбрасываются (то же правило, что в десктопном `themeStore.ts`).
/// Превью пресета считается теми же формулами, что и сама тема, поэтому кружки
/// в списке не могут разойтись с тем, что применится.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/settings_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/subpage_header.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          SubPageHeader(
            title: 'Интерфейс',
            onBack: () => context.go('/settings'),
          ),
          const SizedBox(height: 22),
          Text('ТЕМА', style: theme.labelSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final preset in kThemePresets)
                _PresetCard(
                  preset: preset,
                  active: preset.id == settings.themeId,
                  onTap: () => controller.setTheme(preset.id),
                ),
            ],
          ),
          const SizedBox(height: 26),
          // Подпись — в заголовке, а не под первым кружком: иначе он выше
          // остальных и ряд разъезжается.
          Text('АКЦЕНТ · ПЕРВЫЙ БЕРЁТСЯ ИЗ ТЕМЫ', style: theme.labelSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AccentDot(
                color: settings.preset.accent,
                active: settings.accent == null,
                onTap: () => controller.setAccent(null),
              ),
              for (final color in kAccentSwatches)
                _AccentDot(
                  color: color,
                  active: settings.accent?.toARGB32() == color.toARGB32(),
                  onTap: () => controller.setAccent(color),
                ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Text('СКРУГЛЕНИЯ', style: theme.labelSmall),
              const Spacer(),
              Text('${settings.radius.round()} px', style: theme.bodySmall),
            ],
          ),
          Slider(
            value: settings.radius,
            min: 0,
            max: 28,
            divisions: 28,
            onChanged: controller.setRadius,
          ),
          const SizedBox(height: 8),
          // Живой пример: по нему видно и радиус, и акцент разом.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.pill,
              borderRadius: BorderRadius.circular(t.radius),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(t.radius * 0.72),
                  ),
                  child: Icon(
                    SolarIconsBold.play,
                    size: 20,
                    color: t.accentText,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Так выглядит блок', style: theme.titleSmall),
                      const SizedBox(height: 2),
                      Text('и второстепенный текст', style: theme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text('БЕЙДЖИ', style: theme.labelSmall),
          const SizedBox(height: 10),
          // Тексты — из десктопного `dict.ts` (`settings.interface.accentBadges`).
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: t.pill,
              borderRadius: BorderRadius.circular(t.radius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Бейджи в цвете акцента', style: theme.titleSmall),
                      const SizedBox(height: 3),
                      Text(
                        'По умолчанию бейджи источников в своих фирменных '
                        'цветах; включи — красить в акцент',
                        style: theme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                BloomSwitch(
                  value: settings.accentBadges,
                  onChanged: controller.setAccentBadges,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.active,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    // Превью считаем теми же формулами, что и сама тема.
    final preview = preset.tokens();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: preview.bg,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(
            color: active ? t.accent : preview.border,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Swatch(preview.pill),
                const SizedBox(width: 6),
                _Swatch(preview.accent),
                const Spacer(),
                if (active)
                  Icon(SolarIconsBold.checkCircle, size: 16, color: t.accent),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              preset.name,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: preview.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.active,
    required this.onTap,
  });

  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? t.text : t.border,
            width: active ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}
