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

import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';
import 'atoms.dart';

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
  return showModalBottomSheet<T>(
    context: context,
    // Корневой навигатор: иначе шторка живёт внутри ветки таба и таб-бар с
    // миниплеером остаются поверх неё.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (sheetContext) =>
        _SheetShell(backdrop: backdrop, header: header, child: child),
  );
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.backdrop,
    required this.header,
    required this.child,
  });

  final String? backdrop;
  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final media = MediaQuery.of(context);

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
                    // Ручка и шапка закреплены: листаются только пункты, иначе
                    // в длинной шторке обложка уезжает вверх вместе с ними.
                    const _Handle(),
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
    final t = context.bloom;
    final image = coverImage(cover);
    if (image == null) return ColoredBox(color: t.bg);

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

class _Handle extends StatelessWidget {
  const _Handle();

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
/// нельзя: заливка тут не токен-плёнка (`t.pill` кроет обложку насмерть), а
/// чёрный с прозрачностью, чтобы фон шторки просвечивал.
class SheetPanel extends StatelessWidget {
  const SheetPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        // Просто чёрный с прозрачностью — без своего размытия: размыт фон
        // шторки, а блок лежит поверх него ровной тёмной панелью.
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(t.radius),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Разделитель внутри [SheetPanel]. Начинается там же, где текст: под иконками
/// сплошная линия режет колонку глифов пополам. Цвет светлый, а не
/// токен-плёнка: блок лежит на тёмном, а не на фоне темы.
Widget sheetDivider() => Divider(
  height: 1,
  thickness: 1,
  indent: 54,
  color: Colors.white.withValues(alpha: 0.08),
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
