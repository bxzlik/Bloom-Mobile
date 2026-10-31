/// Настройки мини-плеера — карточки над таб-баром.
///
/// Своя страница, а не группа в «Плеере»: настроек у карточки шесть, и в конце
/// длинной страницы полноэкранного плеера их приходилось искать прокруткой
/// (так решил пользователь, показав макет). Десктопной пары у страницы нет — на
/// ПК все `mp*` живут одной секцией «Вид».
///
/// Настройки самих переходов при смене трека («Смена трека» → «Мини-плеер»)
/// остались в «Плеере»: там обе поверхности стоят рядом и настраиваются
/// сравнением одна с другой.
///
/// Строки — те же, что на странице «Плеера» ([SettingsValueRow]): название,
/// под ним выбранное, справа значок. Варианты — списком в шторке, а не
/// плитками: подписи тут длинные («Кольцо на обложке»), в четверть ширины
/// телефона они превращаются в многоточие.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../features/player/mini_style_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/subpage_header.dart';
import 'settings_sheets.dart';

class MiniPlayerSettingsScreen extends ConsumerWidget {
  const MiniPlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mini = ref.watch(miniStyleProvider);
    final l = context.l;

    return SubPage(
      title: l.setMiniPlayer,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.pvGroupLook.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvMiniBgRow,
              value: _miniBgLabel(l, mini.bg),
              glyph: BloomIcon(_miniBgIcon(mini.bg)),
              onTap: () => _openMiniBg(context, ref),
            ),
            SettingsValueRow(
              title: l.pvMiniShapeRow,
              value: _miniShapeLabel(l, mini.shape),
              glyph: BloomIcon(_miniShapeIcon(mini.shape)),
              onTap: () => _openMiniShape(context, ref),
            ),
            SettingsValueRow(
              title: l.pvMiniRadiusRow,
              value: _miniRadiusLabel(l, mini.radius),
              glyph: BloomIcon(_miniRadiusIcon(mini.radius)),
              onTap: () => _openMiniRadius(context, ref),
            ),
            SettingsValueRow(
              title: l.pvMiniProgressRow,
              value: _miniProgressSummary(l, mini),
              // Набор: значок общий — про сам прогресс.
              glyph: const BloomIcon(Bi.soundwave),
              onTap: () => _openMiniProgress(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupMiniControls.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvMiniButtonsRow,
              value: _miniButtonsSummary(l, mini),
              // Набор: значок общий — про кнопки.
              glyph: const BloomIcon(Bi.gamepad),
              onTap: () => _openMiniButtons(context),
            ),
            SettingsValueRow(
              title: l.pvMiniNeighborsRow,
              value: _miniNeighborsLabel(l, mini.neighbors),
              glyph: BloomIcon(_miniNeighborsIcon(mini.neighbors)),
              onTap: () => _openMiniNeighbors(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Внешний вид ─────────────────────────────────────────────────────────────
// Десктопные `mp*`: фон, форма обложки, скругление углов, индикаторы прогресса.

String _miniBgLabel(AppLocalizations l, MiniBg bg) => switch (bg) {
  MiniBg.theme => l.pvMiniBgTheme,
  MiniBg.coverColor => l.pvMiniBgCoverColor,
  MiniBg.cover => l.pvMiniBgCover,
};

BloomGlyph _miniBgIcon(MiniBg bg) => switch (bg) {
  MiniBg.theme => Bi.paintRoller,
  MiniBg.coverColor => Bi.palette,
  MiniBg.cover => Bi.gallery,
};

String _miniShapeLabel(AppLocalizations l, MiniCoverShape shape) =>
    switch (shape) {
      MiniCoverShape.rounded => l.pvMiniShapeRounded,
      MiniCoverShape.circle => l.pvMiniShapeCircle,
    };

BloomGlyph _miniShapeIcon(MiniCoverShape shape) => switch (shape) {
  MiniCoverShape.rounded => Bi.stop,
  MiniCoverShape.circle => Bi.record,
};

String _miniRadiusLabel(AppLocalizations l, MiniRadius radius) =>
    switch (radius) {
      MiniRadius.none => l.pvMiniRadiusNone,
      MiniRadius.soft => l.pvMiniRadiusSoft,
      MiniRadius.rounded => l.pvMiniRadiusRounded,
      MiniRadius.pill => l.pvMiniRadiusPill,
    };

BloomGlyph _miniRadiusIcon(MiniRadius radius) => switch (radius) {
  MiniRadius.none => Bi.stop,
  MiniRadius.soft => Bi.widget,
  MiniRadius.rounded => Bi.widget2,
  MiniRadius.pill => Bi.record,
};

String _miniProgressLabel(AppLocalizations l, MiniProgressKind kind) =>
    switch (kind) {
      MiniProgressKind.line => l.pvMiniProgressLine,
      MiniProgressKind.fill => l.pvMiniProgressFill,
      MiniProgressKind.ring => l.pvMiniProgressRing,
    };

BloomGlyph _miniProgressIcon(MiniProgressKind kind) => switch (kind) {
  MiniProgressKind.line => Bi.minus,
  MiniProgressKind.fill => Bi.stop,
  MiniProgressKind.ring => Bi.refreshCircle,
};

/// Подпись строки «Индикаторы прогресса»: включённое через запятую, в том же
/// порядке, в каком идут строки шторки. Через запятую, а не через точку, как у
/// соседей: тут не «одно из», а набор.
String _miniProgressSummary(AppLocalizations l, MiniStyle mini) {
  final parts = [
    for (final kind in MiniProgressKind.values)
      if (mini.has(kind)) _miniProgressLabel(l, kind),
  ];
  return parts.isEmpty ? l.pvMiniProgressNone : parts.join(', ');
}

Future<void> _openMiniBg(BuildContext context, WidgetRef ref) => pickOneSheet(
  context: context,
  title: context.l.pvMiniBgRow,
  subtitle: context.l.pvMiniBgSub,
  values: MiniBg.values,
  current: ref.read(miniStyleProvider).bg,
  icon: _miniBgIcon,
  label: (bg) => _miniBgLabel(context.l, bg),
  apply: ref.read(miniStyleProvider.notifier).setBg,
);

Future<void> _openMiniShape(BuildContext context, WidgetRef ref) =>
    pickOneSheet(
      context: context,
      title: context.l.pvMiniShapeRow,
      values: MiniCoverShape.values,
      current: ref.read(miniStyleProvider).shape,
      icon: _miniShapeIcon,
      label: (shape) => _miniShapeLabel(context.l, shape),
      apply: ref.read(miniStyleProvider.notifier).setShape,
    );

Future<void> _openMiniRadius(BuildContext context, WidgetRef ref) =>
    pickOneSheet(
      context: context,
      title: context.l.pvMiniRadiusRow,
      values: MiniRadius.values,
      current: ref.read(miniStyleProvider).radius,
      icon: _miniRadiusIcon,
      label: (radius) => _miniRadiusLabel(context.l, radius),
      apply: ref.read(miniStyleProvider.notifier).setRadius,
    );

/// Шторка индикаторов прогресса — набор, а не выбор: строки переключаются на
/// месте, и шторка остаётся открытой, их настраивают подряд.
Future<void> _openMiniProgress(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: settingsSheetHeader(
      context,
      l.pvMiniProgressRow,
      l.pvMiniProgressSub,
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final mini = ref.watch(miniStyleProvider);
        final ctrl = ref.read(miniStyleProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in MiniProgressKind.values)
              SheetOptionTile(
                icon: _miniProgressIcon(kind),
                label: _miniProgressLabel(l, kind),
                active: mini.has(kind),
                check: true,
                onTap: () => ctrl.toggleProgress(kind, !mini.has(kind)),
              ),
          ],
        );
      },
    ),
  );
}

