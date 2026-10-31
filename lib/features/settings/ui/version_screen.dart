/// «Версия»: проверка обновления и заметки к новой версии.
///
/// Открывается строкой «Версия» из группы «Приложение». Проверка запускается
/// сама при открытии — на страницу и заходят затем, чтобы узнать, вышло ли
/// новое; жать для этого ещё и кнопку незачем. Кнопка внизу остаётся, но она
/// про второй заход: «Проверить снова» (или «Открыть страницу релиза», если
/// новое нашлось).
///
/// Заметка показана прямо на странице, а не шторкой поверх: сюда приходят
/// читать, что в обновлении, — это и есть содержимое страницы, а не
/// всплывающая добавка. Берём заметку к НАЙДЕННОЙ версии, а нет её в
/// манифесте — к установленной. Отдельной строки «Что нового» поэтому нет:
/// она открывала бы шторкой ровно то, что уже на экране.
///
/// Скачать и поставить APK сами мы не можем (см. `about_store.dart`), поэтому
/// «Открыть страницу релиза» уводит в браузер — дальше человек качает сам.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/log/bloom_log.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/subpage_header.dart';
import '../about_store.dart';
import '../update_notes_store.dart';
import 'settings_rows.dart';
import 'update_notes_sheet.dart';

class VersionScreen extends ConsumerStatefulWidget {
  const VersionScreen({super.key});

  @override
  ConsumerState<VersionScreen> createState() => _VersionScreenState();
}

