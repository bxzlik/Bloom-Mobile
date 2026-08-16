/// Нижняя шторка — то, что открывается по «трём точкам» и длинному тапу.
///
/// Раскладка из референса: сверху ручка, затем шапка сущности (обложка +
/// название), ниже пункты, собранные в скруглённые блоки по смыслу — сначала
/// воспроизведение, потом действия над сущностью, в конце опасное.
///
/// Фон самой шторки — размытая обложка той сущности, о которой она; страница
/// под шторкой НЕ размывается, только притемняется. Шторка идёт через корневой
/// навигатор, поэтому накрывает и таб-бар с миниплеером — иначе бары остаются
/// поверх затемнения и висят непрозрачной полосой.
///
/// Состав пунктов задаёт вызывающий: он берётся из десктопного Bloom, а не из
/// референса — там свои функции, которых у нас нет.
library;

import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';
import '../../features/settings/transparency_store.dart';
import 'atoms.dart';
import 'glass.dart';

/// Пункт шторки.
class SheetAction {
  const SheetAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
    this.chevron = false,
    this.trailing,
  });

  final IconData icon;
  final String label;

  /// Шторка закрывается ДО вызова: почти каждый пункт открывает диалог или
  /// другую шторку, и делать это поверх текущей нельзя.
  final VoidCallback? onTap;

  /// Красный пункт — удаление.
  final bool danger;

  /// Стрелка справа: пункт ведёт в следующую шторку.
  final bool chevron;

  /// Своя отметка справа (галочка активного состояния).
  final Widget? trailing;
}

/// Шторка со списком пунктов, разбитых на блоки. Пустые блоки выпадают.
///
/// [backdrop] — обложка сущности: размытая, она и служит фоном шторки.
Future<void> showBloomSheet({
  required BuildContext context,
  String? backdrop,
  Widget? header,
  required List<List<SheetAction>> groups,
}) {
  final filled = groups.where((g) => g.isNotEmpty).toList();
  return showBloomSheetChild<void>(
    context: context,
    backdrop: backdrop,
    header: header,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final group in filled) _SheetGroup(actions: group)],
    ),
  );
}

/// Та же шторка, но с произвольным содержимым — для выбора плейлиста и других
/// списков. Возвращает то, с чем её закрыли (`Navigator.pop`).
Future<T?> showBloomSheetChild<T>({
  required BuildContext context,
  String? backdrop,
  Widget? header,
  required Widget child,
}) {
  return showBloomModal<T>(
    context: context,
    builder: (_) =>
        _SheetShell(backdrop: backdrop, header: header, child: child),
  );
}

/// Открыть шторку — одна точка входа на все: и на эти, и на те, у кого своя
/// оболочка (очередь, скорость, пикер цвета).
///
/// Здесь же живёт стекло затемнения: при включённой «Прозрачности оверлеев»
/// страница под шторкой не просто темнеет, а размывается тем же фильтром, что
/// и блоки, — десктопный scrim с `backdrop-filter: var(--glass-filter)`. Оттуда
/// же и осветление самого затемнения (0.5 → 0.28): под тёмной плёнкой размытие
/// не видно, и стеклянная шторка висела бы над чёрным.
Future<T?> showBloomModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  // Корневой навигатор: иначе шторка живёт внутри ветки таба и таб-бар с
  // миниплеером остаются поверх неё.
  final navigator = Navigator.of(context, rootNavigator: true);
  final glass = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(overlayGlassProvider);
  return navigator.push(
    _BloomSheetRoute<T>(
      builder: builder,
      // Темы захватываем, как это делает сам `showModalBottomSheet`: шторка
      // строится в оверлее корневого навигатора, и всё, что стоит НИЖЕ него
      // (у нас — ничего критичного, но правило общее), иначе потерялось бы.
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(
        alpha: glass == null ? 0.5 : 0.28,
      ),
    ),
  );
}

