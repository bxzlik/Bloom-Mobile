/// Мелкие общие элементы: круглая icon-кнопка и обложка.
///
/// Круглая кнопка — базовый элемент раскладки из референса: шапки экранов,
/// оверлей на обложке, кнопки площадки. Подложка — плёнка `iconBg`, штрих —
/// `iconFg`, как в десктопном Bloom.
library;

import 'dart:math' show cos, pi;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';
import 'bloom_mark.dart';
import 'cover_collage.dart';
import 'cover_hero.dart';
import 'glass.dart';

/// Высота управляющих элементов шапки: круглых кнопок, пилюли профиля, поля
/// поиска и пилюли-заголовка подстраницы. В референсе шапка заметно крупнее,
/// чем была у нас (42), — держим все элементы шапки ровно этой высоты.
///
/// Одно число на всё приложение: свёрнутые бары детальных страниц, поиск,
/// пилюля площадки в плеере и онбординг считают свои размеры от него, поэтому
/// шапка растёт везде разом и ряды не разъезжаются.
const double kHeaderControl = 51;

/// Кегль названия внутри пилюли шапки: имя приложения на главной, раздел на
/// подстранице, запрос в поиске.
///
/// Отдельным числом, а не `titleMedium` темы: тот же стиль носят строки треков
/// и подписи карточек, и растить его ради шапки нельзя.
const double kHeaderTitleSize = 16;

/// Высота чипа-фильтра (библиотека, поиск) и круглых кнопок в том же ряду.
const double kChipHeight = 44;

/// Запас снизу под плавающие бары каркаса — миниплеер и таб-бар.
///
/// Каркас держит их поверх содержимого (`Scaffold.extendBody`), поэтому список
/// идёт до самого низа экрана и просвечивает сквозь поля вокруг карточки
/// плеера. Плата за это — последние строки навсегда остаются под барами, если
/// скролл не добрать этим отступом.
///
/// Высоту не считаем руками (64 + 8 + 58 + вырез): её кладёт в нижний отступ
/// `MediaQuery` сам `Scaffold` — при `extendBody` он берёт максимум из выреза
/// системы и высоты нижних баров. Своя копия числа разъехалась бы с раскладкой
/// при первой же правке миниплеера.
///
/// Вне каркаса (модалка поверх всего) вернёт обычный системный вырез — там это
/// и нужно.
double bottomBarsInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// Хвост `CustomScrollView` на высоту баров: там, где отступ негде дописать к
/// существующему `SliverPadding` (ветки `if`/`else` с разными списками).
class SliverBottomBarsInset extends StatelessWidget {
  const SliverBottomBarsInset({super.key, this.extra = 0});

  /// Дополнительный просвет над барами — сверх их высоты.
  final double extra;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: bottomBarsInset(context) + extra),
  );
}

/// Иконка из SVG-ассета, перекрашенная в цвет темы. Нужна там, где глиф из
/// шрифта Solar нарисован криво (library, user-circle) и берётся настоящий
/// Solar-SVG.
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.asset, {super.key, this.size = 22, this.color});

  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? context.bloom.iconFg,
        BlendMode.srcIn,
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = kHeaderControl,
    this.iconSize = 23,
    this.background,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    // Со своей заливкой (акцент под play, прозрачная у кнопок миниплеера)
    // кнопка стеклом не становится: этот цвет — состояние, а не поверхность
    // темы.
    final button = GlassBox(
      color: background,
      enabled: background == null,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: color ?? t.iconFg),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Матовое стекло под элементами, стоящими ПОВЕРХ обложки: круглые кнопки
/// шапки, ряд действий, поле поиска по списку.
///
/// Кружок здесь светлый, а не тёмный: читаемость даёт размытие того, что под
/// ним, поэтому подложке хватает почти прозрачной белой плёнки, и кнопка
/// подхватывает цвет обложки вместо чёрной нашлёпки.
const double kGlassBlur = 14;
const Color kGlassFilm = Color(0x2BFFFFFF);