class _VersionScreenState extends ConsumerState<VersionScreen> {
  @override
  void initState() {
    super.initState();
    // Сначала версия, потом проверка: без установленной версии сравнивать
    // релиз не с чем (`check` в этом случае честно скажет «есть релиз N»).
    Future.microtask(() async {
      final about = ref.read(aboutProvider.notifier);
      await about.loadVersion();
      if (mounted) await about.check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final about = ref.watch(aboutProvider);

    return SubPage(
      title: l.aboutVersion,
      onBack: () => context.go('/settings'),
      children: [
        _StatusCard(about: about),
        const SizedBox(height: 14),
        if (about.phase == UpdatePhase.available)
          AccentWideButton(
            label: l.aboutOpenRelease,
            icon: Bi.download,
            onTap: () => _openRelease(about.releaseUrl),
          )
        else
          AccentWideButton(
            label: l.aboutRecheck,
            icon: Bi.refresh,
            busy: about.phase == UpdatePhase.checking,
            onTap: () => ref.read(aboutProvider.notifier).check(),
          ),
        const SizedBox(height: 26),
        // Заметку тянем не раньше, чем проверка кончилась: до этого неизвестно,
        // чью показывать — новой версии или установленной.
        if (about.phase == UpdatePhase.uptodate ||
            about.phase == UpdatePhase.available ||
            about.phase == UpdatePhase.error) ...[
          SettingsCaption(l.updWhatsNew.toUpperCase()),
          const SizedBox(height: 10),
          _NoteBlock(
            version:
                about.phase == UpdatePhase.available && about.latest.isNotEmpty
                ? about.latest
                : about.version,
            fallback: about.version,
          ),
        ],
        const SizedBox(height: 22),
        // История — сюда же из «Системы»: заметки к версиям лежат в одном
        // манифесте с той, что показана выше, и искать их в двух местах незачем.
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsLinkRow(
              icon: Bi.history,
              title: l.updHistory,
              subtitle: l.updHistorySub,
              onTap: () => showUpdateHistory(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openRelease(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Исход проверки крупно: кружок со значком, строка состояния и под ней —
/// какая версия стоит сейчас. Тот же расклад, что на макете: значок, заголовок,
/// подпись — по центру.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.about});

  final AboutState about;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;

    final (icon, color, title) = switch (about.phase) {
      UpdatePhase.idle ||
      UpdatePhase.checking => (null, t.accent, l.aboutChecking),
      // Цвета исходов — те же, что у тостов: зелёный «всё хорошо», жёлтый
      // «не вышло». Про них уже знают по всему приложению.
      UpdatePhase.uptodate => (
        Bi.checkCircleBold,
        kindColor(ToastKind.success, t),
        l.aboutUptodate,
      ),
      UpdatePhase.available => (
        Bi.downloadBold,
        t.accent,
        l.aboutAvailable(about.latest),
      ),
      UpdatePhase.error => (
        Bi.dangerTriangleBold,
        kindColor(ToastKind.warn, t),
        l.aboutError,
      ),
    };

    return GlassBox(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              // Пока идёт проверка — крутилка ровно на месте значка: коробка
              // одна, и блок не подпрыгивает, когда исход приходит.
              child: icon == null
                  ? SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: color,
                      ),
                    )
                  : BloomIcon(icon, size: 34, color: color),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: theme.titleLarge),
            const SizedBox(height: 6),
            Text(
              about.version.isEmpty
                  // Платформа не ответила (так бывает в тестах и на десктопе);
                  // прочерк честнее нуля.
                  ? '${l.aboutVersion} —'
                  : l.aboutInstalled(about.version),
              textAlign: TextAlign.center,
              style: theme.bodyMedium?.copyWith(color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Заметка к версии: те же разделы, что в шторке «Что нового».
///
/// Манифест тянется из сети (или из кэша, если её нет), поэтому блок сам
/// показывает крутилку и сам объясняет пустой исход — заметки к версии может
/// не быть вовсе.
class _NoteBlock extends ConsumerStatefulWidget {
  const _NoteBlock({required this.version, required this.fallback});

  /// Чью заметку показываем: найденной версии или установленной.
  final String version;

  /// Установленная версия — к ней откатываемся, если про найденную в манифесте
  /// ещё не написали.
  final String fallback;

  @override
  ConsumerState<_NoteBlock> createState() => _NoteBlockState();
}

class _NoteBlockState extends ConsumerState<_NoteBlock> {
  Future<UpdateNote?>? _future;
  String? _asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensure();
  }

  @override
  void didUpdateWidget(_NoteBlock old) {
    super.didUpdateWidget(old);
    // Проверка кончилась и версия сменилась с установленной на найденную —
    // перезапрашиваем; в остальных случаях запрос живёт один.
    _ensure();
  }

  void _ensure() {
    if (widget.version.isEmpty || _asked == widget.version) return;
    // Локаль берём тут: к `Localizations` из `initState` обращаться нельзя.
    final locale = Localizations.localeOf(context).languageCode;
    final notes = ref.read(updateNotesProvider);
    _asked = widget.version;
    _future = () async {
      final note = await notes.note(widget.version, locale);
      if (note != null) return note;
      // Про найденную версию в манифесте ещё не написали — показываем заметку
      // к установленной, она человеку тоже в новинку.
      if (widget.fallback.isEmpty || widget.fallback == widget.version) {
        return null;
      }
      return notes.note(widget.fallback, locale);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context).textTheme;

    return GlassBox(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: FutureBuilder<UpdateNote?>(
          future: _future,
          builder: (context, snapshot) {
            if (_future == null ||
                snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              logWarn('notes', 'заметка не загрузилась: ${snapshot.error}');
              return Text(l.updNotesError, style: theme.bodyMedium);
            }
            final note = snapshot.data;
            if (note == null) {
              return Text(l.updNotesEmpty, style: theme.bodyMedium);
            }
            final pages = [
              for (final page in note.pages)
                if (!page.isEmpty) page,
            ];
            if (pages.isEmpty && note.title.isEmpty) {
              return Text(l.updNotesEmpty, style: theme.bodyMedium);
            }
            final locale = Localizations.localeOf(context).languageCode;
            final date = formatNoteDate(note.date, locale);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Шапка заметки: чья версия и когда вышла — иначе на странице
                // не видно, к чему относится текст.
                Text(
                  note.title.isEmpty ? 'v${note.version}' : note.title,
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  ['v${note.version}', if (date.isNotEmpty) date].join(' · '),
                  style: theme.bodySmall,
                ),
                for (final page in pages) ...[
                  const SizedBox(height: 18),
                  UpdateNoteSection(page: page),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
