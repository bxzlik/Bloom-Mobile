/// Внешний вид: язык, тема, акцент, скругления.
///
/// Тема — ровно три цвета пресета; акцент и радиус живут отдельно и при смене
/// темы НЕ сбрасываются (то же правило, что в десктопном `themeStore.ts`).
/// Превью пресета считается теми же формулами, что и сама тема, поэтому кружки
/// в списке не могут разойтись с тем, что применится.
///
/// Пресеты выбираются не сеткой на странице, а нижней шторкой: на экране
/// остаётся одна строка «Тема — Dark» с кружками превью справа.
///
/// Ручного выбора акцента нет — как и на ПК, где акцент задаётся либо темой,
/// либо тогглом авто-акцента из обложки.
///
/// Язык стоит первым — как в десктопном `InterfaceSection.tsx`, где секция
/// «ЯЗЫК» идёт над «ТЕМА».
library;

import 'dart:math' show Random, min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/color_picker.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/language_card.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../wrapped/wrapped_store.dart';
import '../transparency_store.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context).textTheme;

    return SubPage(
      title: context.l.setInterface,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(context.l.apLanguage),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final locale in kLocales) ...[
              if (locale != kLocales.first) const SizedBox(width: 12),
              Expanded(
                child: LanguageCard(
                  locale: locale,
                  // Пока язык не выбран руками, активной считается та
                  // карточка, на которой приложение сейчас говорит — иначе
                  // при системном языке не подсвечена ни одна.
                  active:
                      (settings.locale ?? Localizations.localeOf(context))
                          .languageCode ==
                      locale.languageCode,
                  onTap: () => controller.setLocale(locale),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 26),
        SettingsCaption(context.l.apTheme),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _SettingsCard(
              onTap: () => _pickTheme(context, ref),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l.apThemeRow, style: theme.titleMedium),
                        const SizedBox(height: 3),
                        Text(settings.preset.name, style: theme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _ThemeDots(preset: settings.preset),
                ],
              ),
            ),
            // Авто-акцент — тот же тоггл, что в десктопной секции «Интерфейс»:
            // ручного выбора акцента нет ни там, ни здесь.
            _SettingsCard(
              child: _SettingsRow(
                title: context.l.apAutoAccent,
                subtitle: context.l.apAutoAccentSub,
                trailing: BloomSwitch(
                  value: settings.autoAccent,
                  onChanged: controller.setAutoAccent,
                ),
              ),
            ),
            // Яркость — отдельной строкой под тогглом, ровно как на ПК: она
            // нужна, только пока авто-акцент включён.
            if (settings.autoAccent)
              _SettingsCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          context.l.apAutoAccentLevel,
                          style: theme.titleMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${(settings.autoAccentL * 100).round()} %',
                          style: theme.bodySmall,
                        ),
                      ],
                    ),
                    Slider(
                      value: settings.autoAccentL,
                      min: kAutoAccentLMin,
                      max: kAutoAccentLMax,
                      onChanged: controller.setAutoAccentL,
                    ),
                  ],
                ),
              ),
            // Бейджи стоят тут же, в блоке темы, и сразу после авто-акцента —
            // тот же порядок, что в десктопной секции «Интерфейс»: настройка
            // про акцент, а не про скругления. Тексты — из `dict.ts`
            // (`settings.interface.accentBadges`).
            _SettingsCard(
              child: _SettingsRow(
                title: context.l.apBadgesTitle,
                subtitle: context.l.apBadgesSubtitle,
                trailing: BloomSwitch(
                  value: settings.accentBadges,
                  onChanged: controller.setAccentBadges,
                ),
              ),
            ),
            // «Обложка трека как фон» — десктопная настройка вкладки «Фон»
            // раздела «Кастомизация»; сюда её перенёс пользователь. Своя
            // картинка фона (её ставят в «Кастомизации») эту настройку
            // перебивает — как и на ПК.
            _SettingsCard(
              child: _SettingsRow(
                title: context.l.apCoverAsBg,
                subtitle: context.l.apCoverAsBgSub,
                trailing: BloomSwitch(
                  value: settings.coverAsBg,
                  onChanged: controller.setCoverAsBg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        SettingsCaption(context.l.apNavBar),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _SettingsCard(
              onTap: () => _pickNavStyle(context, ref),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l.apNavBarRow, style: theme.titleMedium),
                        const SizedBox(height: 3),
                        Text(
                          _navStyleLabel(context.l, settings.navStyle),
                          style: theme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Тот же макет, что в шторке, только мелкий: строка
                  // показывает выбранное, как кружки темы над ней.
                  SizedBox(
                    width: 46,
                    height: 46 * 64 / 100,
                    child: CustomPaint(
                      painter: _NavStyleGlyph(
                        style: settings.navStyle,
                        screen: t.bg,
                        frame: t.ovlLine2,
                        ink: t.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        ..._wrappedGroup(context, ref),
        const SizedBox(height: 26),
        Row(
          children: [
            SettingsCaption(context.l.apCorners),
            const Spacer(),
            Text('${settings.radius.round()} px', style: theme.bodySmall),
          ],
        ),
        Slider(
          value: settings.radius,
          min: 0,
          max: 28,
          divisions: 28,
          onChanged: controller.setRadius,
        ),
        const SizedBox(height: 8),
        // Живой пример: по нему видно и радиус, и акцент разом.
        GlassBox(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(t.radius * 0.72),
                  ),
                  child: Icon(
                    SolarIconsBold.play,
                    size: 20,
                    color: t.accentText,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l.apPreviewTitle, style: theme.titleSmall),
                      const SizedBox(height: 2),
                      Text(context.l.apPreviewSubtitle, style: theme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        ..._transparencyGroup(context, ref),
      ],
    );
  }
}

/// Группа «ИТОГИ» — порт десктопной категории `settings.wrapped.*` (на ПК она
/// живёт в секции «Вкладки», где настраивается сам пункт сайдбара).
///
/// «Показывать всегда» — единственный способ увидеть итоги вне окна показа:
/// без него неделю пришлось бы ждать до понедельника, а год — до 21 декабря.
List<Widget> _wrappedGroup(BuildContext context, WidgetRef ref) {
  final prefs = ref.watch(wrappedPrefsProvider);
  final controller = ref.read(wrappedPrefsProvider.notifier);
  final l = context.l;

  return [
    SettingsCaption(l.wrSetCaption),
    const SizedBox(height: 10),
    SettingsGroupCard(
      rows: [
        _SettingsCard(
          child: _SettingsRow(
            title: l.wrSetShow,
            subtitle: l.wrSetShowSub,
            trailing: BloomSwitch(
              value: prefs.show,
              onChanged: controller.setShow,
            ),
          ),
        ),
        // Расписание настраивается, только пока вход вообще показывается.
        if (prefs.show)
          _SettingsCard(
            child: _SettingsRow(
              title: l.wrSetAlways,
              subtitle: l.wrSetAlwaysSub,
              trailing: BloomSwitch(
                value: prefs.always,
                onChanged: controller.setAlways,
              ),
            ),
          ),
      ],
    ),
  ];
}

/// Группа «ПРОЗРАЧНОСТЬ» — последняя на экране, как категория с тем же именем
/// в конце десктопной секции «Интерфейс».
///
/// Ползунков на самой странице нет (на ПК они стоят прямо в карточке): строка
/// показывает значение и открывает шторку с одним ползунком — так решил
/// пользователь, показав макет. Всё, кроме тумблера режима, скрыто, пока
/// прозрачность выключена: это подрежимы, и настраивать их в выключенном
/// состоянии нечего (десктопный `#sTrSliders` с классом `vis`).
List<Widget> _transparencyGroup(BuildContext context, WidgetRef ref) {
  final tr = ref.watch(transparencyProvider);
  final controller = ref.read(transparencyProvider.notifier);
  final l = context.l;

  return [
    SettingsCaption(l.apTrGroup),
    const SizedBox(height: 10),
    SettingsGroupCard(
      rows: [
        _SettingsCard(
          child: _SettingsRow(
            title: l.apTrTitle,
            subtitle: tr.on ? l.apTrOn(tr.transparencyPercent) : l.apTrOff,
            trailing: BloomSwitch(value: tr.on, onChanged: controller.setOn),
          ),
        ),
        if (tr.on) ...[
          _TrValueRow(
            icon: SolarIconsOutline.eye,
            title: l.apTrLevel,
            value: '${tr.transparencyPercent}%',
            onTap: () => _pickTrValue(
              context: context,
              title: l.apTrLevel,
              value: tr.transparencyPercent,
              max: 100,
              unit: '%',
              onChanged: controller.setTransparencyPercent,
            ),
          ),
          _TrValueRow(
            icon: SolarIconsOutline.sun2,
            title: l.apTrBrightness,
            value: '${tr.glassStr}%',
            onTap: () => _pickTrValue(
              context: context,
              title: l.apTrBrightness,
              value: tr.glassStr,
              max: 100,
              unit: '%',
              onChanged: controller.setGlassStr,
            ),
          ),
          _TrValueRow(
            icon: SolarIconsOutline.waterdrop,
            title: l.apTrBlur,
            value: '${tr.glassBlur}px',
            onTap: () => _pickTrValue(
              context: context,
              title: l.apTrBlur,
              value: tr.glassBlur,
              max: kTrBlurMax,
              unit: 'px',
              onChanged: controller.setGlassBlur,
            ),
          ),
          _SettingsCard(
            child: _SettingsRow(
              title: l.apTrOverlays,
              subtitle: l.apTrOverlaysSub,
              trailing: BloomSwitch(
                value: tr.overlayGlass,
                onChanged: controller.setOverlayGlass,
              ),
            ),
          ),
        ],
      ],
    ),
  ];
}

/// Строка группы: название, под ним значение или пояснение, справа — тумблер
/// либо кружок со значком.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.titleMedium),
              const SizedBox(height: 3),
              // Ярче общего `bodySmall` — как выбранное в строках «Плеера».
              Text(
                subtitle,
                style: theme.bodySmall?.copyWith(color: context.bloom.text2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        trailing,
      ],
    );
  }
}

/// Строка с ползунком за ней: значение под названием, справа кружок со
/// значком. Кружок не кнопка — нажимается вся строка, а он показывает, о чём
/// она (глаз — прозрачность, солнце — яркость, капля — размытие).
class _TrValueRow extends StatelessWidget {
  const _TrValueRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return _SettingsCard(
      onTap: onTap,
      child: _SettingsRow(
        title: title,
        subtitle: value,
        trailing: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: t.text),
        ),
      ),
    );
  }
}

