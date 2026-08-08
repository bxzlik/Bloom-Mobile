/// Перелёт обложки: с карточки списка на своё место в шапке страницы.
///
/// Обе стороны заворачивают картинку в [CoverHero] с одной меткой, и навигатор
/// на время перехода рисует в своём оверлее копию, которая едет из
/// прямоугольника карточки в прямоугольник шапки.
///
/// Скругление у концов разное — кружок аватарки, мягкий квадрат карточки,
/// скруглённый низ шапки, — поэтому форму летящей копии считаем сами: обрезка
/// родителя на неё не действует, копия живёт вне дерева страницы.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// Обложка карточки, с которой уходят на страницу.
///
/// [tag] карточка выдаёт себе сама — по одной на экземпляр. Считать метку из id
/// нельзя: один и тот же альбом легко попадает сразу в две секции выдачи
/// («Альбомы» и «Репосты»), а два `Hero` с одинаковой меткой в одном дереве —
/// это исключение на старте перехода.
class CoverFlight {
  const CoverFlight({required this.tag, this.image});

  final Object tag;

  /// Картинка карточки — она уже в кеше. Шапка показывает её, пока грузится
  /// своя: площадка ту же обложку отдаёт другой ссылкой (крупнее), и без
  /// подмены конец перелёта моргнул бы заглушкой.
  final String? image;
}

/// Один конец перелёта. [tag] `null` — перелёта нет (открыли не с карточки, у
/// карточки нет обложки), и виджет остаётся просто [child].
class CoverHero extends StatelessWidget {
  const CoverHero({
    super.key,
    required this.tag,
    required this.shape,
    required this.child,
  });

  final Object? tag;

  /// Скругление картинки на ЭТОМ конце. Летящая копия берёт форму у обоих
  /// концов и идёт между ними.
  final BorderRadius shape;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tag = this.tag;
    if (tag == null) return child;
    return Hero(tag: tag, flightShuttleBuilder: _shuttle, child: child);
  }

  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final from = _shapeOf(fromContext);
    final to = _shapeOf(toContext);
    // Летит содержимое ЦЕЛИ — ровно то, что останется на месте после посадки.
    final child = (toContext.widget as Hero).child;
    // Доля перелёта. На «назад» навигатор гонит кадры от 1 к 0, а копия всё
    // равно едет от `from` к `to` — иначе скругление считалось бы задом наперёд.
    final t = direction == HeroFlightDirection.pop
        ? ReverseAnimation(animation)
        : animation;

    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.lerp(from, to, t.value)!,
        child: child,
      ),
    );
  }

  /// Форма конца перелёта: у контекста `Hero` спрашиваем обёртку, которая его
  /// поставила.
  static BorderRadius _shapeOf(BuildContext context) =>
      context.findAncestorWidgetOfExactType<CoverHero>()?.shape ??
      BorderRadius.zero;
}

/// Проявление содержимого шапки (кнопки, название, ряд действий) под конец
/// перелёта.
///
/// Летящая копия рисуется в оверлее навигатора — ПОВЕРХ страницы, — и к концу
/// пути она накрывает собой всю шапку вместе с текстом. Без этого текст успел
/// бы проявиться, спрятаться под обложкой и вынырнуть рывком в момент посадки.
/// Поэтому шапка ждёт своего перехода: содержимое появляется ровно тогда, когда
/// обложка встаёт на место.
///
/// [flying] `false` — перелёта нет, и придерживать нечего.
class HeroContent extends StatelessWidget {
  const HeroContent({super.key, required this.flying, required this.child});

  final bool flying;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (!flying || animation == null) return child;
    return FadeTransition(
      // Первая половина перехода (450 мс на всё) — обложка ещё в пути; текст
      // входит во вторую. `drive`, а не `CurvedAnimation`: тот заводится в
      // `build` и его некому закрыть.
      opacity: animation.drive(
        CurveTween(curve: const Interval(0.5, 1, curve: Curves.easeOut)),
      ),
      child: child,
    );
  }
}

// ─── Переход страницы под перелётом ─────────────────────────────────────────

/// Переход на страницу, в шапку которой летит обложка: то же растворение, что
/// у всего приложения, но БЕЗ горизонтального сдвига.
///
/// Общий переход (`FadeForwardsPageTransitionsBuilder`, Android U) вводит новую
/// страницу сдвигом сбоку. Под перелётом это разваливается: обложка идёт своей
/// диагональю из карточки в шапку, а название, кнопки и трек-лист в это же
/// время едут по горизонтали — два разных движения в одном кадре, и кажется,
/// что «всё, кроме обложки, заезжает сбоку». Здесь страница остаётся на месте:
/// движется одна обложка, остальное только проявляется.
///
/// Кривые растворения взяты у общего перехода, чтобы страницы приложения не
/// расходились по темпу.

/// Новая страница проявляется за первые 3/4 перехода.
final Animatable<double> _fadeIn = Tween<double>(
  begin: 0,
  end: 1,
).chain(CurveTween(curve: const Interval(0, 0.75)));

/// Уходящая — гаснет за первую четверть.
final Animatable<double> _fadeOut = Tween<double>(
  begin: 1,
  end: 0,
).chain(CurveTween(curve: const Interval(0, 0.25)));

/// Длительность = длительность общего перехода: по ней навигатор гонит и
/// перелёт обложки, и переход страницы, и они обязаны кончиться вместе.
const Duration kDetailTransition = Duration(
  milliseconds: FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds,
);

/// Растворение без сдвига — для обеих сторон: и когда страница входит
/// ([animation]), и когда её саму накрывают следующей ([secondaryAnimation]).
Widget detailPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return DualTransitionBuilder(
    animation: animation,
    forwardBuilder: (context, animation, child) =>
        FadeTransition(opacity: _fadeIn.animate(animation), child: child),
    reverseBuilder: (context, animation, child) => IgnorePointer(
      ignoring: animation.status == AnimationStatus.forward,
      child: FadeTransition(opacity: _fadeOut.animate(animation), child: child),
    ),
    // Заливка на время перехода — иначе в момент, когда страницу накрывают
    // следующей, между ними просвечивает чёрное.
    child: ColoredBox(
      color: secondaryAnimation.isAnimating
          ? context.bloom.bg
          : Colors.transparent,
      child: DualTransitionBuilder(
        animation: ReverseAnimation(secondaryAnimation),
        forwardBuilder: (context, animation, child) =>
            FadeTransition(opacity: _fadeIn.animate(animation), child: child),
        reverseBuilder: (context, animation, child) =>
            FadeTransition(opacity: _fadeOut.animate(animation), child: child),
        child: child,
      ),
    ),
  );
}

/// Маршрут страницы артиста и сета — их открывают обычным навигатором ветки.
PageRoute<T> detailPageRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  pageBuilder: (context, _, _) => builder(context),
  transitionsBuilder: detailPageTransition,
  transitionDuration: kDetailTransition,
  reverseTransitionDuration: kDetailTransition,
);
