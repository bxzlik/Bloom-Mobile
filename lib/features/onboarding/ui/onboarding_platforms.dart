/// Аккордеон площадок на слайде «Подключи музыку» — порт десктопного
/// `PlatformsBlock.tsx`.
///
/// Флоу у каждой площадки настоящий, а не заглушка, и берётся из тех же
/// сторов, что и разделы настроек: подключённое здесь видно там и наоборот.
///  • SoundCloud — ручной `client_id` (или авто-подбор кнопкой «Проверить»);
///  • Яндекс.Музыка — OAuth device-flow: код, страница подтверждения, поллинг;
///  • YouTube Music — авторизации не требует, строка не раскрывается.
///
/// Раскрыта максимум одна строка — как на ПК: на телефоне развёрнутые формы
/// трёх площадок разом ушли бы далеко за экран.
library;

import 'dart:async' show scheduleMicrotask;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../providers/soundcloud/models.dart';
import '../../../providers/soundcloud/soundcloud.dart' as sc;
import '../../../providers/yandex/ym_auth.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../settings/ui/yandex_screen.dart' show describeYmError;

class OnboardingPlatforms extends ConsumerStatefulWidget {
  const OnboardingPlatforms({super.key});

  @override
  ConsumerState<OnboardingPlatforms> createState() =>
      _OnboardingPlatformsState();
}

class _OnboardingPlatformsState extends ConsumerState<OnboardingPlatforms> {
  MusicSource? _open;

  /// Контроллер держим ссылкой, а не читаем через `ref` в [dispose]: там `ref`
  /// уже мёртв и бросает `Bad state: Cannot use "ref" after the widget was
  /// disposed` (поймал тест ухода с онбординга).
  late final YmAuthController _ymAuth = ref.read(ymAuthProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Статус Яндекса перечитываем при открытии слайда, поллинг гасим при уходе
    // — то же, что делает секция настроек.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ymAuth.refresh();
    });
  }

  @override
  void dispose() {
    // Отмена МЕНЯЕТ состояние провайдера, а элемент в этот момент уже помечен
    // мёртвым и всё ещё числится слушателем: синхронный вызов роняет ассерт
    // `_lifecycleState != defunct` (поймал тест ухода с онбординга). Микрозадача
    // переносит отмену за разбор дерева.
    scheduleMicrotask(_ymAuth.cancelAuth);
    super.dispose();
  }

  void _toggle(MusicSource id) =>
      setState(() => _open = _open == id ? null : id);

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scSaved = ref.watch(settingsProvider).scClientId != null;
    final ym = ref.watch(ymAuthProvider);

    return Column(
      children: [
        _PlatformRow(
          source: MusicSource.soundcloud,
          name: 'SoundCloud',
          connected: scSaved,
          open: _open == MusicSource.soundcloud,
          onToggle: _toggle,
          child: const _ScForm(),
        ),
        const SizedBox(height: 7),
        _PlatformRow(
          source: MusicSource.yandex,
          name: l.sourceYandex,
          connected: ym.authed,
          open: _open == MusicSource.yandex,
          onToggle: _toggle,
          child: const _YmForm(),
        ),
        const SizedBox(height: 7),
        _PlatformRow(
          source: MusicSource.ytmusic,
          name: 'YouTube Music',
          connected: true,
          connectedText: l.ytmConfigured,
        ),
      ],
    );
  }
}

/// Строка аккордеона. Без [onToggle] строка не раскрывается (YouTube Music).
class _PlatformRow extends StatelessWidget {
  const _PlatformRow({
    required this.source,
    required this.name,
    required this.connected,
    this.connectedText,
    this.open = false,
    this.onToggle,
    this.child,
  });

  final MusicSource source;
  final String name;
  final bool connected;
  final String? connectedText;
  final bool open;
  final ValueChanged<MusicSource>? onToggle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final expandable = onToggle != null;

