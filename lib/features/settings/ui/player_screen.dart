/// Настройки плеера — пока одна вкладка десктопного раздела: «Анимации».
///
/// Порт `AnimCards` из `settings/ui/sections/ViewSection.tsx`. Поверхностей у
/// нас две (на ПК их три — там ещё полноэкранный режим), у каждой своя
/// карточка: коробки разного размера, и одна настройка на обеих заставляла бы
/// выбирать между «красиво в плеере» и «не рябит над таб-баром».
///
/// Внутри карточки две независимые строки — обложка и подпись: слайд обложки
/// при спокойном затухании текста (и наоборот) — рабочее сочетание, а не
/// недонастройка.
///
/// Сами кнопки выбора на странице НЕ стоят: развёрнутыми тремя блоками они
/// занимали два экрана прокрутки. Остались три строки «название — что сейчас
/// выбрано», а варианты открываются нижней шторкой — ровно как «Тема» и «Вид
/// таб-бара» в «Интерфейсе». Шторка от выбора не закрывается: настроек в ней
/// две-три, и они настраиваются подряд.
///
/// Значки вариантов рисуем сами: на ПК это три крошечных SVG (перечёркнутый
/// круг, две плитки рядом, две плитки внахлёст), в шрифте Solar таких нет.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/customization/custom_store.dart';
import '../../../features/lyrics/lyrics_style_store.dart';
import '../../../features/player/mini_style_store.dart';
import '../../../features/player/player_controller.dart';
import '../../../features/player/player_style_store.dart';
import '../../../features/player/player_view_store.dart';
import '../../../features/player/slider_style_store.dart';
import '../../../features/player/track_anim_store.dart';
import '../../../features/player/ui/slider_shapes.dart';
import '../../../features/player/ui/vinyl_disc.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/util/format.dart';