/// Шторка, чьё затемнение умеет быть стеклом.
///
/// `ModalBottomSheetRoute` не принимает фильтр барьера (у `ModalRoute` поле
/// `filter` есть, но конструктор шторки его не пробрасывает), поэтому
/// подменяем сам барьер. Фильтр читается через `Consumer`: ползунок размытия
/// живёт в шторке, и её собственное затемнение обязано меняться под пальцем.
class _BloomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _BloomSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.backgroundColor,
    super.modalBarrierColor,
  });

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    return Consumer(
      builder: (context, ref, _) {
        final filter = ref.watch(overlayGlassProvider)?.filter;
        if (filter == null) return barrier;
        return BackdropFilter(filter: filter, child: barrier);
      },
    );
  }
}

/// Поверхность шторки без обложки: сплошной фон темы, а при включённом стекле
/// оверлеев — полупрозрачный с размытием того, что под шторкой.
///
/// Общая на шторки со своей оболочкой (очередь, скорость, пикер цвета) и на
/// [SheetBackdrop] без картинки.
class SheetSurface extends ConsumerWidget {
  const SheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final glass = ref.watch(overlayGlassProvider);
    // Обложки у такой шторки нет — значит и её плашкам красться не по чёрному:
    // скин объявляем здесь, чтобы шторки со своей оболочкой (очередь, скорость,
    // сон) получали его без своего кода.
    final skinned = _SheetSkinScope(
      skin: glass == null ? _SheetSkin.plain : _SheetSkin.glass,
      child: child,
    );
    if (glass == null) return ColoredBox(color: t.bg, child: skinned);

    final surface = ColoredBox(
      color: t.bg.withValues(alpha: t.bg.a * glass.opacity),
      child: skinned,
    );
    // Фильтр здесь не `grouped`: шторка одна, снимок подложки ей нужен свой —
    // и он обязан отличаться от того, что видят блоки страницы под ней.
    return glass.filter == null
        ? surface
        : BackdropFilter(filter: glass.filter!, child: surface);
  }
}

/// На чём стоят блоки шторки: на её обложке, на стекле или на обычном фоне
/// темы. Отсюда их заливка — [sheetPanelColor] — и линии — [sheetLineColor].
enum _SheetSkin { cover, glass, plain }

/// Скин, объявленный оболочкой шторки. Вне шторки — [_SheetSkin.plain]: блок
/// красится тем же, чем плашки страниц.
class _SheetSkinScope extends InheritedWidget {
  const _SheetSkinScope({required this.skin, required super.child});

  final _SheetSkin skin;

  static _SheetSkin of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetSkinScope>()?.skin ??
      _SheetSkin.plain;

  @override
  bool updateShouldNotify(_SheetSkinScope old) => old.skin != skin;
}

/// Заливка плашки внутри шторки — одна на все её блоки, включая собранные
/// руками (превью стиля, строки выбора в настройках плеера и свайпов).
///
/// Над обложкой — чёрный с прозрачностью: токен-плёнка накрыла бы размытую
/// картинку насмерть. На стекле — тонкая белая плёнка, иначе блок остался бы
/// единственным непрозрачным пятном прозрачной шторки (десктопное «внутренние
/// блоки прозрачны»). А шторка без обложки стоит на обычном фоне темы, и её
/// строки красятся тем же `pill`, что строки страниц: чёрный на нём читался бы
/// провалом.
Color sheetPanelColor(BuildContext context) =>
    switch (_SheetSkinScope.of(context)) {
      _SheetSkin.cover => Colors.black.withValues(alpha: 0.55),
      _SheetSkin.glass => Colors.white.withValues(alpha: 0.06),
      _SheetSkin.plain => context.bloom.pill,
    };

/// Линия внутри плашки шторки: на тёмном (обложка, стекло) — светлая, на
/// обычной плашке — та же токенная линия, что делит строки на страницах.
Color sheetLineColor(BuildContext context) =>
    _SheetSkinScope.of(context) == _SheetSkin.plain
    ? context.bloom.ovlLine
    : Colors.white.withValues(alpha: 0.08);