/// Шторка одного ползунка: заголовок, значение и полоса. Значение применяется
/// НА ХОДУ, не по закрытию, — иначе стекло не с чем сравнивать, пока крутишь.
Future<void> _pickTrValue({
  required BuildContext context,
  required String title,
  required int value,
  required int max,
  required String unit,
  required ValueChanged<int> onChanged,
}) async {
  var current = value;
  await showBloomSheetChild<void>(
    context: context,
    header: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    ),
    child: StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$current$unit',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Slider(
              value: current.toDouble(),
              max: max.toDouble(),
              divisions: max,
              onChanged: (v) {
                setState(() => current = v.round());
                onChanged(current);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Вид таб-бара ───────────────────────────────────────────────────────────

String _navStyleLabel(AppLocalizations l, NavBarStyle style) => switch (style) {
  NavBarStyle.bar => l.apNavBarPlain,
  NavBarStyle.rounded => l.apNavBarRounded,
  NavBarStyle.dome => l.apNavBarDome,
  NavBarStyle.floating => l.apNavBarFloating,
  NavBarStyle.pill => l.apNavBarPill,
};

/// Шторка выбора вида таб-бара: плитки в два столбца, последняя в нечётном
/// ряду остаётся одна.
///
/// Сетка живёт в шторке, а не на самой странице: у «Интерфейса» уже есть
/// строка «Тема» с таким же поведением, и второй развёрнутый блок выбора
/// раздул бы экран вдвое. Плитки в два столбца, а не в строку из четырёх (как
/// варианты анимации в настройках плеера): там подписи в одно короткое слово,
/// а «Скруглённый» на четверти ширины телефона стал бы многоточием.
///
/// Выбор применяется и закрывает шторку: сам бар она собой и закрывает, так
/// что смотреть на результат из-под неё всё равно нечем.
Future<void> _pickNavStyle(BuildContext context, WidgetRef ref) async {
  final current = ref.read(settingsProvider).navStyle;
  final width = MediaQuery.of(context).size.width;
  // 12 полей шторки с двух сторон + 12 зазора между столбцами.
  final cardWidth = (width - 12 * 2 - 12) / 2;

  final picked = await showBloomSheetChild<NavBarStyle>(
    context: context,
    header: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Text(
          context.l.apNavBarRow,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    ),
    // Закрывать шторку надо ЕЁ контекстом, а не контекстом страницы: шторка
    // живёт в корневом навигаторе, а страница — во вложенном (ветка таба), и
    // `pop` со страничным контекстом закрыл бы сами «Настройки».
    child: Builder(
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final style in NavBarStyle.values)
              _NavStyleCard(
                style: style,
                width: cardWidth,
                active: style == current,
                onTap: () => Navigator.of(sheetContext).pop(style),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked != null) ref.read(settingsProvider.notifier).setNavStyle(picked);
}

class _NavStyleCard extends StatelessWidget {
  const _NavStyleCard({
    required this.style,
    required this.width,
    required this.active,
    required this.onTap,
  });

  final NavBarStyle style;
  final double width;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: t.pill,
          borderRadius: BorderRadius.circular(t.radius * 0.75),
          // Рамка есть всегда, просто у невыбранной прозрачная: иначе
          // выбранная плитка распухала бы на полтора пикселя и ряд дёргался.
          border: Border.all(
            color: active ? t.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 100 / 64,
              child: CustomPaint(
                painter: _NavStyleGlyph(
                  style: style,
                  screen: t.bg,
                  frame: t.ovlLine2,
                  ink: active ? t.accent : t.text2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _navStyleLabel(context.l, style),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: active ? t.text : t.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Макет экрана с баром внизу: рамка телефона, три полоски списка и сама
/// панель в том виде, который выберут. Рисуем кодом, а не четырьмя SVG, — те
/// же прямоугольники, что и в самом каркасе.
class _NavStyleGlyph extends CustomPainter {
  const _NavStyleGlyph({
    required this.style,
    required this.screen,
    required this.frame,
    required this.ink,
  });

  final NavBarStyle style;

  /// Заливка «экрана» — фон темы: по нему видно, как панель на нём лежит.
  final Color screen;
  final Color frame;

  /// Цвет панели и иконок: акцент у выбранной плитки, приглушённый у прочих.
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 100×64 и масштабируем разом — как значки вариантов в
    // настройках плеера.
    canvas.save();
    canvas.scale(size.width / 100, size.height / 64);

    final body = RRect.fromLTRBR(0, 0, 100, 64, const Radius.circular(8));
    final paint = Paint()..color = screen;
    canvas.drawRRect(body, paint);

    canvas.save();
    // Всё внутри режется рамкой телефона: нижние углы панели скругляются сами,
    // а панель «во всю ширину» упирается ровно в края.
    canvas.clipRRect(body);

    // Три полоски списка: разной длины, чтобы читались как строки, а не как
    // полосы.
    paint.color = ink.withValues(alpha: 0.22);
    const widths = [64.0, 76.0, 52.0];
    for (var i = 0; i < widths.length; i++) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          10,
          10 + i * 11,
          10 + widths[i],
          15 + i * 11,
          const Radius.circular(2.5),
        ),
        paint,
      );
    }

    final panel = switch (style) {
      // Прижат к низу: верх ровный, низ скруглит рамка.
      NavBarStyle.bar => RRect.fromLTRBR(0, 46, 100, 66, Radius.zero),
      NavBarStyle.rounded => RRect.fromLTRBAndCorners(
        0,
        44,
        100,
        66,
        topLeft: const Radius.circular(9),
        topRight: const Radius.circular(9),
      ),
      // Те же углы вдвое — ровно во столько же раз купол круче скруглённого и
      // в самом баре.
      NavBarStyle.dome => RRect.fromLTRBAndCorners(
        0,
        44,
        100,
        66,
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
      ),
      // Выше прижатых по высоте панели — ровно как в самом баре
      // (`kNavBarFloatHeight` против `kNavBarHeight`).
      NavBarStyle.floating => RRect.fromLTRBR(
        7,
        41,
        93,
        59,
        const Radius.circular(5),
      ),
      // Та же панель, что у плавающей, — разница только в углах: у капсулы
      // они в половину высоты.
      NavBarStyle.pill => RRect.fromLTRBR(
        7,
        41,
        93,
        59,
        const Radius.circular(9),
      ),
    };
    canvas.drawRRect(panel, paint..color = ink.withValues(alpha: 0.26));

    // Тонкая линия сверху — единственное, чем обычный бар отбит от списка.
    if (style == NavBarStyle.bar) {
      canvas.drawLine(
        const Offset(0, 46),
        const Offset(100, 46),
        Paint()
          ..color = ink.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }

    // Три иконки — точки по центру панели.
    paint.color = ink;
    final cy = (panel.top + min(panel.bottom, 64)) / 2;
    final half = (panel.right - panel.left) / 2 - 6;
    final step = half * 2 / 3;
    final cx = (panel.left + panel.right) / 2;
    for (var i = -1; i <= 1; i++) {
      canvas.drawCircle(Offset(cx + i * step, cy), 2.6, paint);
    }

    canvas.restore();
    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = frame,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NavStyleGlyph old) =>
      old.style != style || old.ink != ink || old.screen != screen;
}

/// Строка настройки внутри группы. Своей плёнки у неё нет: связанные строки
/// стоят одной карточкой ([SettingsGroupCard]), как в корневых «Настройках».
///
/// [onTap] — строка ведёт куда-то (шторка выбора темы); без него это просто
/// место под тоггл или ползунок.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: child,
      ),
    );
  }
}

