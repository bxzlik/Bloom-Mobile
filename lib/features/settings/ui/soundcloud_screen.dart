/// Настройки SoundCloud: ручной `client_id` и проверка соединения.
///
/// Раскладка — [PlatformPage]: знак площадки посреди экрана, действия внизу.
/// В покое страница свёрнута (настраивать обычно нечего — ключ подбирается
/// сам), «Настроить» раскрывает карточку с инструкцией, поле ключа и проверку.
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
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../providers/soundcloud/models.dart';
import '../../../providers/soundcloud/soundcloud.dart' as sc;
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';
import 'platform_page.dart';

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

  /// Раскрыт ли блок настройки. В покое страница показывает только знак: свой
  /// ключ нужен редко.
  bool _open = false;
  bool _checking = false;
  ScCheckResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(settingsProvider.notifier).setScClientId(_controller.text);
    setState(() {});
  }

  void _clear() {
    _controller.clear();
    ref.read(settingsProvider.notifier).setScClientId(null);
    setState(() {});
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await sc.checkConnection();
    if (!mounted) return;
    // Авто-подбор сработал, а поле пустое — подставим ключ, чтобы его можно
    // было сохранить (то же, что на ПК).
    if (result.ok && _controller.text.trim().isEmpty) {
      final id = result.clientId;
      if (id != null) _controller.text = id;
    }
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  void _guide() => showPlatformGuide(
    context,
    mark: const BrandMark.platform(MusicSource.soundcloud),
    title: context.l.scGuideTitle,
    steps: [
      context.l.scStep1,
      context.l.scStep2,
      context.l.scStep3,
      context.l.scStep4,
      context.l.scStep5,
    ],
    note: context.l.scHelp,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final saved = ref.watch(settingsProvider).scClientId;

    return PlatformPage(
      mark: const BrandMark.platform(MusicSource.soundcloud),
      onBack: () => context.go('/settings'),
      status: saved == null ? l.scStatusAuto : l.scStatusManual,
      body: _open ? _buildForm(saved) : null,
      actions: [
        PlatformButton(
          label: _open
              ? l.commonHide
              : saved == null
              ? l.scSetup
              : l.scReconfigure,
          onTap: () => setState(() => _open = !_open),
        ),
      ],
    );
  }

  Widget _buildForm(String? saved) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    // Правка в поле ещё не сохранена — левая кнопка предлагает сохранить;
    // иначе она чистит уже сохранённый ключ.
    final changed = _controller.text.trim() != (saved ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformCard(
          mark: const BrandMark.platform(MusicSource.soundcloud),
          title: l.scGuideTitle,
          subtitle: l.scGuideSubtitle,
          onTap: _guide,
        ),
        const Center(child: OrLabel()),
        GlassBox(
          borderRadius: BorderRadius.circular(t.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    cursorColor: t.accent,
                    style: theme.bodyMedium?.copyWith(color: t.text),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      hintText: l.scHint,
                      hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
                    ),
                  ),
                ),
                // «?» внутри поля — как на референсе: инструкция нужна ровно
                // тогда, когда смотришь на пустое поле.
                IconButton(
                  onPressed: _guide,
                  icon: Icon(
                    SolarIconsOutline.questionCircle,
                    size: 20,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: PlatformButton(
                label: changed ? l.commonSave : l.commonClear,
                height: 48,
                onTap: changed
                    ? _save
                    : saved == null && _controller.text.isEmpty
                    ? null
                    : _clear,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PlatformButton(
                label: l.scCheckConnection,
                height: 48,
                busy: _checking,
                onTap: _check,
              ),
            ),
          ],
        ),
        if (_result case final r?) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                r.ok ? SolarIconsBold.checkCircle : SolarIconsBold.closeCircle,
                size: 18,
                color: r.ok ? kPlatformOk : t.sysFavIco,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.ok ? l.scConnectionOk : l.scConnectionFail,
                  style: theme.bodyMedium?.copyWith(color: t.text),
                ),
              ),
            ],
          ),
          if (r.clientId case final id?) ...[
            const SizedBox(height: 6),
            Text('${l.scActiveKey}: $id', style: theme.bodySmall),
          ],
          if (r.error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: theme.bodySmall?.copyWith(color: t.sysFavIco)),
          ],
        ],
      ],
    );
  }
}