class PlayerSettingsScreen extends ConsumerWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anim = ref.watch(trackAnimProvider);
    final lyrics = ref.watch(lyricsStyleProvider);
    final style = ref.watch(playerStyleProvider);
    final align = ref.watch(titleAlignProvider);
    final slider = ref.watch(sliderStyleProvider);
    final mini = ref.watch(miniStyleProvider);
    final l = context.l;

    return SubPage(
      title: l.setPlayer,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.pvGroupLook.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _Row(
              title: l.pvStyleRow,
              value: _styleLabel(l, style),
              glyph: _StyleGlyph(style: style),
              onTap: () => _openStyle(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupTitle.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _Row(
              title: l.pvTitleAlign,
              value: _alignLabel(l, align),
              glyph: _AlignRowGlyph(align: align),
              onTap: () => _openTitleAlign(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupSlider.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _Row(
              title: l.pvSliderRow,
              value: _sliderLabel(l, slider),
              glyph: _SliderRowGlyph(style: slider),
              onTap: () => _openSlider(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupAnim.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            for (final surface in TrackAnimSurface.values)
              _Row(
                title: _surfaceLabel(l, surface),
                value: _summary([
                  for (final target in TrackAnimTarget.values)
                    _kindLabel(l, anim.of(surface).of(target)),
                ]),
                // Значок — поверхность, а не вид перехода: их в строке два
                // (обложка и подпись), одним значком не показать.
                glyph: Icon(
                  surface == TrackAnimSurface.player
                      ? SolarIconsOutline.maximizeSquare
                      : SolarIconsOutline.minimizeSquare,
                ),
                onTap: () => _openAnim(context, surface),
              ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupLyrics.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _Row(
              title: l.pvLyricsRow,
              value: _summary([
                _modeLabel(l, lyrics.mode),
                _fillLabel(l, lyrics.fill),
                _fxLabel(l, lyrics.fx),
              ]),
              // Строка настраивает три вещи разом — значок общий, про
              // оформление.
              glyph: const Icon(SolarIconsOutline.magicStick),
              onTap: () => _openLyrics(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupMini.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _Row(
              title: l.pvMiniBgRow,
              value: _miniBgLabel(l, mini.bg),
              glyph: Icon(_miniBgIcon(mini.bg)),
              onTap: () => _openMiniBg(context, ref),
            ),
            _Row(
              title: l.pvMiniProgressRow,
              value: _miniProgressSummary(l, mini),
              // Набор: значок общий — про сам прогресс.
              glyph: const Icon(SolarIconsOutline.soundwave),
              onTap: () => _openMiniProgress(context),
            ),
            _Row(
              title: l.pvMiniShapeRow,
              value: _miniShapeLabel(l, mini.shape),
              glyph: Icon(_miniShapeIcon(mini.shape)),
              onTap: () => _openMiniShape(context, ref),
            ),
            _Row(
              title: l.pvMiniRadiusRow,
              value: _miniRadiusLabel(l, mini.radius),
              glyph: Icon(_miniRadiusIcon(mini.radius)),
              onTap: () => _openMiniRadius(context, ref),
            ),
            _Row(
              title: l.pvMiniButtonsRow,
              value: _miniButtonsSummary(l, mini),
              // Набор: значок общий — про кнопки.
              glyph: const Icon(SolarIconsOutline.gamepad),
              onTap: () => _openMiniButtons(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// Подпись строки — выбранное через точку, в том же порядке, в каком настройки
/// идут в шторке.
String _summary(List<String> parts) => parts.join(' · ');

/// Строка настройки: название, под ним выбранное, справа — ЗНАЧОК ВЫБРАННОГО.
///
/// Своей плёнки у строки нет — она живёт внутри [SettingsGroupCard], одного на
/// всю группу: связанные настройки стоят одной карточкой, как в корневых
/// «Настройках».
///
/// Шеврона нет: строка и так открывается вся целиком, а стрелка занимала место
/// справа, ничего не сообщая. Вместо неё — тот же значок, что стоит у выбранного
/// варианта в шторке: выбор видно, не открывая её. У строк, которые настраивают
/// НАБОР («Индикаторы прогресса», «Кнопки управления») или сразу несколько
/// настроек («Оформление» текста), значок один и общий — про что строка, а не
/// про первый включённый пункт.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.value,
    required this.glyph,
    required this.onTap,
  });

  final String title;
  final String value;

  /// Значок справа. Рисуется цветом [BloomTokens.iconFg] — свой цвет задавать
  /// не нужно: значки-картинки берут его из [IconTheme].
  final Widget glyph;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Ярче общего `bodySmall`: выбранное — часть строки, а не
                    // сноска. `text2` держит его ниже названия на `text`.
                    style: theme.bodySmall?.copyWith(color: t.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Коробка одна на все значки: они разной ширины (полоска слайдера
            // шире круга пластинки), а стоять в колонке должны ровно.
            SizedBox(
              width: 28,
              height: 24,
              child: IconTheme(
                data: IconThemeData(color: t.iconFg, size: 21),
                child: Center(child: glyph),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Шапка шторки: название и, если есть, пояснение под ним — то самое, что
/// раньше стояло подписью карточки на странице.
Widget _sheetHeader(BuildContext context, String title, [String? subtitle]) {
  final theme = Theme.of(context).textTheme;
  return Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle, style: theme.bodySmall),
          ],
        ],
      ),
    ),
  );
}

/// Шторка одной поверхности: обложка и подпись — двумя блоками.
///
/// Настройки читаются ВНУТРИ шторки (`Consumer`): выбор применяется на месте и
/// закрывать её незачем — вторая строка настраивается тут же.
Future<void> _openAnim(BuildContext context, TrackAnimSurface surface) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: _sheetHeader(
      context,
      _surfaceLabel(l, surface),
      _surfaceSub(l, surface),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final cfg = ref.watch(trackAnimProvider).of(surface);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final target in TrackAnimTarget.values)
              _Section(
                icon: target == TrackAnimTarget.cover
                    ? SolarIconsOutline.gallery
                    : SolarIconsOutline.text,
                title: _targetLabel(l, target),
                child: _KindRow(
                  surface: surface,
                  target: target,
                  value: cfg.of(target),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Шторка стиля плеера — порт карточки `settings.view.style` с ПК. Вариантов
/// два из четырёх: десктопные «Большой» и «Кино» — раскладки на широкое окно.
///
/// Устроена как шторка слайдера: сверху живое превью, под ним строки вариантов
/// с подписью — разница между стилями чисто картиночная, словами её не
/// объяснить. От выбора шторка НЕ закрывается: варианты для того и смотрят на
/// превью, что квадрат на глазах скругляется в диск и начинает крутиться.
/// Шапки нет по той же причине, что у слайдера, — она повторяла бы строку, с
/// которой в шторку пришли, и съедала высоту у превью.
Future<void> _openStyle(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(playerStyleProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StylePreview(style: current),
            for (final style in PlayerStyle.values)
              _StyleTile(
                style: style,
                selected: style == current,
                onTap: () =>
                    ref.read(playerStyleProvider.notifier).setStyle(style),
              ),
          ],
        );
      },
    ),
  );
}

/// Живое превью стиля: мини-плеер с настоящей обложкой играющего трека.
///
/// Обложка та же, что в плеере (своя из «Кастомизации» важнее обложки трека), и
/// диск крутится тем же [VinylSpin] — картинка в настройках не должна
/// разойтись с настоящей. Ничего не играет — на её месте обычная заглушка.
class _StylePreview extends ConsumerWidget {
  const _StylePreview({required this.style});

  final PlayerStyle style;

  /// Сторона обложки в превью.
  static const double side = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final vinyl = style.isVinyl;
    final url =
        ref.watch(customSrcProvider(CustomCtx.cover)) ??
        ref.watch(playbackProvider.select((s) => s.track?.cover));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          // Та же заливка, что у блоков шторки.
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Column(
          children: [
            SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  // Квадрат скругляется в круг НА ГЛАЗАХ — по этой доле и видно,
                  // что настройка сделала. Радиус обложки в плеере (20) на
                  // превью взят долей стороны, иначе маленькая картинка
                  // выглядела бы заметно острее настоящей.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: vinyl ? 1 : 0),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    builder: (context, k, child) => ClipRRect(
                      borderRadius: BorderRadius.circular(
                        side * (0.11 + 0.39 * k),
                      ),
                      child: child,
                    ),
                    child: VinylSpin(
                      enabled: vinyl,
                      // В настройках диск крутится ВСЕГДА, пока стиль выбран:
                      // звука тут нет, а замерший круг от квадрата отличается
                      // только формой — половина смысла режима осталась бы за
                      // кадром.
                      spinning: true,
                      child: Cover(url: url, size: side, radius: 0),
                    ),
                  ),
                  if (vinyl)
                    Positioned.fill(
                      child: Center(
                        child: VinylLabel(size: side * VinylLabel.share),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Название и артист — плашками, а не текстом: превью показывает
            // раскладку, а не содержимое, и живой заголовок тянул бы на себя
            // всё внимание.
            _Bar(width: 104, height: 9, color: t.text.withValues(alpha: 0.55)),
            const SizedBox(height: 8),
            _Bar(width: 68, height: 7, color: t.text.withValues(alpha: 0.24)),
          ],
        ),
      ),
    );
  }
}

/// Плашка на месте строки текста в превью.
class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}

/// Строка выбора стиля — та же, что у выравнивания заголовка ([_AlignTile]):
/// значок в кружке у выбранного, название, подпись под ним и галочка справа.
/// Отличие одно — от тапа шторка не закрывается, см. [_openStyle].
class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final PlayerStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final l = context.l;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        color: sheetPanelColor(context),
        borderRadius: BorderRadius.circular(t.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius),
              border: Border.all(
                color: selected ? t.ovlLine2 : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _StyleTileGlyph(style: style, selected: selected),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _styleLabel(l, style),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _styleSub(l, style),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (selected)
                  Icon(SolarIconsBold.checkCircle, size: 20, color: t.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок варианта: у выбранного — в кружке, как у выравнивания заголовка.
class _StyleTileGlyph extends StatelessWidget {
  const _StyleTileGlyph({required this.style, required this.selected});

  final PlayerStyle style;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final glyph = _StyleGlyph(style: style);
    if (!selected) return SizedBox(width: 38, child: Center(child: glyph));
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: glyph,
    );
  }
}

/// Шторка выравнивания заголовка — порт карточки `settings.view.titleAlign` с
/// ПК.
///
/// Вариантов три и настройка одна: строки крупные, во всю ширину, с подписью и
/// галочкой — как в шторке «Свайпов», а не тремя кнопками в ряд. И закрывается
/// от выбора: настраивать в ней больше нечего.
///
/// Шапки нет: строка, из которой сюда пришли, осталась видна над шторкой, и
/// подписывать выбор второй раз незачем.
Future<void> _openTitleAlign(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(titleAlignProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final align in TitleAlign.values)
              _AlignTile(
                align: align,
                selected: align == current,
                onTap: () => ref.read(titleAlignProvider.notifier).set(align),
              ),
          ],
        );
      },
    ),
  );
}