/// Шторка выбора темы: сетка пресетов в два столбца, ниже — свои темы, отбитые
/// тонкой линией (как `tp-sep` на десктопе). Список пресетов длиннее экрана не
/// бывает, но шторка всё равно скроллится — это делает её оболочка.
Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(settingsProvider.notifier);
  final width = MediaQuery.of(context).size.width;
  // 12 полей шторки с двух сторон + 12 зазора между столбцами.
  final cardWidth = (width - 12 * 2 - 12) / 2;

  await showBloomSheetChild<void>(
    context: context,
    header: Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l.apThemeRow,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          // «+» — как кнопка `tp-add` рядом со строкой темы на ПК.
          _RoundButton(
            icon: SolarIconsOutline.addCircle,
            onTap: () => _createTheme(context, ref),
          ),
        ],
      ),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        // Настройки читаем внутри шторки: тема применяется сразу, а свои темы
        // появляются в ней же — и галочка, и новая карточка должны приезжать,
        // не закрывая шторку.
        final settings = ref.watch(settingsProvider);
        Widget card(ThemePreset preset) => _PresetCard(
          preset: preset,
          width: cardWidth,
          active: preset.id == settings.themeId,
          onTap: () => controller.setTheme(preset.id),
          onDelete: preset.custom
              ? () => _deleteTheme(context, ref, preset)
              : null,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final p in kThemePresets) card(p)],
              ),
              if (settings.customThemes.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1, color: Colors.white24),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [for (final p in settings.customThemes) card(p)],
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