    return GlassBox(
      borderRadius: BorderRadius.circular(t.radius),
      // Раскрытая строка подсвечивается ФИРМЕННЫМ цветом площадки, а не
      // акцентом темы, — как `.ob-plat.open` на ПК.
      borderSide: BorderSide(
        color: open
            ? (platformColor[source] ?? t.accent).withValues(alpha: 0.45)
            : Colors.transparent,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: expandable ? () => onToggle!(source) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
              child: Row(
                children: [
                  // Логотип в кружке своего цвета — тот же приём, что у бейджей
                  // источника в строке трека: без подложки мелкий знак теряется.
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (platformColor[source] ?? t.accent).withValues(
                        alpha: 0.14,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: PlatformLogo(source, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          connected
                              ? (connectedText ?? l.onbPlatConnected)
                              : l.onbPlatNotConnected,
                          style: theme.bodySmall?.copyWith(
                            color: connected
                                ? const Color(0xFF1ED760)
                                : t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (expandable) ...[
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        SolarIconsOutline.altArrowDown,
                        size: 18,
                        color: t.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Раскрытие ростом самой строки — то же, что `grid-rows 0fr → 1fr` на
          // ПК: содержимое собрано всегда, но обрезается по высоте.
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: const Cubic(0.4, 0, 0.2, 1),
            alignment: Alignment.topCenter,
            child: open && child != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ─── SoundCloud: ручной client_id ───────────────────────────────────────────

class _ScForm extends ConsumerStatefulWidget {
  const _ScForm();

  @override
  ConsumerState<_ScForm> createState() => _ScFormState();
}

class _ScFormState extends ConsumerState<_ScForm> {
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

  void _save() =>
      ref.read(settingsProvider.notifier).setScClientId(_controller.text);

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await sc.checkConnection();
    if (!mounted) return;
    // Авто-подбор сработал — подставим ключ в поле, чтобы его можно было
    // сохранить (то же, что на ПК).
    if (result.ok && _controller.text.trim().isEmpty) {
      final id = result.clientId;
      if (id != null) _controller.text = id;
    }
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Поле-пилюля, как в настройках SoundCloud и в поиске по списку.
        Container(
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: TextField(
            controller: _controller,
            cursorColor: t.accent,
            style: theme.bodyMedium?.copyWith(color: t.text),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              isDense: true,
              isCollapsed: true,
              border: InputBorder.none,
              hintText: l.scHint,
              hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SmallButton(
                label: l.commonSave,
                primary: true,
                onTap: _save,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _SmallButton(
                label: l.onbPlatCheck,
                busy: _checking,
                onTap: _checking ? null : _check,
              ),
            ),
          ],
        ),
        if (_result case final r?) ...[
          const SizedBox(height: 8),
          Text(
            r.ok ? l.scConnectionOk : '${l.scConnectionFail} ${r.error ?? ''}',
            style: theme.bodySmall?.copyWith(
              color: r.ok ? const Color(0xFF4CAF50) : t.sysFavIco,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Яндекс.Музыка: device-flow ─────────────────────────────────────────────

class _YmForm extends ConsumerWidget {
  const _YmForm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final s = ref.watch(ymAuthProvider);

    if (s.authed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.ymConnected, style: theme.bodySmall),
          const SizedBox(height: 8),
          _SmallButton(
            label: l.ymLogout,
            onTap: () => ref.read(ymAuthProvider.notifier).logout(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.ymLoginHint, style: theme.bodySmall),
        if (s.userCode case final code?) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(t.radius * 0.55),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l.ymCodePromptA} ${s.verifyUrl ?? 'https://ya.ru/device'} ${l.ymCodePromptB}',
                  style: theme.bodySmall,
                ),
                const SizedBox(height: 5),
                // Тап по коду копирует его — как на экране настроек: набирать
                // цифры руками в чужом браузере неудобно.
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    showToast(context, l.ymCodeCopied);
                  },
                  child: Text(
                    code,
                    style: theme.titleMedium?.copyWith(
                      color: t.accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _SmallButton(
            label: l.ymOpenPage,
            onTap: () => openVerifyPage(s.verifyUrl ?? 'https://ya.ru/device'),
          ),
        ] else ...[
          const SizedBox(height: 8),
          _SmallButton(
            label: l.ymConnect,
            primary: true,
            busy: s.connecting,
            onTap: s.connecting
                ? null
                : () => ref.read(ymAuthProvider.notifier).startAuth(),
          ),
        ],
        if (s.note case final note?) ...[
          const SizedBox(height: 8),
          Text(
            _noteText(l, note),
            style: theme.bodySmall?.copyWith(
              color: note.kind == YmAuthNoteKind.error ? t.sysFavIco : t.muted,
            ),
          ),
        ],
      ],
    );
  }
}

String _noteText(AppLocalizations l, YmAuthNote note) => switch (note.kind) {
  YmAuthNoteKind.gettingCode => l.ymGettingCode,
  YmAuthNoteKind.waiting => l.ymWaiting,
  YmAuthNoteKind.codeExpired => l.ymCodeExpired,
  YmAuthNoteKind.error => describeYmError(l, note.errorCode ?? ''),
};

// ─── Общее ──────────────────────────────────────────────────────────────────

/// Кнопка формы площадки — `.ob-plat-btn`: невысокая, во всю ширину колонки.
class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return SizedBox(
      // 44 — та же высота, что у чипов и круглых кнопок в рядах: ниже палец
      // начинает промахиваться.
      height: kChipHeight,
      child: GlassBox(
        // Залитая акцентом кнопка стеклом не становится: это состояние, а не
        // поверхность темы.
        color: primary ? t.accent : null,
        enabled: !primary,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primary ? t.accentText : t.accent,
                    ),
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium?.copyWith(
                      color: primary ? t.accentText : t.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
