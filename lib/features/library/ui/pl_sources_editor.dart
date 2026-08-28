/// Секция «Источники обновления» в правке плейлиста — порт десктопного
/// `PlSourcesEditor`.
///
/// Показывает привязанные коллекции (плейлисты/альбомы/лайки любых площадок) и
/// даёт привязать новую вставкой ссылки: по «Привязать» ссылка резолвится тем
/// же путём, что и импорт (`resolveCollectionUrl`), — так проверяем, что это
/// вообще коллекция, и заодно забираем её название для строки.
///
/// Черновик живёт у родителя ([ListEditor]) и записывается только по ✓, как имя
/// и обложка: сеть здесь дёргается сразу, а вот сама привязка — нет.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../import_url.dart';
import 'create_playlist_sheet.dart' show detectLinkSource;

class PlSourcesEditor extends ConsumerStatefulWidget {
  const PlSourcesEditor({
    super.key,
    required this.sources,
    required this.onChanged,
  });

  final List<PlSourceRef> sources;
  final ValueChanged<List<PlSourceRef>> onChanged;

  @override
  ConsumerState<PlSourcesEditor> createState() => _PlSourcesEditorState();
}

class _PlSourcesEditorState extends ConsumerState<PlSourcesEditor> {
  final _url = TextEditingController();

  /// Идёт резолв вставленной ссылки.
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final url = _url.text.trim();
    if (url.isEmpty || _busy) return;
    // Дубль ловим ДО сети: привязывать одно и то же дважды незачем, а ждать
    // ради этого ответа площадки — тем более.
    if (widget.sources.any((s) => s.url == url)) {
      showToast(context, context.l.psDuplicate, kind: ToastKind.warn);
      return;
    }
    setState(() => _busy = true);
    try {
      final found = await resolveCollectionUrl(ref.read(registryProvider), url);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _url.clear();
      });
      widget.onChanged([
        ...widget.sources,
        PlSourceRef(url: url, title: found.title),
      ]);
    } on ImportException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(
        context,
        describeImportFailure(context.l, e.reason),
        kind: ToastKind.warn,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, context.l.cpSourceNoAnswer, kind: ToastKind.error);
    }
  }

  void _remove(int index) => widget.onChanged([
    for (var i = 0; i < widget.sources.length; i++)
      if (i != index) widget.sources[i],
  ]);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l.psTitle, style: theme.titleMedium),
          const SizedBox(height: 4),
          Text(
            context.l.psHint,
            style: theme.bodySmall?.copyWith(color: t.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.sources.length; i++) ...[
            _SourceRow(
              source: widget.sources[i],
              onRemove: _busy ? null : () => _remove(i),
            ),
            const SizedBox(height: 8),
          ],
          _AddRow(
            controller: _url,
            busy: _busy,
            onChanged: (_) => setState(() {}),
            onSubmit: _add,
          ),
        ],
      ),
    );
  }
}

/// Строка привязки: знак площадки, название коллекции, под ним сама ссылка.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.onRemove});

  final PlSourceRef source;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final platform = detectLinkSource(source.url);
    final title = source.title;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: t.pill,
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Row(
        children: [
          // Знак площадки — в фирменных цветах, как везде в приложении.
          if (platform != null) ...[
            PlatformLogo(platform, size: 18),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title ?? source.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleMedium,
                ),
                // Ссылку под названием повторять незачем — она и есть
                // название, когда площадка не сказала своего.
                if (title != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    source.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: t.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: t.muted,
            tooltip: context.l.psRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Поле для новой ссылки и кнопка «Привязать» — те же две части, что в шторке
/// импорта, только кнопка со словом: рядом с ней стоит уже целый список, и одна
/// галочка не сказала бы, что она делает.
class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.controller,
    required this.busy,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final filled = controller.text.trim().isNotEmpty;
    final platform = detectLinkSource(controller.text);

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: t.pill,
              borderRadius: BorderRadius.circular(t.radius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !busy,
                    cursorColor: t.accent,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: theme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      hintText: context.l.psAddHint,
                      hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
                    ),
                    onChanged: onChanged,
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                // Значок площадки внутри поля — как только ссылка узнана.
                if (platform != null) ...[
                  const SizedBox(width: 8),
                  PlatformLogo(platform, size: 18),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: filled ? t.accent : t.pill,
          borderRadius: BorderRadius.circular(t.radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: filled && !busy ? onSubmit : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: busy
                        ? CircularProgressIndicator(
                            strokeWidth: 2,
                            color: filled ? t.accentText : t.muted,
                          )
                        : Icon(
                            SolarIconsOutline.addCircle,
                            size: 16,
                            color: filled ? t.accentText : t.muted,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l.psAdd,
                    style: theme.titleMedium?.copyWith(
                      color: filled ? t.accentText : t.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