/// Строка выбора выравнивания. Своя, а не [SheetAction]: строка крупнее пункта
/// шторки, под названием стоит подпись, а у выбранной — кружок под значком и
/// галочка справа.
class _AlignTile extends StatelessWidget {
  const _AlignTile({
    required this.align,
    required this.selected,
    required this.onTap,
  });

  final TitleAlign align;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final l = context.l;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        // Та же заливка, что у блоков шторки ([SheetPanel]).
        color: sheetPanelColor(context),
        borderRadius: BorderRadius.circular(t.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius),
              border: Border.all(
                color: selected ? t.ovlLine2 : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _TileGlyph(align: align, selected: selected),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _alignLabel(l, align),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _alignSub(l, align),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (selected)
                  Icon(SolarIconsBold.checkCircle, size: 20, color: t.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок варианта: у выбранного — в кружке, как в шторке «Свайпов».
class _TileGlyph extends StatelessWidget {
  const _TileGlyph({required this.align, required this.selected});

  final TitleAlign align;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final glyph = CustomPaint(
      size: const Size(22, 22),
      painter: _AlignGlyph(align: align, color: context.bloom.text),
    );
    if (!selected) return SizedBox(width: 38, child: Center(child: glyph));
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: glyph,
    );
  }
}

/// Тот же значок для строки настройки: без кружка и цветом [IconTheme] — в
/// строке он стоит наравне с обычными значками Solar.
class _AlignRowGlyph extends StatelessWidget {
  const _AlignRowGlyph({required this.align});

  final TitleAlign align;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(21, 21),
    painter: _AlignGlyph(
      align: align,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

/// Три строки разной длины, сдвинутые к своему краю, — те же SVG, что в
/// десктопной карточке выравнивания. В Solar такой тройки нет: `alignLeft`
/// оттуда — направляющая с планкой, а не текст.
class _AlignGlyph extends CustomPainter {
  const _AlignGlyph({required this.align, required this.color});

  final TitleAlign align;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 24×24, как исходные SVG, и масштабируем разом.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Первая строка всегда во всю ширину — двигаются только короткие, иначе
    // разница между вариантами не читается в 22 px.
    canvas.drawLine(const Offset(3, 6), const Offset(21, 6), stroke);
    final (mid, last) = switch (align) {
      TitleAlign.left => ((3.0, 15.0), (3.0, 18.0)),
      TitleAlign.center => ((6.0, 18.0), (4.0, 20.0)),
      TitleAlign.right => ((9.0, 21.0), (6.0, 21.0)),
    };
    canvas.drawLine(Offset(mid.$1, 12), Offset(mid.$2, 12), stroke);
    canvas.drawLine(Offset(last.$1, 18), Offset(last.$2, 18), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AlignGlyph old) =>
      old.align != align || old.color != color;
}

String _alignLabel(AppLocalizations l, TitleAlign align) => switch (align) {
  TitleAlign.left => l.pvTitleAlignLeft,
  TitleAlign.center => l.pvTitleAlignCenter,
  TitleAlign.right => l.pvTitleAlignRight,
};

String _alignSub(AppLocalizations l, TitleAlign align) => switch (align) {
  TitleAlign.left => l.pvTitleAlignLeftSub,
  TitleAlign.center => l.pvTitleAlignCenterSub,
  TitleAlign.right => l.pvTitleAlignRightSub,
};

/// Шторка типа слайдера — порт карточки `settings.view.slider` с ПК.
///
/// Сверху живая полоса прогресса, под ней строки вариантов: разница между
/// типами — только в том, как выглядит сама полоса, и подписью «Волновой» её не
/// объяснить. От выбора шторка НЕ закрывается — ради этого превью и стоит:
/// варианты перебираются подряд, глядя на него.
///
/// Шапки у этой шторки нет — в отличие от соседних. Название и пояснение
/// повторяли строку, с которой в неё пришли, и съедали высоту у того, ради чего
/// она открыта: превью и вариантов. Что настраивается — видно по самой полосе.
Future<void> _openSlider(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(sliderStyleProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SliderPreview(style: current),
            for (final style in SliderStyle.values)
              _SliderTile(
                style: style,
                selected: style == current,
                onTap: () => ref.read(sliderStyleProvider.notifier).set(style),
              ),
          ],
        );
      },
    ),
  );
}

