/// Настройки → «Система» — порт десктопной секции `PlaybackSection.tsx`
/// (плюс `AboutBlock.tsx` в шапке).
///
/// Что перенесено: «О приложении», «Импорт/Экспорт», «Логи» и «Опасная зона».
/// Что нет и почему: автозапуск с логином Windows, сворачивание в трей, трек в
/// заголовке окна и обложка в трее — всё это про окно и трей, которых на
/// телефоне нет. Десктопное «Автовоспроизведение» из группы «Запуск» уехало в
/// «Аудио» — так выбрал пользователь.
///
/// Подтверждения — шторкой с красной кнопкой, а не системным `confirm()`, как
/// на ПК: тот же приём, что в «Хранилище», и по той же причине — на телефоне
/// промахнуться по строке в списке легко, по шторке нет.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/log/bloom_log.dart';
import '../../../core/store/library_store.dart';
import '../../../core/store/text_files.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/subpage_header.dart';
import '../about_store.dart';
import '../data_transfer.dart';
import '../reset.dart';
import 'platform_page.dart' show PlatformButton;
import 'settings_rows.dart';

class SystemSettingsScreen extends ConsumerWidget {
  const SystemSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final t = context.bloom;

    return SubPage(
      title: l.setSystem,
      onBack: () => context.go('/settings'),
      children: [
        const _AboutCard(),
        const SizedBox(height: 22),
        SettingsCaption(l.sysImportExport.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsLinkRow(
              icon: SolarIconsOutline.export,
              title: l.sysExportTitle,
              subtitle: l.sysExportSub,
              onTap: () => _exportAll(context, ref),
            ),
            SettingsLinkRow(
              icon: SolarIconsOutline.import,
              title: l.sysImportTitle,
              subtitle: l.sysImportSub,
              onTap: () => _import(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.sysLogs.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsLinkRow(
              icon: SolarIconsOutline.documentText,
              title: l.sysLogTitle,
              subtitle: BloomLog.instance.isEmpty
                  ? l.sysLogEmptySub
                  : l.sysLogEntries(BloomLog.instance.length),
              onTap: () => context.go('/settings/system/logs'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        // Заголовок опасной зоны красный и со значком — как `h3` с `Ico danger`
        // на десктопе.
        Row(
          children: [
            Icon(
              SolarIconsOutline.dangerTriangle,
              size: 13,
              color: t.sysFavIco,
            ),
            const SizedBox(width: 6),
            SettingsCaption(l.sysDangerZone.toUpperCase()),
          ],
        ),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsLinkRow(
              icon: SolarIconsOutline.restart,
              title: l.sysResetTitle,
              subtitle: l.sysResetSub,
              danger: true,
              onTap: () => _confirmReset(context, ref, hard: false),
            ),
            SettingsLinkRow(
              icon: SolarIconsOutline.trashBinMinimalistic,
              title: l.sysHardResetTitle,
              subtitle: l.sysHardResetSub,
              danger: true,
              onTap: () => _confirmReset(context, ref, hard: true),
            ),
          ],
        ),
      ],
    );
  }
}

/// «О приложении»: знак, название, версия и проверка обновлений.
///
/// На ПК тут же живёт установка обновления; в мобилке её нет и быть не может —
/// APK ставит система. Поэтому максимум, что делает кнопка, — открывает
/// страницу релиза в браузере (см. `about_store.dart`).
class _AboutCard extends ConsumerStatefulWidget {
  const _AboutCard();

  @override
  ConsumerState<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends ConsumerState<_AboutCard> {
  @override
  void initState() {
    super.initState();
    // Версию спрашиваем у платформы один раз за сеанс: ответ не меняется до
    // переустановки. Не в `build` — там правка состояния пришлась бы на фазу
    // построения кадра.
    Future.microtask(() => ref.read(aboutProvider.notifier).loadVersion());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final about = ref.watch(aboutProvider);

    return GlassBox(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BloomMark(size: 42, color: t.text),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bloom', style: theme.titleLarge),
                      const SizedBox(height: 3),
                      Text(
                        about.version.isEmpty
                            // Версии нет — платформа не ответила (так бывает в
                            // тестах и на десктопе); прочерк честнее нуля.
                            ? '${l.aboutVersion} —'
                            : '${l.aboutVersion} v${about.version}'
                                  '${about.build.isEmpty ? '' : ' · ${l.aboutBuild(about.build)}'}',
                        style: theme.bodySmall?.copyWith(color: t.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _statusText(l, about),
              style: theme.bodySmall?.copyWith(
                color: about.phase == UpdatePhase.available ? t.text : t.text2,
              ),
            ),
            const SizedBox(height: 12),
            if (about.phase == UpdatePhase.available)
              PlatformButton(
                label: l.aboutOpenRelease,
                height: 46,
                onTap: () => _openRelease(about.releaseUrl),
              )
            else
              PlatformButton(
                label: l.aboutCheck,
                height: 46,
                muted: true,
                busy: about.phase == UpdatePhase.checking,
                onTap: () => ref.read(aboutProvider.notifier).check(),
              ),
          ],
        ),
      ),
    );
  }

  String _statusText(AppLocalizations l, AboutState about) =>
      switch (about.phase) {
        UpdatePhase.idle => l.aboutIdle,
        UpdatePhase.checking => l.aboutChecking,
        UpdatePhase.uptodate => l.aboutUptodate,
        UpdatePhase.available => l.aboutAvailable(about.latest),
        UpdatePhase.error => l.aboutError,
      };

  Future<void> _openRelease(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Выгрузить все плейлисты файлом. Отмена диалога — тишина, как на десктопе.
Future<void> _exportAll(BuildContext context, WidgetRef ref) async {
  final l = context.l;
  final messenger = ScaffoldMessenger.of(context);
  final lib = ref.read(libraryProvider);
  if (lib.playlists.isEmpty) {
    messenger.toast(l.sysNoPlaylists, kind: ToastKind.warn);
    return;
  }
  final ok = await saveTextFile(l.sysExportFilename, buildExportAllBundle(lib));
  if (!ok) return;
  logInfo('transfer', 'выгружено плейлистов: ${lib.playlists.length}');
  messenger.toast(l.sysExported, kind: ToastKind.success);
}

/// Загрузить плейлисты из файла.
Future<void> _import(BuildContext context, WidgetRef ref) async {
  final l = context.l;
  final messenger = ScaffoldMessenger.of(context);
  final content = await openTextFile();
  if (content == null) return; // диалог закрыли
  final result = importPlaylistBundle(
    content,
    ref.read(libraryProvider),
    ref.read(libraryProvider.notifier),
  );
  if (result == null) {
    messenger.toast(l.sysImportInvalid, kind: ToastKind.error);
    return;
  }
  if (result.playlists == 0) {
    messenger.toast(l.sysImportNoPlaylists, kind: ToastKind.warn);
    return;
  }
  logInfo('transfer', 'импорт: ${result.playlists} пл., ${result.tracks} тр.');
  messenger.toast(
    result.tracks > 0
        ? l.sysImportedFull(result.playlists, result.tracks)
        : l.sysImportedPlaylists(result.playlists),
    kind: ToastKind.success,
  );
}

/// Шторка подтверждения сброса. [hard] — «Сбросить всё».
Future<void> _confirmReset(
  BuildContext context,
  WidgetRef ref, {
  required bool hard,
}) async {
  final l = context.l;
  final messenger = ScaffoldMessenger.of(context);

  final yes = await showBloomSheetChild<bool>(
    context: context,
    child: _ConfirmBody(
      icon: hard
          ? SolarIconsOutline.trashBinMinimalistic
          : SolarIconsOutline.restart,
      title: hard ? l.sysHardResetTitle : l.sysResetTitle,
      body: hard ? l.sysHardResetBody : l.sysResetBody,
      button: hard ? l.sysHardResetBtn : l.sysResetBtn,
    ),
  );
  if (yes != true) return;

  if (hard) {
    await hardReset(ref);
    messenger.toast(l.sysHardResetDone, kind: ToastKind.success);
  } else {
    await resetSettings(ref);
    messenger.toast(l.sysResetDone, kind: ToastKind.success);
  }
}

/// Тело шторки подтверждения: крупный значок, название, что произойдёт, и
/// красная кнопка во всю ширину — тот же вид, что у очистки в «Хранилище».
class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.icon,
    required this.title,
    required this.body,
    required this.button,
  });

  final IconData icon;
  final String title;
  final String body;
  final String button;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: t.sysFavIco.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: t.sysFavIco),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.titleLarge),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.bodySmall?.copyWith(color: t.text2),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: const Color(0xFFE0494A),
              borderRadius: BorderRadius.circular(t.radius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  child: Center(
                    child: Text(
                      button,
                      style: theme.titleMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