/// Обернуть в стекло произвольную форму: [shape] и обрезает размытие, и задаёт
/// границу плёнки.
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.shape, required this.child});

  final BorderRadius shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
        child: Material(
          color: kGlassFilm,
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

/// Круглая кнопка ПОВЕРХ картинки: светлое стекло, белый штрих. Под ней
/// обложка, а не поверхность темы, поэтому `pill` и `iconFg` не годятся —
/// на баннере они читаются как серая заплатка.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = kHeaderControl,
    this.iconSize = 23,
    this.background,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// Своя подложка — для «включённых» состояний (подписка, сет сохранён).
  /// Кружок при этом сплошной: размывать под заливкой нечего.
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (background case final fill?) {
      return CircleIconButton(
        icon: icon,
        size: size,
        iconSize: iconSize,
        background: fill,
        color: color ?? Colors.white,
        onTap: onTap,
      );
    }
    return GlassSurface(
      shape: BorderRadius.circular(size / 2),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: color ?? Colors.white),
        ),
      ),
    );
  }
}

/// Нижний край обложки в hero-шапках.
///
/// Обложка идёт на всю высоту шапки — под название, счётчик и ряд кнопок — и
/// ОБРЕЗАЕТСЯ скруглёнными нижними углами, а не растворяется в фоне: в
/// референсе граница видна, картинка просто кончается. Плёнка поверх нужна
/// только чтобы белый текст и кнопки не тонули на светлом снимке, поэтому она
/// не доходит до полной непрозрачности — иначе сам край станет не виден.
class HeroCover extends StatelessWidget {
  const HeroCover({super.key, required this.child, this.start = 0.20});

  /// Сама картинка: одна обложка, коллаж или заглушка.
  final Widget child;

  /// Доля высоты шапки, до которой картинка не затемняется вовсе.
  final double start;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final rest = 1 - start;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(t.radius * 1.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Верх: на светлом снимке белые кнопки и часы системной строки
          // исчезают, поэтому им нужна тёмная подложка независимо от обложки.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0),
                ],
                stops: const [0, 0.28],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  t.bg.withValues(alpha: 0),
                  t.bg.withValues(alpha: 0.45),
                  t.bg.withValues(alpha: 0.70),
                  t.bg.withValues(alpha: 0.80),
                ],
                stops: [start, start + rest * 0.40, start + rest * 0.72, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Та же круглая кнопка, но со Solar-SVG вместо глифа.
class CircleSvgButton extends StatelessWidget {
  const CircleSvgButton({
    super.key,
    required this.asset,
    this.onTap,
    this.size = kHeaderControl,
    this.iconSize = 23,
  });

  final String asset;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return GlassBox(
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: SvgIcon(asset, size: iconSize)),
        ),
      ),
    );
  }
}