/// Живая полоса прогресса в шторке: та же [bloomSliderTheme], что в плеере, —
/// иначе картинка в настройках со временем разошлась бы с настоящей.
///
/// Полосу можно тянуть: у половины типов вся разница в пуговке и в том, как она
/// разрезает дорожку, и на замершей картинке этого не видно. Время слева бежит
/// за пальцем, справа стоит длительность демо-трека.
class _SliderPreview extends StatefulWidget {
  const _SliderPreview({required this.style});

  final SliderStyle style;

  /// Демо-трек: 3:45 с позицией на 1:24 (мс).
  static const int total = 225000;
  static const int start = 84000;

  /// Зерно волны — постоянное: узор в настройках не должен меняться от
  /// открытия к открытию (в плеере он свой на каждый трек).
  static const int waveSeed = 42;

  @override
  State<_SliderPreview> createState() => _SliderPreviewState();
}

class _SliderPreviewState extends State<_SliderPreview> {
  double _value = _SliderPreview.start.toDouble();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        decoration: BoxDecoration(
          // Та же заливка, что у блоков шторки.
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Column(
          children: [
            SizedBox(
              // Выше плеерной ловушки (там 29: дорожка 5 плюс по 12 воздуха) —
              // это главное, ради чего шторка открыта, и полоса в ней должна
              // читаться крупно, а не как строка настройки.
              height: 44,
              child: SliderTheme(
                data: bloomSliderTheme(
                  SliderTheme.of(context),
                  style: widget.style,
                  tokens: t,
                  waveSeed: _SliderPreview.waveSeed,
                ),
                child: Slider(
                  value: _value,
                  max: _SliderPreview.total.toDouble(),
                  onChanged: (v) => setState(() => _value = v),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    mmss(Duration(milliseconds: _value.round())),
                    style: theme.bodyMedium,
                  ),
                  Text(
                    mmss(const Duration(milliseconds: _SliderPreview.total)),
                    style: theme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка выбора типа слайдера. Устроена как [_AlignTile] (значок в кружке у
/// выбранного, галочка справа), но без подписи под названием: типов четыре, и
/// вторая строка в каждом растянула бы шторку на пол-экрана. Что они значат,
/// показывает превью сверху.
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final SliderStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        color: sheetPanelColor(context),
        borderRadius: BorderRadius.circular(t.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            // Выше строки выравнивания заголовка (там 14 при двух строках
            // текста): здесь строка одна, и на её высоте кнопка выходила
            // приплюснутой.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius),
              border: Border.all(
                color: selected ? t.ovlLine2 : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _SliderTileGlyph(style: style, selected: selected),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _sliderLabel(context.l, style),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleMedium?.copyWith(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                if (selected)
                  Icon(SolarIconsBold.checkCircle, size: 22, color: t.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок варианта: у выбранного — в кружке, как у выравнивания заголовка.
class _SliderTileGlyph extends StatelessWidget {
  const _SliderTileGlyph({required this.style, required this.selected});

  final SliderStyle style;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final glyph = CustomPaint(
      // Пропорции десктопной сетки 44×10 — в 28 px значок читается как
      // полоска с ползунком, а не как чёрточка.
      size: const Size(28, 6.4),
      painter: _SliderGlyph(style: style, color: context.bloom.text),
    );
    // Коробка одна и та же с кружком и без него: высоту строки задаёт самый
    // высокий её элемент, и значок без заданной высоты (а это высота самой
    // картинки, 6 px) делал невыбранные строки ниже выбранной.
    if (!selected) {
      return SizedBox(width: 44, height: 44, child: Center(child: glyph));
    }
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: glyph,
    );
  }
}

/// Тот же значок для строки настройки. Уже, чем в шторке (26 против 28): в
/// строке он стоит в одной колонке со значками-иконками, и полоса во всю их
/// коробку выглядела бы рядом с ними линейкой.
class _SliderRowGlyph extends StatelessWidget {
  const _SliderRowGlyph({required this.style});

  final SliderStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(26, 6),
    painter: _SliderGlyph(
      style: style,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

/// Четыре крошечных SVG из десктопной карточки `settings.view.slider`: полоса с
/// заливкой, волосяная полоса с кружком, два сегмента с каплей и столбики.
class _SliderGlyph extends CustomPainter {
  const _SliderGlyph({required this.style, required this.color});

  final SliderStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 44×10, как исходные SVG, и масштабируем разом.
    canvas.save();
    canvas.scale(size.width / 44, size.height / 10);
    final fill = Paint()..color = color;
    // Незалитая часть — та же треть яркости, что у десктопного `opacity={0.3}`.
    final rest = Paint()..color = color.withValues(alpha: 0.3);

    void bar(double x, double y, double w, double h, Paint paint) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(math.min(1, h / 2)),
          ),
          paint,
        );

    switch (style) {
      case SliderStyle.standard:
        bar(0, 4, 44, 2, rest);
        bar(0, 4, 22, 2, fill);
      case SliderStyle.thin:
        bar(0, 4.5, 44, 1, rest);
        bar(0, 4.5, 22, 1, fill);
        canvas.drawCircle(const Offset(22, 5), 2.5, fill);
      case SliderStyle.ios:
        bar(0, 4, 20, 2, fill);
        bar(24, 4, 20, 2, rest);
        bar(21, 1, 2, 8, fill);
      case SliderStyle.wave:
        // Пятнадцать столбиков с шагом 3: семь залитых, остальные тихие.
        const List<double> heights = [
          4, 6, 3, 8, 5, 7, 4, 6, 3, 7, 5, 4, 8, 3, 5, //
        ];
        for (var i = 0; i < heights.length; i++) {
          final h = heights[i];
          bar(i * 3, (10 - h) / 2, 2, h, i < 7 ? fill : rest);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SliderGlyph old) =>
      old.style != style || old.color != color;
}

String _sliderLabel(AppLocalizations l, SliderStyle style) => switch (style) {
  SliderStyle.standard => l.pvSliderStandard,
  SliderStyle.thin => l.pvSliderThin,
  // Название платформы не переводится — на ПК оно тоже вписано прямо в кнопку.
  SliderStyle.ios => 'iOS',
  SliderStyle.wave => l.pvSliderWave,
};

/// Шторка оформления текста песни: вид, заливка и эффект — порт десктопной
/// карточки `settings.view.lyricsStyle` (там таких три, по одной на
/// поверхность; у нас поверхность одна — полноэкранный плеер).
Future<void> _openLyrics(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: _sheetHeader(context, l.pvGroupLyrics),
    child: Consumer(
      builder: (context, ref, _) {
        final style = ref.watch(lyricsStyleProvider);
        final ctrl = ref.read(lyricsStyleProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Section(
              icon: SolarIconsOutline.gallery,
              title: l.pvLyricsMode,
              subtitle: l.pvLyricsModeSub,
              // Вид — две крупные кнопки со своими значками: разница между ними
              // чисто картиночная, одними подписями её не объяснить.
              child: Row(
                children: [
                  for (final mode in LyricsMode.values) ...[
                    if (mode != LyricsMode.values.first)
                      const SizedBox(width: 8),
                    Expanded(
                      child: _Choice(
                        label: _modeLabel(l, mode),
                        active: style.mode == mode,
                        glyph: _ModeGlyph(mode: mode),
                        onTap: () => ctrl.setMode(mode),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _Section(
              icon: SolarIconsOutline.text,
              title: l.pvLyricsFill,
              subtitle: l.pvLyricsFillSub,
              // Заливка и эффект — по четыре варианта: в один ряд на телефоне
              // они не встают, поэтому идут плиткой 2×2.
              child: _Chips(
                labels: [for (final v in LyricsFill.values) _fillLabel(l, v)],
                index: LyricsFill.values.indexOf(style.fill),
                onTap: (i) => ctrl.setFill(LyricsFill.values[i]),
              ),
            ),
            _Section(
              icon: SolarIconsOutline.magicStick,
              title: l.pvLyricsFx,
              subtitle: l.pvLyricsFxSub,
              child: _Chips(
                labels: [for (final v in LyricsFx.values) _fxLabel(l, v)],
                index: LyricsFx.values.indexOf(style.fx),
                onTap: (i) => ctrl.setFx(LyricsFx.values[i]),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Одна настройка в шторке: блок с названием, пояснением и кнопками. Блок —
/// [SheetPanel], а не своя коробка: у шторки своя заливка, и токен-плёнка
/// страницы в ней смотрится дырой.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SheetPanel(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Sub(icon: icon, title: title, strong: true),
              if (subtitle case final text?) ...[
                const SizedBox(height: 3),
                Text(text, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

String _styleLabel(AppLocalizations l, PlayerStyle style) => switch (style) {
  PlayerStyle.standard => l.pvStyleStandard,
  PlayerStyle.vinyl => l.pvStyleVinyl,
};

String _styleSub(AppLocalizations l, PlayerStyle style) => switch (style) {
  PlayerStyle.standard => l.pvStyleStandardSub,
  PlayerStyle.vinyl => l.pvStyleVinylSub,
};

String _modeLabel(AppLocalizations l, LyricsMode mode) => switch (mode) {
  LyricsMode.overlay => l.pvLyricsModeOverlay,
  LyricsMode.replace => l.pvLyricsModeReplace,
};

String _fillLabel(AppLocalizations l, LyricsFill fill) => switch (fill) {
  LyricsFill.line => l.pvLyricsFillLine,
  LyricsFill.word => l.pvLyricsFillWord,
  LyricsFill.letter => l.pvLyricsFillLetter,
  LyricsFill.wipe => l.pvLyricsFillWipe,
};

String _fxLabel(AppLocalizations l, LyricsFx fx) => switch (fx) {
  LyricsFx.none => l.pvLyricsFxNone,
  LyricsFx.fade => l.pvLyricsFxFade,
  LyricsFx.glow => l.pvLyricsFxGlow,
  LyricsFx.spring => l.pvLyricsFxSpring,
};

/// Подзаголовок строки настройки — значок с подписью.
///
/// [strong] — блок в шторке: там эта подпись главная в блоке, а не мелкая
/// метка под названием карточки.
class _Sub extends StatelessWidget {
  const _Sub({required this.icon, required this.title, this.strong = false});

  final IconData icon;
  final String title;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(
          icon,
          size: strong ? 16 : 14,
          color: strong ? context.bloom.text : context.bloom.muted,
        ),
        const SizedBox(width: 6),
        Text(title, style: strong ? theme.titleMedium : theme.bodySmall),
      ],
    );
  }
}

/// Ряд из четырёх вариантов плиткой 2×2.
class _Chips extends StatelessWidget {
  const _Chips({
    required this.labels,
    required this.index,
    required this.onTap,
  });

  final List<String> labels;
  final int index;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < labels.length; i++)
              SizedBox(
                width: width,
                child: _Choice(
                  label: labels[i],
                  active: i == index,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Кнопка варианта: та же плёнка, рамка и акцент, что у выбора анимации.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.active,
    required this.onTap,
    this.glyph,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Картинка над подписью. `null` — вариант объясняется одной подписью.
  final Widget? glyph;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = active ? t.accent : t.iconFg;
    return Material(
      color: active ? t.accent.withValues(alpha: 0.14) : t.ovlBg,
      borderRadius: BorderRadius.circular(t.radius * 0.8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: glyph == null ? 10 : 12),
          decoration: BoxDecoration(
            border: Border.all(color: active ? t.accent : t.ovlLine),
            borderRadius: BorderRadius.circular(t.radius * 0.8),
          ),
          child: Column(
            children: [
              if (glyph != null) ...[
                IconTheme(
                  data: IconThemeData(color: color),
                  child: glyph!,
                ),
                const SizedBox(height: 6),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
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

/// Значок стиля плеера — те же два SVG, что в десктопном `ViewSection`: две
/// плитки рядом у обычного, круг в круге у пластинки.
class _StyleGlyph extends StatelessWidget {
  const _StyleGlyph({required this.style});

  final PlayerStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 24),
    painter: _StylePainter(
      style: style,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

class _StylePainter extends CustomPainter {
  const _StylePainter({required this.style, required this.color});

  final PlayerStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (style) {
      // Две плитки рядом: широкая слева, узкая справа.
      case PlayerStyle.standard:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 3, 11, 21, const Radius.circular(1)),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(14, 3, 21, 21, const Radius.circular(1)),
          stroke,
        );
      // Диск с этикеткой.
      case PlayerStyle.vinyl:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawCircle(const Offset(12, 12), 3, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StylePainter old) =>
      old.style != style || old.color != color;
}

/// Значок вида: слева квадрат обложки со строками поверх, справа — одни
/// строки. В Solar таких картинок нет, рисуем сами, как и значки анимации.
class _ModeGlyph extends StatelessWidget {
  const _ModeGlyph({required this.mode});

  final LyricsMode mode;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(28, 24),
    painter: _ModePainter(
      mode: mode,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

class _ModePainter extends CustomPainter {
  const _ModePainter({required this.mode, required this.color});

  final LyricsMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 24);
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(
        alpha: mode == LyricsMode.overlay ? 0.38 : 0.9,
      );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (mode == LyricsMode.overlay) {
      // Рамка обложки, а по ней — строки текста.
      canvas.drawRRect(
        RRect.fromLTRBR(4, 3, 24, 21, const Radius.circular(3)),
        frame,
      );
      canvas.drawLine(const Offset(8, 9), const Offset(20, 9), line);
      canvas.drawLine(const Offset(8, 13), const Offset(17, 13), line);
      canvas.drawLine(const Offset(8, 17), const Offset(19, 17), line);
    } else {
      // Обложки нет — одни строки во всю ширину.
      canvas.drawLine(const Offset(4, 6), const Offset(24, 6), line);
      canvas.drawLine(const Offset(4, 11), const Offset(20, 11), line);
      canvas.drawLine(const Offset(4, 16), const Offset(23, 16), line);
      canvas.drawLine(const Offset(4, 21), const Offset(15, 21), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ModePainter old) =>
      old.mode != mode || old.color != color;
}

String _surfaceLabel(AppLocalizations l, TrackAnimSurface surface) =>
    switch (surface) {
      TrackAnimSurface.player => l.pvAnimPlayer,
      TrackAnimSurface.mini => l.pvAnimMini,
    };

String _surfaceSub(AppLocalizations l, TrackAnimSurface surface) =>
    switch (surface) {
      TrackAnimSurface.player => l.pvAnimPlayerSub,
      TrackAnimSurface.mini => l.pvAnimMiniSub,
    };

String _targetLabel(AppLocalizations l, TrackAnimTarget target) =>
    switch (target) {
      TrackAnimTarget.cover => l.pvAnimCover,
      TrackAnimTarget.text => l.pvAnimText,
    };

String _kindLabel(AppLocalizations l, TrackAnimKind kind) => switch (kind) {
  TrackAnimKind.none => l.pvAnimNone,
  TrackAnimKind.slide => l.pvAnimSlide,
  TrackAnimKind.fade => l.pvAnimFade,
};

/// Три варианта в ряд — порт десктопного `s-opt-row`.
class _KindRow extends ConsumerWidget {
  const _KindRow({
    required this.surface,
    required this.target,
    required this.value,
  });

  final TrackAnimSurface surface;
  final TrackAnimTarget target;
  final TrackAnimKind value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        for (final kind in TrackAnimKind.values) ...[
          if (kind != TrackAnimKind.values.first) const SizedBox(width: 8),
          Expanded(
            child: _KindButton(
              kind: kind,
              active: kind == value,
              onTap: () => ref
                  .read(trackAnimProvider.notifier)
                  .setKind(surface, target, kind),
            ),
          ),
        ],
      ],
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
    required this.kind,
    required this.active,
    required this.onTap,
  });

  final TrackAnimKind kind;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = active ? t.accent : t.iconFg;
    return Material(
      color: active ? t.accent.withValues(alpha: 0.14) : t.ovlBg,
      borderRadius: BorderRadius.circular(t.radius * 0.8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: active ? t.accent : t.ovlLine),
            borderRadius: BorderRadius.circular(t.radius * 0.8),
          ),
          child: Column(
            children: [
              CustomPaint(
                size: const Size(24, 24),
                painter: _KindGlyph(kind: kind, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                _kindLabel(context.l, kind),
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

/// Значок варианта — те же три картинки, что в десктопной строке выбора.
class _KindGlyph extends CustomPainter {
  const _KindGlyph({required this.kind, required this.color});

  final TrackAnimKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 24×24, как исходные SVG, и масштабируем разом.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final faded = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.38);

    switch (kind) {
      // Перечёркнутый круг.
      case TrackAnimKind.none:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawLine(const Offset(6, 18), const Offset(18, 6), stroke);
      // Две плитки рядом: приезжающая сплошная, уезжающая тихая.
      case TrackAnimKind.slide:
        canvas.drawRRect(
          RRect.fromLTRBR(2, 6, 11, 18, const Radius.circular(1.5)),
          faded,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(13, 6, 22, 18, const Radius.circular(1.5)),
          stroke,
        );
        canvas.drawLine(const Offset(9, 12), const Offset(15, 12), faded);
      // Две плитки внахлёст.
      case TrackAnimKind.fade:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 6, 15, 18, const Radius.circular(1.5)),
          faded,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(9, 6, 21, 18, const Radius.circular(1.5)),
          stroke,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KindGlyph old) => old.kind != kind || old.color != color;
}

// ── Мини-плеер ──────────────────────────────────────────────────────────────
// Четыре настройки карточки над таб-баром (десктопные `mp*`): фон, индикаторы
// прогресса, форма обложки, скругление углов. Варианты — списком в шторке, а не
// плитками: подписи тут длинные («Кольцо на обложке»), в четверть ширины
// телефона они превращаются в многоточие.

String _miniBgLabel(AppLocalizations l, MiniBg bg) => switch (bg) {
  MiniBg.theme => l.pvMiniBgTheme,
  MiniBg.coverColor => l.pvMiniBgCoverColor,
  MiniBg.cover => l.pvMiniBgCover,
};

IconData _miniBgIcon(MiniBg bg) => switch (bg) {
  MiniBg.theme => SolarIconsOutline.paintRoller,
  MiniBg.coverColor => SolarIconsOutline.palette,
  MiniBg.cover => SolarIconsOutline.gallery,
};

String _miniShapeLabel(AppLocalizations l, MiniCoverShape shape) =>
    switch (shape) {
      MiniCoverShape.rounded => l.pvMiniShapeRounded,
      MiniCoverShape.circle => l.pvMiniShapeCircle,
    };

IconData _miniShapeIcon(MiniCoverShape shape) => switch (shape) {
  MiniCoverShape.rounded => SolarIconsOutline.stop,
  MiniCoverShape.circle => SolarIconsOutline.record,
};

String _miniRadiusLabel(AppLocalizations l, MiniRadius radius) =>
    switch (radius) {
      MiniRadius.none => l.pvMiniRadiusNone,
      MiniRadius.soft => l.pvMiniRadiusSoft,
      MiniRadius.rounded => l.pvMiniRadiusRounded,
      MiniRadius.pill => l.pvMiniRadiusPill,
    };

IconData _miniRadiusIcon(MiniRadius radius) => switch (radius) {
  MiniRadius.none => SolarIconsOutline.stop,
  MiniRadius.soft => SolarIconsOutline.widget,
  MiniRadius.rounded => SolarIconsOutline.widget_2,
  MiniRadius.pill => SolarIconsOutline.record,
};

String _miniProgressLabel(AppLocalizations l, MiniProgressKind kind) =>
    switch (kind) {
      MiniProgressKind.line => l.pvMiniProgressLine,
      MiniProgressKind.fill => l.pvMiniProgressFill,
      MiniProgressKind.ring => l.pvMiniProgressRing,
    };

IconData _miniProgressIcon(MiniProgressKind kind) => switch (kind) {
  MiniProgressKind.line => SolarIconsOutline.minus,
  MiniProgressKind.fill => SolarIconsOutline.stop,
  MiniProgressKind.ring => SolarIconsOutline.refreshCircle,
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

Future<void> _openMiniBg(BuildContext context, WidgetRef ref) => _pickMini(
  context: context,
  title: context.l.pvMiniBgRow,
  subtitle: context.l.pvMiniBgSub,
  values: MiniBg.values,
  current: ref.read(miniStyleProvider).bg,
  icon: _miniBgIcon,
  label: (bg) => _miniBgLabel(context.l, bg),
  apply: ref.read(miniStyleProvider.notifier).setBg,
);

Future<void> _openMiniShape(BuildContext context, WidgetRef ref) => _pickMini(
  context: context,
  title: context.l.pvMiniShapeRow,
  values: MiniCoverShape.values,
  current: ref.read(miniStyleProvider).shape,
  icon: _miniShapeIcon,
  label: (shape) => _miniShapeLabel(context.l, shape),
  apply: ref.read(miniStyleProvider.notifier).setShape,
);

Future<void> _openMiniRadius(BuildContext context, WidgetRef ref) => _pickMini(
  context: context,
  title: context.l.pvMiniRadiusRow,
  values: MiniRadius.values,
  current: ref.read(miniStyleProvider).radius,
  icon: _miniRadiusIcon,
  label: (radius) => _miniRadiusLabel(context.l, radius),
  apply: ref.read(miniStyleProvider.notifier).setRadius,
);

/// Шторка «одно из»: список вариантов; выбор применяется и ЗАКРЫВАЕТ шторку.
///
/// Закрывает, в отличие от шторок анимации: настройка меняет карточку над
/// таб-баром, а шторка её собой и закрывает — смотреть на результат из-под неё
/// всё равно нечем (та же причина, что у выбора вида таб-бара).
Future<void> _pickMini<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<T> values,
  required T current,
  required IconData Function(T) icon,
  required String Function(T) label,
  required void Function(T) apply,
}) async {
  final picked = await showBloomSheetChild<T>(
    context: context,
    header: _sheetHeader(context, title, subtitle),
    // Закрывать шторку надо ЕЁ контекстом: она живёт в корневом навигаторе, а
    // страница — во вложенном, и `pop` со страничным закрыл бы «Настройки».
    child: Builder(
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            _OptionTile(
              icon: icon(value),
              label: label(value),
              active: value == current,
              onTap: () => Navigator.of(sheetContext).pop(value),
            ),
        ],
      ),
    ),
  );
  if (picked != null) apply(picked);
}

String _miniButtonLabel(AppLocalizations l, MiniButton button) =>
    switch (button) {
      MiniButton.prev => l.pvMiniButtonPrev,
      MiniButton.play => l.pvMiniButtonPlay,
      MiniButton.next => l.pvMiniButtonNext,
      MiniButton.fav => l.pvMiniButtonFav,
    };

IconData _miniButtonIcon(MiniButton button) => switch (button) {
  MiniButton.prev => SolarIconsOutline.skipPrevious,
  MiniButton.play => SolarIconsOutline.play,
  MiniButton.next => SolarIconsOutline.skipNext,
  MiniButton.fav => SolarIconsOutline.heart,
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
    header: _sheetHeader(context, l.pvMiniButtonsRow, l.pvMiniButtonsSub),
    child: Consumer(
      builder: (context, ref, _) {
        final mini = ref.watch(miniStyleProvider);
        final ctrl = ref.read(miniStyleProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final button in MiniButton.values)
              _OptionTile(
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

/// Шторка индикаторов прогресса — набор, а не выбор: строки переключаются на
/// месте, и шторка остаётся открытой, их настраивают подряд.
Future<void> _openMiniProgress(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: _sheetHeader(context, l.pvMiniProgressRow, l.pvMiniProgressSub),
    child: Consumer(
      builder: (context, ref, _) {
        final mini = ref.watch(miniStyleProvider);
        final ctrl = ref.read(miniStyleProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in MiniProgressKind.values)
              _OptionTile(
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

/// Строка варианта в шторке: значок, подпись и отметка справа. Каждая — своим
/// блоком ([SheetPanel]), как пункты обычной шторки: сплошным списком с
/// разделителями выбранную строку не подсветить.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.check = false,
  });

  final IconData icon;
  final String label;

  /// Выбранный вариант (или включённый индикатор).
  final bool active;

  /// Строка набора: справа не галочка, а квадратик-флажок, и подсветки строки
  /// нет — включённых бывает несколько, и подсвеченными оказались бы почти все.
  final bool check;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final tint = active && !check;
    return SheetPanel(
      children: [
        InkWell(
          onTap: onTap,
          child: Ink(
            color: tint ? t.accent.withValues(alpha: 0.12) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 16, 11),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? t.accent.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(t.radius * 0.6),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: active ? t.accent : t.iconFg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (check)
                    _CheckBox(on: active)
                  else if (active)
                    Icon(Icons.check, size: 20, color: t.accent),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Флажок строки набора: пустая рамка / залитый акцентом квадрат с галочкой.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? t.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: on ? t.accent : t.ovlLine2, width: 1.5),
      ),
      child: on ? Icon(Icons.check, size: 15, color: t.accentText) : null,
    );
  }
}