/// Удалить свою тему. Подтверждение — вторым нажатием на сам крестик (как
/// очистка статистики в профиле), модалки нет.
void _deleteTheme(BuildContext context, WidgetRef ref, ThemePreset preset) {
  ref.read(settingsProvider.notifier).deleteCustomTheme(preset.id);
  showToast(context, context.l.thDeleted);
}

/// Шторка создания своей темы: название, три цвета, «случайные» и «сохранить» —
/// тот же набор, что в десктопном `ThemeCreator`. Созданная тема сразу
/// применяется, поэтому шторка выбора под ней остаётся открытой: видно и
/// карточку, и результат.
Future<void> _createTheme(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final draft = await showBloomSheetChild<_ThemeDraft>(
    context: context,
    header: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Text(
          context.l.thNew,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    ),
    // Отталкиваемся от текущей темы — как на ПК, где создатель открывается с
    // её цветами: чаще всего свою тему крутят именно из неё.
    child: _ThemeCreator(initial: settings.preset),
  );
  if (draft == null || !context.mounted) return;
  final created = ref
      .read(settingsProvider.notifier)
      .createCustomTheme(
        name: draft.name.isEmpty ? context.l.thNameDefault : draft.name,
        bg: draft.bg,
        blockColor: draft.blockColor,
        accent: draft.accent,
      );
  showToast(context, context.l.thCreated(created.name));
}

