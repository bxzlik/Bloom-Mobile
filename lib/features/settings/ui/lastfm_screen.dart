/// Настройки Last.fm — порт десктопной секции `LastfmSection.tsx`.
///
/// Раскладка — [PlatformPage], как у площадок: знак посреди экрана, статус под
/// ним, действия внизу. Инструкция с ПК (попап «?») живёт в шторке, поля
/// ключей приложения прячутся под кнопку «Ключи API» — на телефоне их вводят
/// один раз, а на виду они только мешают.
///
/// Вход двухшаговый, как на ПК: `auth.getToken` → браузер → `auth.getSession`.
/// Отличие мобилки: возврат из браузера ловится сам
/// ([WidgetsBindingObserver.didChangeAppLifecycleState]) и молча пробует
/// добрать сессию — кнопка «Готово» остаётся запасной для случая, когда тихая
/// проверка не прошла.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../lastfm/lastfm_store.dart';
import 'platform_page.dart';

const BrandMark _mark = BrandMark.service(Service.lastfm);

class LastfmSettingsScreen extends ConsumerStatefulWidget {
  const LastfmSettingsScreen({super.key});

  @override
  ConsumerState<LastfmSettingsScreen> createState() =>
      _LastfmSettingsScreenState();
}

class _LastfmSettingsScreenState extends ConsumerState<LastfmSettingsScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _key = TextEditingController(
    text: ref.read(lastfmProvider).apiKey,
  );
  late final TextEditingController _secret = TextEditingController(
    text: ref.read(lastfmProvider).apiSecret,
  );

  /// Раскрыты ли поля ключей. Без сохранённых ключей войти всё равно нельзя —
  /// тогда открываем сразу.
  late bool _keysOpen = !ref.read(lastfmProvider).hasKeys;

  bool _keyVisible = false;
  bool _secretVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _key.dispose();
    _secret.dispose();
    super.dispose();
  }

  /// Вернулись из браузера — тихо пробуем добрать сессию. Токен живёт в
  /// контроллере, поэтому нажимать «Готово» руками обычно не приходится.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!ref.read(lastfmProvider).oauthPending) return;
    _finish(silent: true);
  }

  Future<void> _finish({bool silent = false}) async {
    final ok = await ref
        .read(lastfmProvider.notifier)
        .finishOAuth(silent: silent);
    if (!ok || !mounted) return;
    setState(() => _keysOpen = false);
    showToast(
      context,
      context.l.lfmToastConnected(ref.read(lastfmProvider).user),
      kind: ToastKind.success,
    );
  }

  void _saveKeys() {
    final ok = ref
        .read(lastfmProvider.notifier)
        .saveKeys(_key.text, _secret.text);
    if (!ok) return;
    showToast(context, context.l.lfmToastKeysSaved);
    setState(() {});
  }

  void _logout() {
    ref.read(lastfmProvider.notifier).logout();
    showToast(context, context.l.lfmToastDisconnected);
    setState(() => _keysOpen = false);
  }

  void _guide() => showPlatformGuide(
    context,
    mark: _mark,
    title: context.l.lfmGuideTitle,
    steps: [
      context.l.lfmStep1,
      context.l.lfmStep2,
      context.l.lfmStep3,
      context.l.lfmStep4,
    ],
    note: context.l.lfmGuideNote,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final s = ref.watch(lastfmProvider);

    return PlatformPage(
      mark: _mark,
      onBack: () => context.go('/settings'),
      status: s.connected ? l.lfmConnectedAs(s.user) : l.lfmNotConnected,
      statusColor: s.connected ? kPlatformOk : null,
      body: s.connected ? _connectedBody(s) : _loginBody(s),
      actions: [
        if (s.connected)
          PlatformButton(label: l.lfmLogout, onTap: _logout)
        else ...[
          // Пока доступ подтверждают в браузере, главной кнопкой становится
          // «Готово»: вход уже начат, повторно открывать браузер незачем.
          if (s.oauthPending)
            PlatformButton(
              label: l.lfmDone,
              busy: s.busy,
              onTap: () => _finish(),
            ),
          PlatformButton(
            label: l.lfmLogin,
            busy: s.busy && !s.oauthPending,
            onTap: () => ref.read(lastfmProvider.notifier).startOAuth(),
          ),
          PlatformButton(
            label: _keysOpen ? l.commonHide : l.lfmKeys,
            onTap: () => setState(() => _keysOpen = !_keysOpen),
          ),
        ],
      ],
    );
  }

  /// Подключено: два тумблера, как в десктопной карточке.
  Widget _connectedBody(LastfmState s) {
    final l = context.l;
    final controller = ref.read(lastfmProvider.notifier);
    return SettingsGroupCard(
      dividerInset: 16,
      rows: [
        _ToggleRow(
          title: l.lfmScrobble,
          subtitle: l.lfmScrobbleSub,
          value: s.scrobbleEnabled,
          onChanged: controller.setScrobble,
        ),
        // Название статуса Last.fm не переводим — это его собственный термин,
        // на ПК он тоже английский.
        _ToggleRow(
          title: 'Now Playing',
          subtitle: l.lfmNowPlayingSub,
          value: s.nowPlayingEnabled,
          onChanged: controller.setNowPlaying,
        ),
      ],
    );
  }

  /// Не подключено: инструкция, поля ключей и подсказка о ходе входа.
  Widget _loginBody(LastfmState s) {
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformCard(
          mark: _mark,
          title: l.lfmGuideTitle,
          subtitle: l.lfmGuideSubtitle,
          onTap: _guide,
        ),
        if (_keysOpen) ...[
          const SizedBox(height: 10),
          _KeyField(
            controller: _key,
            hint: 'API Key',
            obscure: !_keyVisible,
            onToggle: () => setState(() => _keyVisible = !_keyVisible),
          ),
          const SizedBox(height: 8),
          _KeyField(
            controller: _secret,
            hint: 'API Secret',
            obscure: !_secretVisible,
            onToggle: () => setState(() => _secretVisible = !_secretVisible),
          ),
          const SizedBox(height: 10),
          PlatformButton(label: l.lfmSaveKeys, height: 48, onTap: _saveKeys),
        ],
        if (s.note case final note?) ...[
          const SizedBox(height: 14),
          Builder(
            builder: (context) => Text(
              _noteText(l, note),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: note.kind == LfmNoteKind.error
                    ? context.bloom.sysFavIco
                    : context.bloom.text2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Типизированная причина → фраза. Тексты площадки (`message`) показываем как
/// есть — перевести их всё равно нечем.
String _noteText(AppLocalizations l, LfmNote note) => switch (note.kind) {
  LfmNoteKind.gettingToken => l.lfmGettingToken,
  LfmNoteKind.confirmAccess => l.lfmConfirmAccess,
  LfmNoteKind.checking => l.lfmChecking,
  LfmNoteKind.notConfirmed => l.lfmNotConfirmed,
  LfmNoteKind.loginFirst => l.lfmLoginFirst,
  LfmNoteKind.needKeys => l.lfmNeedKeys,
  LfmNoteKind.networkError => l.lfmNetworkError,
  LfmNoteKind.error => l.lfmError(note.message ?? ''),
};

/// Строка с тумблером внутри общей карточки настроек.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: theme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 14),
          BloomSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Поле ключа: моноширинный текст (ключи сверяют посимвольно) и «глаз».
class _KeyField extends StatelessWidget {
  const _KeyField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return GlassBox(
      borderRadius: BorderRadius.circular(t.radius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: t.accent,
                style: theme.bodyMedium?.copyWith(
                  color: t.text,
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Courier'],
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  hintText: hint,
                  hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
                ),
              ),
            ),
            IconButton(
              onPressed: onToggle,
              icon: Icon(
                obscure ? SolarIconsOutline.eyeClosed : SolarIconsOutline.eye,
                size: 20,
                color: t.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
