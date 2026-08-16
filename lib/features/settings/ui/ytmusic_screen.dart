/// Настройки «YouTube Music» — порт десктопной секции `YtmSection.tsx`.
///
/// Настраивать нечего: поиск, страницы, импорт по ссылке, воспроизведение и
/// скачивание работают без авторизации. Экран лишь сообщает, что всё готово, —
/// без него строка в настройках вела бы в заглушку «раздел ещё не сделан» и
/// врала бы про рабочую площадку. Что именно работает без входа — в шторке под
/// карточкой, как гайды остальных площадок.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import 'platform_page.dart';

class YtmusicSettingsScreen extends StatelessWidget {
  const YtmusicSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return PlatformPage(
      source: MusicSource.ytmusic,
      onBack: () => context.go('/settings'),
      status: '${l.ytmConfigured} — ${l.ytmNoAuth}',
      statusColor: kPlatformOk,
      body: PlatformCard(
        source: MusicSource.ytmusic,
        title: l.ytmGuideTitle,
        subtitle: l.ytmGuideSubtitle,
        onTap: () => showPlatformGuide(
          context,
          source: MusicSource.ytmusic,
          title: l.ytmGuideTitle,
          steps: [l.ytmStep1, l.ytmStep2, l.ytmStep3],
          note: l.ytmHelp,
        ),
      ),
    );
  }
}
