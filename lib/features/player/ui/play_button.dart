/// Кнопка воспроизведения — одна на обе поверхности: транспорт полноэкранного
/// плеера и карточку над таб-баром.
///
/// Виджет общий, а не по кнопке на поверхность, ровно потому, что форму задаёт
/// настройка ([PlayButtonShape]): развести их — значит однажды поправить круг в
/// плеере и забыть про карточку.
///
/// Коробка [size] у всех форм ОДНА и та же, включая «без фона»: ряд транспорта
/// стоит `spaceEvenly`, и кнопка, ужавшаяся до своего знака, растащила бы
/// соседей по строке от одной галочки в настройках.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../play_button_store.dart';
import '../player_controller.dart';

class PlayButton extends ConsumerWidget {
  const PlayButton({
    super.key,
    required this.size,
    required this.iconSize,
    required this.plainIconSize,
    required this.spinnerSize,
    this.loading = false,
    this.live = true,
    this.onTap,
  });

  /// Сторона кнопки — она же диаметр круга.
  final double size;

  /// Знак на заливке (круг и квадрат).
  final double iconSize;

  /// Знак без заливки. Крупнее [iconSize]: подложки, которой кнопка держала на
  /// себе внимание, больше нет, и в прежнем размере она стала бы рядовой
  /// иконкой ряда.
  final double plainIconSize;

  /// Кружок ожидания внутри кнопки.
  final double spinnerSize;

  /// Идёт переход на другой трек. Кнопка ОСТАЁТСЯ на месте, знак подменяется
  /// кружком: иначе транспорт на каждом переходе визуально схлопывался бы.
  final bool loading;

  /// Живая кнопка. `false` — карточка соседа в карусели миниплеера: там кнопки
  /// стоят только ради раскладки, делать им нечего, и знак всегда `play`.
  final bool live;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final shape = ref.watch(playButtonShapeProvider);
    final plain = shape.isPlain;
    // Без заливки знак берёт цвет соседних кнопок: `accentText` держался на
    // фоне акцента, а на фоне плеера он бы просто исчез.
    final color = plain ? t.iconFg : t.accentText;

    Widget shell(Widget child, {VoidCallback? tap}) {
      final inner = Center(child: child);
      return SizedBox(
        width: size,
        height: size,
        child: Material(
          color: plain ? Colors.transparent : t.accent,
          shape: shape == PlayButtonShape.square
              // Скругление долей стороны, а не радиусом темы: кнопка в карточке
              // почти вдвое меньше плеерной, и общий радиус сделал бы из неё
              // пилюлю.
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(size * 0.3),
                )
              : const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: tap == null ? inner : InkWell(onTap: tap, child: inner),
        ),
      );
    }

    if (loading) {
      return shell(
        SizedBox(
          width: spinnerSize,
          height: spinnerSize,
          child: CircularProgressIndicator(
            strokeWidth: size >= 56 ? 2.4 : 2.2,
            color: color,
          ),
        ),
      );
    }

    if (!live) {
      return shell(
        Icon(
          SolarIconsBold.play,
          size: plain ? plainIconSize : iconSize,
          color: color,
        ),
      );
    }

    // Состояние берём у самого плеера, а не у `PlaybackState`: пауза из шторки
    // и с гарнитуры до него не доходит.
    return shell(
      Icon(
        ref.watch(playingNowProvider)
            ? SolarIconsBold.pause
            : SolarIconsBold.play,
        size: plain ? plainIconSize : iconSize,
        color: color,
      ),
      tap: onTap,
    );
  }
}
