/// «Настройки → Кастомизация → Пресеты» — снимки применённых картинок.
///
/// Порт десктопной карточки `PresetsCard` из `CustomizationSection.tsx`:
/// сетка карточек с превью-каруселью, создание по имени, экспорт и импорт
/// файла `.bloompresets`. Контекстное меню правой кнопкой там — здесь наша
/// шторка по тапу (`showBloomSheet`), как у всего остального в приложении.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../media_store.dart';
import '../presets_file.dart';
import '../presets_store.dart';
import 'custom_widgets.dart';

class PresetsScreen extends ConsumerWidget {
  const PresetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider);

    return CustomizationPage(
      title: context.l.custPresets,
      onBack: () => context.go('/settings'),
      actions: [
        WideButton(
          icon: SolarIconsOutline.addCircle,
          label: context.l.custPresetCreate,
          onTap: () => _create(context, ref),
        ),
        WideButton(
          icon: SolarIconsOutline.import,
          label: context.l.custImport,
          onTap: () => _import(context, ref),
        ),
      ],
      child: presets.isEmpty
          ? EmptyHint(text: context.l.custPresetsEmpty)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 4 / 3,
              ),
              itemCount: presets.length,
              itemBuilder: (_, i) => _PresetCard(preset: presets[i]),
            ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showBloomSheetChild<String>(
      context: context,
      child: SheetTextField(hint: context.l.custPresetNameHint, maxLength: 40),
    );
    if (name == null || !context.mounted) return;
    final saved = ref.read(presetsProvider.notifier).save(name);
    // Два разных отказа: упёрлись в лимит или нечего снимать — ни один
    // контекст не занят.
    final failure = ref.read(presetsProvider).length >= kPresetsLimit
        ? context.l.custPresetsFull(kPresetsLimit)
        : context.l.custPresetNothing;
    showToast(
      context,
      saved == null ? failure : context.l.custPresetSaved(saved.name),
      kind: saved == null ? ToastKind.warn : ToastKind.success,
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final content = await openTextFile();
    if (content == null || !context.mounted) return;
    final added = await importPresets(ref.read, content);
    if (!context.mounted) return;
    showToast(
      context,
      added == 0 ? context.l.custImportBad : context.l.custImported(added),
      kind: added == 0 ? ToastKind.warn : ToastKind.success,
    );
  }
}

class _PresetCard extends ConsumerWidget {
  const _PresetCard({required this.preset});

  final Preset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final lib = ref.watch(mediaLibProvider);
    final srcs = [
      for (final id in preset.imageIds)
        for (final item in lib)
          if (item.id == id) item.src,
    ];

    return GestureDetector(
      onTap: () => _openSheet(context, ref, srcs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius * 0.85),
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.pill),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PresetThumb(srcs: srcs),
              // Подпись — плашкой у нижнего края, как на макете: поверх
              // картинки, а не под ней.
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Text(
                    preset.name.isEmpty
                        ? context.l.custPresetUntitled
                        : preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref,
    List<String> srcs,
  ) async {
    final l10n = context.l;
    final messenger = ScaffoldMessenger.of(context);
    await showBloomSheet(
      context: context,
      backdrop: srcs.isEmpty ? null : srcs.first,
      header: _PresetSheetHeader(
        srcs: srcs,
        name: preset.name.isEmpty ? l10n.custPresetUntitled : preset.name,
      ),
      groups: [
        [
          SheetAction(
            icon: SolarIconsOutline.checkCircle,
            label: l10n.custPresetApply,
            onTap: () {
              ref.read(presetsProvider.notifier).apply(preset.id);
              messenger.toast(
                l10n.custPresetApplied(preset.name),
                kind: ToastKind.success,
              );
            },
          ),
          SheetAction(
            icon: SolarIconsOutline.export,
            label: l10n.custPresetExport,
            onTap: () async {
              final content = await encodePresets([
                preset,
              ], ref.read(mediaLibProvider));
              final ok = await saveTextFile(
                presetFileName(preset.name),
                content,
              );
              // Отмена диалога — не повод для тоста: человек сам закрыл окно.
              if (ok) {
                messenger.toast(
                  l10n.custPresetExported,
                  kind: ToastKind.success,
                );
              }
            },
          ),
        ],
        [
          SheetAction(
            icon: SolarIconsOutline.trashBinMinimalistic,
            label: l10n.commonDelete,
            danger: true,
            onTap: () => ref.read(presetsProvider.notifier).delete(preset.id),
          ),
        ],
      ],
    );
  }
}

/// Шапка шторки пресета: крупная обложка на всю ширину шторки и имя ПОД ней.
///
/// Так его показал пользователь. Общий [SheetCoverHeader] не подошёл вдвойне:
/// там название лежит поверх картинки, а картинка одна — здесь же их столько,
/// сколько занятых контекстов, и листать их можно пальцем (точки снизу
/// показывают, сколько всего).
class _PresetSheetHeader extends StatefulWidget {
  const _PresetSheetHeader({required this.srcs, required this.name});

  final List<String> srcs;
  final String name;

  @override
  State<_PresetSheetHeader> createState() => _PresetSheetHeaderState();
}

class _PresetSheetHeaderState extends State<_PresetSheetHeader> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final srcs = widget.srcs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(t.radius),
            child: AspectRatio(
              // Те же пропорции, что у широкой обложки в других шторках.
              aspectRatio: 1 / 0.56,
              child: DecoratedBox(
                // Плашка красится как блоки шторки: с картинками под ней
                // лежит размытая обложка, без них — обычный фон темы.
                decoration: BoxDecoration(color: sheetPanelColor(context)),
                child: srcs.isEmpty
                    ? Center(
                        child: Icon(
                          SolarIconsOutline.box,
                          size: 30,
                          color: t.muted,
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          PageView.builder(
                            controller: _pages,
                            itemCount: srcs.length,
                            onPageChanged: (i) => setState(() => _index = i),
                            itemBuilder: (_, i) {
                              final image = coverImage(srcs[i]);
                              return image == null
                                  ? const SizedBox.expand()
                                  : Image(
                                      image: image,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox.expand(),
                                    );
                            },
                          ),
                          if (srcs.length > 1)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 10,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < srcs.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 6),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(
                                          alpha: i == _index ? 0.9 : 0.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Превью пресета: все его картинки листаются сами, как на десктопе
/// (`PresetThumb`, смена каждые 2.2 с). Одна картинка — просто картинка, ноль —
/// значок коробки.
class PresetThumb extends StatefulWidget {
  const PresetThumb({super.key, required this.srcs});

  final List<String> srcs;

  @override
  State<PresetThumb> createState() => _PresetThumbState();
}

class _PresetThumbState extends State<PresetThumb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _cycle.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      setState(() => _index = (_index + 1) % widget.srcs.length);
      _cycle.forward(from: 0);
    });
    if (widget.srcs.length > 1) _cycle.forward();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    if (widget.srcs.isEmpty) {
      return Center(
        child: Icon(SolarIconsOutline.box, size: 26, color: t.muted),
      );
    }
    final image = coverImage(widget.srcs[_index % widget.srcs.length]);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: image == null
          ? const SizedBox.expand()
          : Image(
              key: ValueKey(_index),
              image: image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
    );
  }
}