class _SheetShell extends ConsumerWidget {
  const _SheetShell({
    required this.backdrop,
    required this.header,
    required this.child,
  });

  final String? backdrop;
  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final media = MediaQuery.of(context);
    // Стеклянной шторка становится, только если своей обложки у неё нет: с
    // обложкой вид утверждён отдельно (затемнённая картинка фоном), и стекло
    // его перечёркивает. Спрашиваем не ссылку, а картинку — ссылка бывает и
    // без картинки (свой файл, а каталога обложек нет), и тогда фоном шторки
    // всё равно встаёт [SheetSurface].
    final cover = coverImage(backdrop) != null;
    final glass = !cover && ref.watch(overlayGlassProvider) != null;

    // Отступ снизу под клавиатуру: шторка стоит на дне экрана, и без него поле
    // ввода (создание плейлиста) осталось бы под ней. Потолок высоты на ту же
    // величину опускается, иначе шторка вылезет за верх экрана.
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height * 0.85 - media.viewInsets.bottom,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(t.radius * 1.7),
          ),
          child: _SheetSkinScope(
            skin: cover
                ? _SheetSkin.cover
                : glass
                ? _SheetSkin.glass
                : _SheetSkin.plain,
            // Своя группа: шторка лежит поверх страницы, и снимок подложки у
            // неё обязан быть свой (см. `GlassGroup`).
            child: GlassGroup(
              child: Stack(
                children: [
                  // Картинок две: эта — фон всей шторки, и та же, но резкая и
                  // яркая, в шапке поверх неё.
                  Positioned.fill(child: SheetBackdrop(cover: backdrop)),
                  SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Ручка и шапка закреплены: листаются только пункты,
                        // иначе в длинной шторке обложка уезжает вверх с ними.
                        const SheetHandle(),
                        ?header,
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [child, const SizedBox(height: 10)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Фон шторки: обложка сущности, размытая и притемнённая. Один на все шторки —
/// включая очередь, у которой своя оболочка.
class SheetBackdrop extends StatelessWidget {
  const SheetBackdrop({super.key, required this.cover});

  /// Сила размытия. Пункты лежат прямо на фоне, и деталей обложки под ними
  /// остаться не должно — отсюда σ куда больше, чем у стеклянных плёнок.
  static const double sigma = 34;

  final String? cover;

  @override
  Widget build(BuildContext context) {
    final image = coverImage(cover);
    // Обложки нет — фон шторки берёт на себя [SheetSurface]: он же умеет быть
    // стеклом.
    if (image == null) return const SheetSurface(child: SizedBox.expand());

    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          // `clamp`: без него размытие тянет за края прозрачность и по
          // периметру шторки идёт светлая кайма.
          imageFilter: ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
          child: Image(image: image, fit: BoxFit.cover),
        ),
        // Притемнение поверх размытия: одного блюра мало, светлые обложки
        // забивают текст пунктов.
        ColoredBox(color: Colors.black.withValues(alpha: 0.62)),
      ],
    );
  }
}

/// Ручка шторки — одна на все шторки, включая те, у кого своя оболочка
/// (очередь, скорость).
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// Блок пунктов шторки. Один на все шторки — свой такой же собирать руками
/// нельзя: заливка тут зависит от того, на чём стоит шторка ([sheetPanelColor]).
class SheetPanel extends StatelessWidget {
  const SheetPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        // Без своего размытия: размыт фон шторки, а блок лежит поверх него
        // ровной панелью.
        color: sheetPanelColor(context),
        borderRadius: BorderRadius.circular(t.radius),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Разделитель внутри [SheetPanel]. Начинается там же, где текст: под иконками
/// сплошная линия режет колонку глифов пополам.
Widget sheetDivider() => Builder(
  builder: (context) => Divider(
    height: 1,
    thickness: 1,
    indent: 54,
    color: sheetLineColor(context),
  ),
);

class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.actions});

  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    return SheetPanel(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) sheetDivider(),
          _SheetTile(action: actions[i]),
        ],
      ],
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.action});

  final SheetAction action;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final enabled = action.onTap != null;
    final color = action.danger
        ? t.sysFavIco
        : enabled
        ? t.text
        : t.muted;

    return InkWell(
      onTap: enabled
          ? () {
              Navigator.of(context).pop();
              action.onTap!();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(action.icon, size: 22, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: color),
              ),
            ),
            ?action.trailing,
            if (action.chevron)
              Icon(Icons.chevron_right, size: 20, color: t.muted),
          ],
        ),
      ),
    );
  }
}

