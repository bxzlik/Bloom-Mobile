/// Настройки SoundCloud: ручной `client_id` и проверка соединения.
///
/// Обе операции портированы вместе с провайдером: `setManualClientId` сбрасывает
/// авто-кеш, `checkConnection` сначала сбрасывает его же и потом делает тестовый
/// поиск — то есть показывает, каким ключом всё реально работает сейчас.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/settings_store.dart';
import '../../../providers/soundcloud/models.dart';
import '../../../providers/soundcloud/soundcloud.dart' as sc;
import '../../../shared/ui/subpage_header.dart';

class SoundCloudSettingsScreen extends ConsumerStatefulWidget {
  const SoundCloudSettingsScreen({super.key});

  @override
  ConsumerState<SoundCloudSettingsScreen> createState() =>
      _SoundCloudSettingsScreenState();
}

class _SoundCloudSettingsScreenState
    extends ConsumerState<SoundCloudSettingsScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(settingsProvider).scClientId ?? '',
  );
  bool _checking = false;
  ScCheckResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await sc.checkConnection();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          SubPageHeader(
            title: 'SoundCloud',
            onBack: () => context.go('/settings'),
          ),
          const SizedBox(height: 22),
          Text('CLIENT_ID', style: theme.labelSmall),
          const SizedBox(height: 8),
          Text(
            'Обычно не нужен: ключ подбирается сам — скрейпом сайта, а если не '
            'вышло, перебором известных. Своё значение имеет смысл вбить, если '
            'SoundCloud перестал отвечать.',
            style: theme.bodySmall,
          ),
          const SizedBox(height: 12),
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: t.pill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    cursorColor: t.accent,
                    style: theme.titleSmall,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Автоматически',
                      hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
                    ),
                    onSubmitted: (v) =>
                        ref.read(settingsProvider.notifier).setScClientId(v),
                  ),
                ),
                if (settings.scClientId != null)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      ref.read(settingsProvider.notifier).setScClientId(null);
                    },
                    child: Icon(
                      SolarIconsOutline.closeCircle,
                      size: 18,
                      color: t.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .setScClientId(_controller.text),
              child: Text('Сохранить', style: TextStyle(color: t.accent)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: Material(
              color: t.pill,
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _checking ? null : _check,
                child: Center(
                  child: _checking
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: t.accent,
                          ),
                        )
                      : Text('Проверить соединение', style: theme.titleSmall),
                ),
              ),
            ),
          ),
          if (_result case final r?) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.ovlBg,
                border: Border.all(color: t.ovlLine),
                borderRadius: BorderRadius.circular(t.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        r.ok
                            ? SolarIconsBold.checkCircle
                            : SolarIconsBold.closeCircle,
                        size: 18,
                        color: r.ok ? t.sysAllIco : t.sysFavIco,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.ok ? 'Соединение работает' : 'Не отвечает',
                        style: theme.titleSmall,
                      ),
                    ],
                  ),
                  if (r.clientId != null) ...[
                    const SizedBox(height: 8),
                    Text('Активный ключ', style: theme.bodySmall),
                    const SizedBox(height: 2),
                    SelectableText(
                      r.clientId!,
                      style: theme.bodyMedium?.copyWith(color: t.text),
                    ),
                  ],
                  if (r.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      r.error!,
                      style: theme.bodySmall?.copyWith(color: t.sysFavIco),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
