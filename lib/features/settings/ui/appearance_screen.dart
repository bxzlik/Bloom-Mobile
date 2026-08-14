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

import 'dart:math' show Random;

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
import '../../../shared/ui/subpage_header.dart';

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
        Text(context.l.apLanguage, style: theme.labelSmall),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final locale in kLocales) ...[
              if (locale != kLocales.first) const SizedBox(width: 12),
              Expanded(
                child: _LanguageCard(
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
        Text(context.l.apTheme, style: theme.labelSmall),
        const SizedBox(height: 10),
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
        const SizedBox(height: 12),
        // Авто-акцент — тот же тоггл, что в десктопной секции «Интерфейс»:
        // ручного выбора акцента нет ни там, ни здесь.
        _SettingsCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l.apAutoAccent, style: theme.titleMedium),
                    const SizedBox(height: 3),
                    Text(context.l.apAutoAccentSub, style: theme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              BloomSwitch(
                value: settings.autoAccent,
                onChanged: controller.setAutoAccent,
              ),
            ],
          ),
        ),
        // Яркость — отдельной карточкой под тогглом, ровно как на ПК: она
        // нужна, только пока авто-акцент включён.
        if (settings.autoAccent) ...[
          const SizedBox(height: 12),
          _SettingsCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Text(context.l.apAutoAccentLevel, style: theme.titleMedium),
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
        ],
        const SizedBox(height: 12),
        // Бейджи стоят тут же, в блоке темы, и сразу после авто-акцента — тот
        // же порядок, что в десктопной секции «Интерфейс»: настройка про
        // акцент, а не про скругления. Тексты — из `dict.ts`
        // (`settings.interface.accentBadges`).
        _SettingsCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l.apBadgesTitle, style: theme.titleMedium),
                    const SizedBox(height: 3),
                    Text(context.l.apBadgesSubtitle, style: theme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              BloomSwitch(
                value: settings.accentBadges,
                onChanged: controller.setAccentBadges,
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Text(context.l.apCorners, style: theme.labelSmall),
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.pill,
            borderRadius: BorderRadius.circular(t.radius),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(t.radius * 0.72),
                ),
                child: Icon(SolarIconsBold.play, size: 20, color: t.accentText),
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
      ],
    );
  }
}

/// Карточка языка — порт десктопного `.s-lang-card`: флаг, название на самом
/// языке и код в углу у активной.
class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.locale,
    required this.active,
    required this.onTap,
  });

  final Locale locale;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final name = switch (locale.languageCode) {
      'ru' => context.l.apLanguageRu,
      _ => context.l.apLanguageEn,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        decoration: BoxDecoration(
          color: t.pill,
          borderRadius: BorderRadius.circular(t.radius * 0.75),
          border: Border.all(
            color: active ? t.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                CustomPaint(
                  size: const Size(46, 46 * 24 / 36),
                  painter: _FlagPainter(locale.languageCode),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: active ? t.text : t.text2,
                  ),
                ),
              ],
            ),
            if (active)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: t.ovlLine,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    locale.languageCode.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Флаги — те же две картинки, что в `FLAGS` десктопного `InterfaceSection`,
/// с той же сеткой: холст 36×24, у американского 13 полос и кантон в семь из
/// них. Рисуем кодом, а не SVG-файлом: две фигуры проще посчитать, чем тащить
/// ассеты.
class _FlagPainter extends CustomPainter {
  const _FlagPainter(this.code);

  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 36;
    final paint = Paint();
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(2 * k),
    );
    canvas.clipRRect(rect);
    canvas.drawRect(Offset.zero & size, paint..color = const Color(0xFFFFFFFF));

    if (code == 'ru') {
      canvas.drawRect(
        Rect.fromLTWH(0, 8 * k, size.width, 8 * k),
        paint..color = const Color(0xFF0039A6),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 16 * k, size.width, 8 * k),
        paint..color = const Color(0xFFD52B1E),
      );
      return;
    }

    final stripe = 24 / 13 * k;
    paint.color = const Color(0xFFB22234);
    for (var i = 0; i < 13; i += 2) {
      canvas.drawRect(Rect.fromLTWH(0, i * stripe, size.width, stripe), paint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 15.6 * k, stripe * 7),
      paint..color = const Color(0xFF3C3B6E),
    );
    paint.color = const Color(0xFFFFFFFF);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        canvas.drawCircle(
          Offset(
            (1.6 + c * 3.1 + (r.isOdd ? 1.55 : 0)) * k,
            (1.6 + r * 2.9) * k,
          ),
          0.6 * k,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FlagPainter old) => old.code != code;
}

/// Карточка-строка настройки: та же тёмная плёнка, что у групп в «Настройках».
/// [onTap] — строка ведёт куда-то (шторка выбора темы); без него это просто
/// подложка под тоггл или ползунок.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      color: t.pill,
      borderRadius: BorderRadius.circular(t.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: child,
        ),
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