/// Черновик своей темы: то, с чем закрывается шторка создания.
class _ThemeDraft {
  const _ThemeDraft({
    required this.name,
    required this.bg,
    required this.blockColor,
    required this.accent,
  });

  final String name;
  final Color bg;
  final Color blockColor;
  final Color accent;
}

class _ThemeCreator extends StatefulWidget {
  const _ThemeCreator({required this.initial});

  final ThemePreset initial;

  @override
  State<_ThemeCreator> createState() => _ThemeCreatorState();
}

class _ThemeCreatorState extends State<_ThemeCreator> {
  late final TextEditingController _name = TextEditingController();
  late Color _bg = widget.initial.bg;
  late Color _block = widget.initial.blockColor;
  late Color _accent = widget.initial.accent;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Случайная приятная палитра — порт `randomThemeColors`: тёмный фон, блок
  /// чуть светлее того же тона, акцент — заметно другой тон.
  void _random() {
    final rnd = Random();
    final h = rnd.nextDouble() * 360;
    final bgL = (5 + rnd.nextDouble() * 5) / 100;
    setState(() {
      _bg = HSLColor.fromAHSL(1, h, 0.18, bgL).toColor();
      _block = HSLColor.fromAHSL(1, h, 0.16, bgL + 0.05).toColor();
      _accent = HSLColor.fromAHSL(
        1,
        (h + 20 + rnd.nextDouble() * 320) % 360,
        0.65,
        0.58,
      ).toColor();
    });
  }

