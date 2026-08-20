/// Настройки → Система → «Журнал работы» — порт десктопного
/// `LogsViewerModal.tsx`.
///
/// На ПК это модалка с моноширинным «хвостом» лог-файла и кнопками
/// «Копировать»/«Закрыть»; здесь — своя страница (модалка во весь экран
/// телефона и есть страница), а «Сохранить» и «Очистить» с десктопной строки
/// «Журнал работы» переехали сюда же: держать действия над журналом в двух
/// местах на телефоне незачем.
///
/// Порядок записей ОБРАТНЫЙ файлу: свежее сверху. В файле лог читается сверху
/// вниз, но на телефоне открывший страницу почти всегда ищет то, что случилось
/// только что, и мотать до конца ради этого не должен. Выгрузка и копирование
/// отдают журнал как есть — по времени.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/log/bloom_log.dart';
import '../../../core/store/text_files.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/subpage_header.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  /// Снимок журнала на момент открытия — иначе список ехал бы под пальцем от
  /// каждой новой записи (а пишет в него и сама эта страница).
  late List<LogEntry> _entries = BloomLog.instance.entries.reversed.toList();

  void _reload() =>
      setState(() => _entries = BloomLog.instance.entries.reversed.toList());

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: BloomLog.instance.text()));
    if (!mounted) return;
    showToast(context, context.l.logsCopied, kind: ToastKind.success);
  }

  Future<void> _save() async {
    final l = context.l;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'bloom-${now.year}-${two(now.month)}-${two(now.day)}.log';
    final ok = await saveTextFile(
      name,
      BloomLog.instance.text(),
      mime: 'text/plain',
    );
    if (!ok) return; // диалог закрыли — молчим, как везде с файлами
    messenger.toast(l.logsSaved, kind: ToastKind.success);
  }

  Future<void> _clear() async {
    final l = context.l;
    final messenger = ScaffoldMessenger.of(context);
    await BloomLog.instance.clear();
    _reload();
    messenger.toast(l.logsCleared, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.bloom;
    final empty = _entries.isEmpty;

    return SubPage(
      title: l.sysLogTitle,
      onBack: () => context.go('/settings/system'),
      children: [
        Row(
          children: [
            Expanded(
              child: _LogButton(
                icon: SolarIconsOutline.copy,
                label: l.logsCopy,
                onTap: empty ? null : _copy,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LogButton(
                icon: SolarIconsOutline.export,
                label: l.logsSave,
                onTap: empty ? null : _save,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LogButton(
                icon: SolarIconsOutline.trashBinMinimalistic,
                label: l.logsClear,
                danger: true,
                onTap: empty ? null : _clear,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                l.logsEmpty,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: t.muted),
              ),
            ),
          )
        else
          GlassBox(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in _entries) _LogLine(entry: entry),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Одна запись: моноширинная строка, цвет — по уровню.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = switch (entry.level) {
      // Тот же красный, что у ошибок в уведомлениях (`notifications.css` на ПК).
      LogLevel.error => const Color(0xFFFF6B6B),
      LogLevel.warn => t.text,
      LogLevel.info => t.text2,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        entry.format(),
        style: TextStyle(
          // Своё семейство, а не Inter: журнал читают столбиком по времени, и
          // пропорциональный шрифт эти столбцы разваливает.
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.45,
          color: color,
        ),
      ),
    );
  }
}

/// Кнопка над журналом: значок и подпись, во всю ширину своей трети.
class _LogButton extends StatelessWidget {
  const _LogButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final enabled = onTap != null;
    final color = !enabled
        ? t.muted
        : danger
        ? t.sysFavIco
        : t.text;

    return GlassBox(
      borderRadius: BorderRadius.circular(t.radius),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
