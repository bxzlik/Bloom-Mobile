/// Настройки «Яндекс.Музыка» — порт десктопной секции `YandexSection.tsx`.
///
/// OAuth device-flow: «Подключить» → открывается страница Яндекс ID и
/// показывается код → идёт поллинг токена. Всё состояние живёт в
/// [ymAuthProvider]; здесь только вид и перевод типизированных причин.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../providers/yandex/ym_auth.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/subpage_header.dart';

class YandexSettingsScreen extends ConsumerStatefulWidget {
  const YandexSettingsScreen({super.key});

  @override
  ConsumerState<YandexSettingsScreen> createState() =>
      _YandexSettingsScreenState();
}

class _YandexSettingsScreenState extends ConsumerState<YandexSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Статус перечитываем при открытии экрана, а поллинг гасим при уходе —
    // как `useEffect` в десктопной секции.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(ymAuthProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    ref.read(ymAuthProvider.notifier).cancelAuth();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final s = ref.watch(ymAuthProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          SubPageHeader(
            title: l.sourceYandex,
            onBack: () => context.go('/settings'),
          ),
          const SizedBox(height: 22),

          // Шапка: логотип, название, статус подключения.
          Row(
            children: [
              const PlatformLogo(MusicSource.yandex, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.sourceYandex, style: theme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      s.checking
                          ? l.ymChecking
                          : s.authed
                          ? l.ymConnected
                          : l.ymNotConnected,
                      style: theme.bodySmall?.copyWith(
                        color: s.authed && !s.checking
                            ? const Color(0xFF1DB954)
                            : t.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (s.authed) ...[
            _PlusBadge(hasPlus: s.hasPlus),
            const SizedBox(height: 16),
            _PillButton(
              label: l.ymLogout,
              onTap: () => ref.read(ymAuthProvider.notifier).logout(),
            ),
          ] else ...[
            Text(l.ymLoginHint, style: theme.bodySmall),
            const SizedBox(height: 14),
            _PillButton(
              label: l.ymConnect,
              accent: true,
              busy: s.connecting && s.userCode == null,
              onTap: s.connecting
                  ? null
                  : () => ref.read(ymAuthProvider.notifier).startAuth(),
            ),
            if (s.userCode case final code?) ...[
              const SizedBox(height: 16),
              _CodeCard(code: code, verifyUrl: s.verifyUrl),
            ],
          ],

          if (s.note case final note?) ...[
            const SizedBox(height: 14),
            Text(
              _noteText(l, note),
              style: theme.bodySmall?.copyWith(
                color: note.kind == YmAuthNoteKind.error
                    ? t.sysFavIco
                    : t.text2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Типизированная причина → фраза. Коды `ym.err.*` приходят из сетевого слоя,
/// незнакомый код показываем как есть — это текст самой площадки.
String _noteText(AppLocalizations l, YmAuthNote note) => switch (note.kind) {
  YmAuthNoteKind.gettingCode => l.ymGettingCode,
  YmAuthNoteKind.waiting => l.ymWaiting,
  YmAuthNoteKind.codeExpired => l.ymCodeExpired,
  YmAuthNoteKind.error => describeYmError(l, note.errorCode ?? ''),
};

/// Ошибка площадки на языке пользователя.
String describeYmError(AppLocalizations l, String code) => switch (code) {
  'ym.err.auth' => l.ymErrAuth,
  'ym.err.noToken' => l.ymNotConnected,
  'ym.err.needPlus' => l.ymErrNeedPlus,
  'ym.err.network' || 'ym.err.badJson' => l.ymErrNetwork,
  _ => code,
};

class _PlusBadge extends StatelessWidget {
  const _PlusBadge({required this.hasPlus});

  final bool? hasPlus;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final body = Theme.of(context).textTheme.bodySmall;
    // Как на десктопе: первая половина фразы выделена, вторая — обычным
    // текстом. Статус неизвестен — одна серая строка.
    return switch (hasPlus) {
      true => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: l.ymPlusActiveA,
              style: body?.copyWith(
                color: const Color(0xFF1DB954),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: ' ${l.ymPlusActiveB}', style: body),
          ],
        ),
      ),
      false => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: l.ymPlusNoneA,
              style: body?.copyWith(
                color: t.text2,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: ' ${l.ymPlusNoneB}', style: body),
          ],
        ),
      ),
      null => Text(l.ymPlusUnknown, style: body),
    };
  }
}

/// Код устройства: крупные цифры (тап — копировать) и повторное открытие
/// страницы подтверждения, если браузер не открылся сам.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.verifyUrl});

  final String code;
  final String? verifyUrl;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final url = verifyUrl ?? 'https://ya.ru/device';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.ovlBg,
        border: Border.all(color: t.ovlLine),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${l.ymCodePromptA} ', style: theme.bodySmall),
                TextSpan(
                  text: url,
                  style: theme.bodySmall?.copyWith(
                    color: t.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' ${l.ymCodePromptB}', style: theme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              showToast(context, l.ymCodeCopied);
            },
            child: Text(
              code,
              style: theme.headlineSmall?.copyWith(
                color: t.accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PillButton(label: l.ymOpenPage, onTap: () => openVerifyPage(url)),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.accent = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return SizedBox(
      height: 46,
      child: Material(
        color: accent ? t.accent : t.pill,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: accent ? t.accentText : t.accent,
                    ),
                  )
                : Text(
                    label,
                    style: theme.titleSmall?.copyWith(
                      color: accent ? t.accentText : null,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