  Future<void> _pick(Color current, ValueChanged<Color> apply) async {
    final picked = await showBloomColorPicker(context, current);
    if (picked != null) setState(() => apply(picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final width = MediaQuery.of(context).size.width;
    final preview = ThemePreset(
      id: 'draft',
      name: _name.text.trim().isEmpty
          ? context.l.thNameDefault
          : _name.text.trim(),
      bg: _bg,
      blockColor: _block,
      accent: _accent,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            maxLength: 24,
            cursorColor: t.accent,
            style: theme.titleMedium,
            // Имя видно в превью — перерисовываем на каждый символ.
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: t.pill,
              hintText: context.l.thNameDefault,
              hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.radius * 0.7),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ColorSlot(
                label: context.l.thSlotBg,
                color: _bg,
                onTap: () => _pick(_bg, (c) => _bg = c),
              ),
              const SizedBox(width: 10),
              _ColorSlot(
                label: context.l.thSlotCard,
                color: _block,
                onTap: () => _pick(_block, (c) => _block = c),
              ),
              const SizedBox(width: 10),
              _ColorSlot(
                label: context.l.thSlotAccent,
                color: _accent,
                onTap: () => _pick(_accent, (c) => _accent = c),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Живое превью: та же карточка, что потом встанет в сетку.
          Center(
            child: _PresetCard(
              preset: preview,
              width: width - 40,
              active: false,
              onTap: () {},
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _random,
                  icon: Icon(SolarIconsOutline.magicStick, size: 16),
                  label: Text(
                    context.l.thRandom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.text2),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _ThemeDraft(
                      name: _name.text.trim(),
                      bg: _bg,
                      blockColor: _block,
                      accent: _accent,
                    ),
                  ),
                  child: Text(context.l.commonSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Слот цвета: подпись и широкий сватч под ней — тап открывает пикер.
class _ColorSlot extends StatelessWidget {
  const _ColorSlot({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(t.radius * 0.6),
                border: Border.all(color: t.ovlLine2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Круглая кнопка шапки шторки — «+» у выбора темы.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 22, color: t.text),
        ),
      ),
    );
  }
}

/// Три кружка превью темы — как `Dots` в десктопном `ThemePicker`: фон, блок,
/// акцент. Кружки заходят друг на друга, поэтому у каждого своя обводка цветом
/// подложки, иначе тёмные темы сливаются в одно пятно.
class _ThemeDots extends StatelessWidget {
  const _ThemeDots({required this.preset, this.size = 22, this.ring});

  final ThemePreset preset;
  final double size;

  /// Цвет обводки — подложка, на которой лежат кружки. По умолчанию плёнка
  /// текущей темы: строка настроек лежит на ней.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final preview = preset.tokens();
    final colors = [preview.bg, preview.pill, preview.accent];
    final step = size * 0.68;
    return SizedBox(
      width: step * (colors.length - 1) + size,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: ring ?? t.pill, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Пресет в шторке: карточка, залитая фоном самой темы, с кружками превью
/// сверху и названием снизу. Превью считаем теми же формулами, что и саму
/// тему, — разойтись они не могут.
class _PresetCard extends StatefulWidget {
  const _PresetCard({
    required this.preset,
    required this.width,
    required this.active,
    required this.onTap,
    this.onDelete,
  });

  final ThemePreset preset;
  final double width;
  final bool active;
  final VoidCallback onTap;

  /// Крестик в углу — только у своих тем.
  final VoidCallback? onDelete;

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard> {
  /// Крестик спрашивает вторым нажатием — как очистка статистики в профиле:
  /// модалки на такую мелочь нет ни там, ни на ПК.
  bool _armed = false;

  void _delete() {
    if (!_armed) {
      setState(() => _armed = true);
      // Само остывает — иначе взведённый крестик так и ждёт промаха.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() => _armed = false);
    widget.onDelete!();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final preset = widget.preset;
    final active = widget.active;
    final preview = preset.tokens();
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.width,
        height: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: preview.bg,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(
            color: active ? t.accent : preview.border,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ThemeDots(preset: preset, size: 24, ring: preview.bg),
                const Spacer(),
                if (active)
                  Icon(
                    SolarIconsBold.checkCircle,
                    size: 18,
                    color: preview.accent,
                  ),
                if (widget.onDelete != null)
                  // Своя зона нажатия: крестик мелкий, а мажут по нему пальцем.
                  // Взведённый — красная корзина: без модалки видно, что
                  // следующий тап удалит.
                  GestureDetector(
                    onTap: _delete,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        _armed
                            ? SolarIconsBold.trashBinMinimalistic
                            : SolarIconsOutline.closeCircle,
                        size: 18,
                        color: _armed ? preview.sysFavIco : preview.muted,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              preset.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: preview.text),
            ),
          ],
        ),
      ),
    );
  }
}
