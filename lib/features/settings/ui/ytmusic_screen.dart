/// Настройки «YouTube Music» — порт десктопной секции `YtmSection.tsx`.
///
/// Настраивать нечего: поиск, страницы, импорт по ссылке, воспроизведение и
/// скачивание работают без авторизации. Экран лишь сообщает, что всё готово, —
/// без него строка в настройках вела бы в заглушку «раздел ещё не сделан» и
/// врала бы про рабочую площадку.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/subpage_header.dart';

/// Зелёный «всё в порядке» — тот же, что у подключённого Яндекса.
const Color _ok = Color(0xFF1DB954);

class YtmusicSettingsScreen extends StatelessWidget {
  const YtmusicSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;

    return SubPage(
      title: 'YouTube Music',
      onBack: () => context.go('/settings'),
      children: [
        Row(
          children: [
            const PlatformLogo(MusicSource.ytmusic, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YouTube Music', style: theme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    l.ytmConfigured,
                    style: theme.bodySmall?.copyWith(color: _ok),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.ovlBg,
            border: Border.all(color: t.ovlLine),
            borderRadius: BorderRadius.circular(t.radius),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_rounded, size: 24, color: _ok),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.ytmConfigured,
                      style: theme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.ytmNoAuth,
                      style: theme.bodySmall?.copyWith(color: t.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Text(
          l.ytmHelp,
          style: theme.bodySmall?.copyWith(color: t.text2, height: 1.6),
        ),
      ],
    );
  }
}