/// Эквалайзер играющего трека — порт десктопного `.bars`: три полоски шириной
/// 3 с зазором 2, высоты 8/12/6, каждая следующая со сдвигом фазы на 0.2s.
///
/// Одна анимация на все три полоски, фаза берётся сдвигом по косинусу — цикл
/// замкнут, «отката» в начале нет. На паузе полоски замирают там, где стояли, и
/// гаснут вполовину (десктопное `body.audio-paused`).
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.color,
    this.scale = 1,
  });

  final bool playing;
  final Color? color;

  /// Множитель размера — полоски заданы в тех же пикселях, что на десктопе.
  final double scale;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  static const List<double> _heights = [8, 12, 6];

  /// Сдвиги фазы: 0 / 0.2s / 0.4s от цикла в 1.6s.
  static const List<double> _phases = [0, 0.125, 0.25];

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) return;
    if (widget.playing) {
      _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.bloom.accent;
    final k = widget.scale;
    return Opacity(
      opacity: widget.playing ? 1 : 0.5,
      child: SizedBox(
        height: 14 * k,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _heights.length; i++) ...[
                if (i > 0) SizedBox(width: 2 * k),
                Container(
                  width: 3 * k,
                  // scaleY .3 → 1 по косинусу: то же ease-in-out alternate.
                  height:
                      _heights[i] *
                      k *
                      (0.3 +
                          0.35 * (1 - cos(2 * pi * (_c.value + _phases[i])))),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2 * k),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Тумблер настроек — порт десктопного `.tele-sw`: дорожка 44×24 цвета
/// `border`, кружок 18 у левого края, включённый — дорожка акцентом, кружок
/// `accentText`. Свой, а не material `Switch`: тому не отключить заливку под
/// пальцем и он тянет за собой свою палитру.
class BloomSwitch extends StatelessWidget {
  const BloomSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: _duration,
        curve: Curves.easeOut,
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? t.accent : t.border,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: _duration,
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? t.accentText : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Обложка: скруглённая картинка с заглушкой на месте отсутствующей.
class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.url,
    required this.size,
    this.radius,
    this.circle = false,
    this.flight,
    this.overlay,
    this.covers,
  });

  final String? url;
  final double size;
  final double? radius;
  final bool circle;

  /// Обложки треков списка — из них собирается коллаж, когда своей картинки у
  /// списка нет. Так же, как в шапке этого списка (`CoverCollage`): карточка и
  /// страница обязаны показывать одно и то же. `null` — сущность не список
  /// (трек, артист), собирать нечего.
  final Iterable<String?>? covers;

  /// Слой поверх картинки — эквалайзер играющего сета. Стоит РЯДОМ с перелётом,
  /// а не внутри: летит одна обложка, полоски остаются на карточке.
  final Widget? overlay;

  /// Метка перелёта в шапку страницы, которую откроет эта карточка. `null` —
  /// обложка никуда не летит (строка трека, шапка шторки, превью выбора).
  ///
  /// Летит только НАСТОЯЩАЯ картинка: заглушке лететь некуда — на той стороне
  /// её место занимает коллаж или тинт раздела.
  final CoverFlight? flight;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final shape = circle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(radius ?? t.radius * 0.72);

    // Пустая обложка — приглушённый знак bloom, как `.ps-cover-empty` на
    // десктопе (там глиф с opacity .12).
    // Цвет сплошной, а не плёнка: над картинкой-фоном полупрозрачная заглушка
    // показывала обои и плитка читалась дыркой в списке.
    Widget placeholder() => DecoratedBox(
      decoration: BoxDecoration(color: t.coverEmpty, borderRadius: shape),
      child: Center(
        child: BloomMark(size: size * 0.34, color: t.text, opacity: 0.16),
      ),
    );

    // Оверлей обрезаем той же формой, что и картинку, — иначе плёнка вылезет
    // за скруглённые углы.
    Widget withOverlay(Widget child) => overlay == null
        ? child
        : Stack(
            fit: StackFit.expand,
            children: [
              child,
              ClipRRect(borderRadius: shape, child: overlay),
            ],
          );

    final image = coverImage(url);
    if (image == null) {
      final collage = covers;
      return SizedBox(
        width: size,
        height: size,
        child: withOverlay(
          collage == null
              ? placeholder()
              : ClipRRect(
                  borderRadius: shape,
                  child: CoverCollage(covers: collage, fallback: placeholder()),
                ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: withOverlay(
        // Скругление внутри перелёта, а не снаружи: обрезка родителя на летящую
        // копию не действует, форму ей задаёт сам [CoverHero].
        CoverHero(
          tag: flight?.tag,
          shape: shape,
          child: ClipRRect(
            borderRadius: shape,
            child: Image(
              image: image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder(),
              frameBuilder: (context, child, frame, wasSync) {
                if (wasSync || frame != null) return child;
                return placeholder();
              },
            ),
          ),
        ),
      ),
    );
  }
}
