/// Стеклянная поверхность — то, чем на телефоне заменяется десктопный
/// `body.glass-mode` из `transparency.css`.
///
/// На ПК стекло получают внешние контейнеры (`.sidebar`/`.main`/панели), а
/// блоки внутри становятся прозрачными. Здесь таких контейнеров нет: карточки
/// лежат прямо на фоне приложения, поэтому стекло — у каждой поверхности своё,
/// и заводит его [GlassBox].
///
/// **Все `GlassBox` обязаны сидеть в [GlassGroup].** `BackdropFilter.grouped`
/// делит с соседями один снимок подложки, и движок размывает её ОДИН раз на
/// группу — иначе экран настроек стоил бы десятка полноэкранных `saveLayer`.
/// Цена — правило из документации `BackdropGroup`: поверхности одной группы не
/// должны накладываться друг на друга. Поэтому групп несколько: своя у
/// содержимого страниц, своя у нижних баров (они лежат ПОВЕРХ списка) и своя у
/// каждой шторки.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../features/settings/transparency_store.dart';

/// Общий снимок подложки для стеклянных поверхностей внутри. Ставится там, где
/// начинается слой, который не накладывается сам на себя: содержимое страницы,
/// нижние бары, шторка.
class GlassGroup extends StatelessWidget {
  const GlassGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => BackdropGroup(child: child);
}

/// Поверхность интерфейса: сплошная плашка, а при включённой прозрачности —
/// стекло (полупрозрачная заливка + размытие и яркость подложки).
///
/// Заливка считается от [color] (по умолчанию `pill` — та же, что у плашек без
/// стекла), а не от `blockColor`, как на ПК: у нас поверхность приподнята над
/// фоном плёнкой, и брать голый цвет темы значило бы на сотне процентов
/// получить блок, неотличимый от фона.
class GlassBox extends ConsumerWidget {
  const GlassBox({
    super.key,
    required this.child,
    this.color,
    this.borderRadius,
    this.borderSide,
    this.shape,
    this.overlay = false,
    this.enabled = true,
  });

  final Widget child;

  /// Цвет заливки в непрозрачном виде. По умолчанию `pill`.
  final Color? color;

  /// Скругление. По умолчанию радиус темы. Игнорируется, если задан [shape].
  final BorderRadius? borderRadius;

  /// Рамка. Игнорируется, если задан [shape].
  final BorderSide? borderSide;

  /// Своя форма — когда скруглением и рамкой не обойтись (полоса таб-бара с
  /// линией только сверху, круглая кнопка).
  final ShapeBorder? shape;

  /// Читать настройку оверлеев, а не блоков: шторки, меню и диалоги.
  final bool overlay;

  /// Поверхность, которой стекло не положено даже при включённой настройке
  /// (выбранный чип красится акцентом, а не темой).
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final glass = enabled
        ? ref.watch(overlay ? overlayGlassProvider : glassProvider)
        : null;
    final fill = color ?? t.pill;
    final form =
        shape ??
        RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(t.radius),
          side: borderSide ?? BorderSide.none,
        );

    final surface = Material(
      // Заливка живёт на `Material`, а не на `DecoratedBox`: почти каждая
      // поверхность держит внутри `InkWell`, а ему нужен материал-предок.
      color: glass == null
          ? fill
          : fill.withValues(alpha: fill.a * glass.opacity),
      shape: form,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    if (glass?.filter == null) return surface;

    // Обрезка обязательна: без неё фильтр применился бы ко всей области
    // родителя, а не к самой плашке.
    return ClipPath(
      clipper: ShapeBorderClipper(
        shape: form,
        textDirection: Directionality.maybeOf(context),
      ),
      child: BackdropFilter.grouped(filter: glass!.filter!, child: surface),
    );
  }
}