/// Шапка шторки для трека и артиста: маленькая обложка слева, название и
/// подпись справа.
class SheetLineHeader extends StatelessWidget {
  const SheetLineHeader({
    super.key,
    required this.cover,
    required this.title,
    required this.subtitle,
    this.circle = false,
  });

  final String? cover;
  final String title;
  final String subtitle;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          Cover(url: cover, size: 56, circle: circle),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleLarge,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Шапка шторки для плейлиста и альбома: широкая обложка, название поверх неё
/// в нижнем углу.
/// Поле шторки с галочкой справа. Галочка появляется вместе с текстом — до
/// него кнопке нечего делать (то же условие, что в `lam-check` на ПК).
///
/// Общее у шторок «Создать плейлист» и «Создать пресет»: поле ввода в шторке
/// должно выглядеть одинаково, где бы оно ни стояло.
class SheetField extends StatelessWidget {
  const SheetField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onSubmit,
    this.autofocus = false,
    this.busy = false,
    this.maxLength,
    this.trailing,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool autofocus;

  /// Идёт долгая работа (импорт по ссылке) — на кнопке кружок, нажатие не
  /// проходит.
  final bool busy;
  final int? maxLength;

  /// Значок внутри поля справа — площадка, узнанная по ссылке.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final filled = controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                // Как и блоки шторки — по тому же скину.
                color: sheetPanelColor(context),
                borderRadius: BorderRadius.circular(t.radius),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: autofocus,
                      maxLength: maxLength,
                      cursorColor: t.accent,
                      textInputAction: TextInputAction.done,
                      style: theme.titleMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                        hintText: hint,
                        hintStyle: theme.titleMedium?.copyWith(color: t.muted),
                      ),
                      onChanged: onChanged,
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                  if (trailing case final widget?) ...[
                    const SizedBox(width: 8),
                    widget,
                  ],
                ],
              ),
            ),
          ),
          // Ширина ряда меняется вместе с кнопкой — иначе поле дёргалось бы
          // рывком на первом же символе.
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: filled
                ? Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: _ConfirmButton(busy: busy, onTap: onSubmit),
                  )
                : const SizedBox(height: 54),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      color: t.accent,
      borderRadius: BorderRadius.circular(t.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 54,
          height: 54,
          child: busy
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accentText,
                    ),
                  ),
                )
              : Icon(Icons.check_rounded, size: 24, color: t.accentText),
        ),
      ),
    );
  }
}

class SheetCoverHeader extends StatelessWidget {
  const SheetCoverHeader({
    super.key,
    required this.cover,
    required this.title,
    required this.subtitle,
  });

  final String? cover;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final width = MediaQuery.of(context).size.width - 24;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius),
        child: SizedBox(
          width: width,
          height: width * 0.56,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Обложка квадратная, а карточка широкая — берём центр по
              // вертикали, там у обложек обычно и есть главное.
              Cover(url: cover, size: width, radius: 0),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleLarge?.copyWith(
                        fontSize: 20,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium?.copyWith(
                          color: Colors.white70,
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
    );
  }
}
