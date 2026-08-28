/// Строки разделов настроек, общие для «Системы» и «Аудио».
///
/// В остальных разделах такие же строки живут приватными классами внутри своих
/// экранов (`appearance_screen`, `player_screen`). Здесь их два потребителя,
/// поэтому вынесены; вид тот же — название, под ним пояснение, справа тумблер
/// либо шеврон.
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';

/// Строка с тумблером. [enabled] `false` — настройка сейчас недоступна
/// (выключен её «родитель»): текст гаснет, тумблер не нажимается.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Значок слева. Без него строка начинается с текста — как в «Интерфейсе».
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SettingsRowShell(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: BloomSwitch(value: value, onChanged: onChanged),
      // Тап по строке делает то же, что тумблер: попасть по нему пальцем
      // труднее, чем по строке во всю ширину.
      onTap: () => onChanged(!value),
    );
  }
}

/// Строка-переход: справа шеврон, вся строка нажимается.
class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.danger = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? icon;

  /// Опасное действие — название и значок красные.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SettingsRowShell(
      icon: icon,
      title: title,
      subtitle: subtitle,
      color: danger ? t.sysFavIco : null,
      trailing: Icon(
        SolarIconsOutline.altArrowRight,
        size: 16,
        color: danger ? t.sysFavIco : t.text2,
      ),
      onTap: onTap,
    );
  }
}

/// Оболочка строки: значок — текст — что-то справа. Своей плёнки нет:
/// связанные строки стоят одной карточкой (`SettingsGroupCard`).
class SettingsRowShell extends StatelessWidget {
  const SettingsRowShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.icon,
    this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final IconData? icon;

  /// Цвет названия и значка; `null` — обычный текст темы.
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          children: [
            if (icon != null) ...[
              SizedBox(
                width: 24,
                child: Icon(icon, size: 20, color: color ?? t.iconFg),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.titleMedium?.copyWith(color: color)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.bodySmall?.copyWith(color: t.text2),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            trailing,
          ],
        ),
      ),
    );
  }
}