// ── Управление ──────────────────────────────────────────────────────────────

String _miniButtonLabel(AppLocalizations l, MiniButton button) =>
    switch (button) {
      MiniButton.prev => l.pvMiniButtonPrev,
      MiniButton.play => l.pvMiniButtonPlay,
      MiniButton.next => l.pvMiniButtonNext,
      MiniButton.fav => l.pvMiniButtonFav,
    };

BloomGlyph _miniButtonIcon(MiniButton button) => switch (button) {
  MiniButton.prev => Bi.skipPrevious,
  MiniButton.play => Bi.play,
  MiniButton.next => Bi.skipNext,
  MiniButton.fav => Bi.heart,
};

/// Подпись строки «Кнопки управления» — включённые в том порядке, в каком они
/// стоят в самой карточке.
String _miniButtonsSummary(AppLocalizations l, MiniStyle mini) {
  final parts = [
    for (final button in MiniButton.values)
      if (mini.hasButton(button)) _miniButtonLabel(l, button),
  ];
  return parts.isEmpty ? l.pvMiniButtonsNone : parts.join(', ');
}

/// Шторка кнопок — тоже набор: включать можно любые, включая ни одной (тогда в
/// карточке остаются обложка с подписью, а играет она с полноэкранного плеера).
Future<void> _openMiniButtons(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: settingsSheetHeader(
      context,
      l.pvMiniButtonsRow,
      l.pvMiniButtonsSub,
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final mini = ref.watch(miniStyleProvider);
        final ctrl = ref.read(miniStyleProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final button in MiniButton.values)
              SheetOptionTile(
                icon: _miniButtonIcon(button),
                label: _miniButtonLabel(l, button),
                active: mini.hasButton(button),
                check: true,
                onTap: () => ctrl.toggleButton(button, !mini.hasButton(button)),
              ),
          ],
        );
      },
    ),
  );
}

String _miniNeighborsLabel(AppLocalizations l, bool on) =>
    on ? l.pvMiniNeighborsOn : l.pvMiniNeighborsOff;

BloomGlyph _miniNeighborsIcon(bool on) => on ? Bi.transferHorizontal : Bi.stop;

/// Соседние треки — выбор из двух, а не тумблер: строка стоит в одной карточке
/// с остальным видом миниплеера, и её значение должно читаться так же, как у
/// соседних строк («Фон», «Скругление»).
Future<void> _openMiniNeighbors(BuildContext context, WidgetRef ref) =>
    pickOneSheet<bool>(
      context: context,
      title: context.l.pvMiniNeighborsRow,
      subtitle: context.l.pvMiniNeighborsSub,
      values: const [false, true],
      current: ref.read(miniStyleProvider).neighbors,
      icon: _miniNeighborsIcon,
      label: (on) => _miniNeighborsLabel(context.l, on),
      apply: ref.read(miniStyleProvider.notifier).setNeighbors,
    );
