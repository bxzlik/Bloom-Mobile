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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';
import '../../features/settings/transparency_store.dart';
import '../util/format.dart';
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
    // Меню сущности на весь экран не растягивается: у трека потолок ниже —
    // шапка там строкой. У плейлиста 0.78 — его число: на 0.7 список обрывался
    // слишком рано, на общих 0.85 шторка лезла под статус-бар.
    // Списки (выбор плейлиста, инфо о треке) идут мимо: у них свой
    // [showBloomSheetChild] и общий потолок.
    maxFraction: switch (header) {
      SheetLineHeader() => 0.65,
      SheetCoverHeader() => 0.78,
      _ => _kSheetMaxFraction,
    },
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
  double maxFraction = _kSheetMaxFraction,
  required Widget child,
}) {
  return showBloomModal<T>(
    context: context,
    builder: (_) => _SheetShell(
      backdrop: backdrop,
      header: header,
      maxFraction: maxFraction,
      child: child,
    ),
  );
}

/// Потолок высоты шторки по умолчанию — доля экрана. Меню трека и плейлиста
/// ограничены сильнее (см. [showBloomSheet]).
const double _kSheetMaxFraction = 0.85;

/// Отступ содержимого меню сущности от краёв шторки: на нём стоят и блоки
/// пунктов, и шапки. Шторки со своим содержимым (списки, настройки) живут на
/// прежних 12 — их вид не пересматривали.
const double kSheetEdge = 20;

/// Скругление в меню сущности — своё, крупнее общего `t.radius` (14): плашки
/// тут широкие и без заливки, на общем радиусе они читались углами. Одно число
/// на блоки пунктов и на карточку обложки — иначе они спорят между собой.
/// Общий радиус не трогаем: он на всё приложение.
const double kSheetPanelRadius = 20;

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

/// Рамка блока шторки — чуть плотнее внутренних линий (0.08), но не жирнее:
/// заливки у блока нет, и кромка должна только намечать его край, а не обводить.
Color sheetPanelLineColor(BuildContext context) =>
    _SheetSkinScope.of(context) == _SheetSkin.plain
    ? context.bloom.ovlLine
    : Colors.white.withValues(alpha: 0.08);

class _SheetShell extends ConsumerWidget {
  const _SheetShell({
    required this.backdrop,
    required this.header,
    required this.maxFraction,
    required this.child,
  });

  final String? backdrop;
  final Widget? header;

  /// Доля экрана, выше которой шторка не растёт.
  final double maxFraction;
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
          maxHeight: media.size.height * maxFraction - media.viewInsets.bottom,
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

/// Фон шторки: обложка сущности сверху, притемнённая и уходящая в цвет темы.
/// Один на все шторки — включая очередь, у которой своя оболочка.
///
/// Размытия здесь нет намеренно: картинка стоит резкой полосой наверху (его
/// референс), а не размытым полотном на всю шторку.
class SheetBackdrop extends StatelessWidget {
  const SheetBackdrop({super.key, required this.cover});

  /// Доля высоты шторки, которую занимает картинка. Ниже неё — ровный цвет:
  /// растянутая на всю шторку обложка «плывёт» до самого низа, а надо, чтобы
  /// фотография стояла полосой сверху и уходила в цвет.
  static const double band = 0.4;

  /// С какой доли полосы картинка начинает растворяться в цвет. Растворение
  /// именно градиентом поверх, а не маской: маска обрывала полосу видимым швом.
  static const double fade = 0.4;

  final String? cover;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final image = coverImage(cover);
    // Обложки нет — фон шторки берёт на себя [SheetSurface]: он же умеет быть
    // стеклом.
    if (image == null) return const SheetSurface(child: SizedBox.expand());

    return Stack(
      fit: StackFit.expand,
      children: [
        // Цвет, в который уходит картинка, — фон темы: низ шторки должен быть
        // ровным, без остатков обложки.
        ColoredBox(color: t.bg),
        FractionallySizedBox(
          alignment: Alignment.topCenter,
          heightFactor: band,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Обложка квадратная, полоса шире — берём её центр (`cover` с
              // выравниванием по центру), иначе картинка липнет к краю.
              Image(image: image, fit: BoxFit.cover),
              // Притемнение — только по картинке: светлые обложки забивают
              // текст шапки. Ниже полосы его нет, иначе плёнка красила бы и
              // ровный фон и дно шторки уходило бы в чёрное вместо цвета темы.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x57000000), // 0.34 — у шапки обложка почти открыта
                      Color(0xB8000000), // 0.72 — дальше текст уже уверенно
                    ],
                    stops: [0, 0.55],
                  ),
                ),
              ),
              // Растворение картинки в фон темы — последним, поверх плёнки:
              // к низу полосы должен остаться ровно `t.bg`, без чёрного под ним.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Тот же цвет с нулевой альфой, а не `transparent`: иначе
                    // на светлой теме растворение шло бы через чёрный.
                    colors: [t.bg.withValues(alpha: 0), t.bg],
                    stops: const [fade, 1],
                  ),
                ),
              ),
            ],
          ),
        ),
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
  const SheetPanel({super.key, required this.children, this.gap = 6});

  final List<Widget> children;

  /// Просвет сверху и снизу. Меньше обычного у списков выбора: там каждая
  /// строка — свой блок, и полный отступ между ними растаскивает список.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, gap, 12, gap),
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

/// Блок пунктов меню сущности — [SheetPanel] ему не подходит: у меню свой вид,
/// утверждённый отдельно (прозрачная плашка на градиенте, только рамка), а у
/// остальных шторок — свои плашки с заливкой, и трогать их не просили.
class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.actions});

  final List<SheetAction> actions;

  /// Отступ строки от края блока. Разделитель начинается на 56 = 18 + иконка 22
  /// + просвет 16, то есть ровно под текстом.
  static const double pad = 18;

  /// Шторка стоит на обложке — тогда у блока свой вид.
  bool _cover(BuildContext context) =>
      _SheetSkinScope.of(context) == _SheetSkin.cover;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 6),
      child: Material(
        // Прозрачным блок бывает только над обложкой: там заливка спорила бы с
        // градиентом фона и возвращала бы шторке лоскутный вид, а держит блок
        // рамка. У шторки без обложки (сортировка, выбор из списка) фон ровный —
        // там всё как было: заливка и никакой кромки.
        color: _cover(context) ? Colors.transparent : sheetPanelColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kSheetPanelRadius),
          side: _cover(context)
              ? BorderSide(color: sheetPanelLineColor(context))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: pad + 38,
                  color: sheetLineColor(context),
                ),
              _SheetTile(action: actions[i]),
            ],
          ],
        ),
      ),
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
        ? t.danger
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
        padding: const EdgeInsets.symmetric(
          horizontal: _SheetGroup.pad,
          vertical: 15,
        ),
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

/// Дата под подписью в шапке шторки: «Добавлен 2 сент. 2026 г.», «Создан …».
///
/// Метка и дата хранятся врозь не ради перевода, а ради вида: метка идёт
/// приглушённой, сама дата — ярче, чтобы глаз цеплялся за неё, а не за слово.
class SheetMeta {
  const SheetMeta({required this.label, required this.date});

  final String label;
  final String date;
}

/// Дата события для шапки шторки. Метка времени пустая (трека нет в
/// библиотеке, плейлист заведён до появления `createdAt`) — `null`, и строки не
/// будет: прочерк на её месте не сказал бы ничего.
SheetMeta? sheetDateMeta(BuildContext context, String label, int? ms) {
  if (ms == null || ms <= 0) return null;
  return SheetMeta(
    label: label,
    date: stampDate(ms, Localizations.localeOf(context).languageCode),
  );
}

/// Строка [SheetMeta]. [onCover] — шапка стоит поверх обложки, и цвета там не
/// из темы, а белые: под чужой картинкой приглушённый текст темы пропадает.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.meta, this.onCover = false});

  final SheetMeta meta;
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final base = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${meta.label} ',
            style: TextStyle(color: onCover ? Colors.white60 : t.muted),
          ),
          TextSpan(
            text: meta.date,
            style: TextStyle(
              color: onCover ? Colors.white : t.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base,
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
    this.meta,
  });

  final String? cover;
  final String title;
  final String subtitle;
  final bool circle;

  /// Когда трек попал в библиотеку. Нет записи в библиотеке — нет и строки:
  /// у трека из поиска этой даты не существует.
  final SheetMeta? meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      // Обложка встаёт ровно по краю блоков ниже — прежние +4 при отступе 20
      // уводили её вправо от их линии.
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 10, kSheetEdge, 18),
      child: Row(
        children: [
          Cover(url: cover, size: 72, circle: circle),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleLarge?.copyWith(fontSize: 22),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium?.copyWith(fontSize: 15),
                  ),
                ],
                if (meta case final meta?) ...[
                  const SizedBox(height: 3),
                  _MetaLine(meta: meta),
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
    this.meta,
    this.subtitleTrailing,
  });

  final String? cover;
  final String title;
  final String subtitle;

  /// Довесок к подписи справа — офлайн-тег списка («· 🖫 1/177»), тот же, что на
  /// плитке в библиотеке. Виджетом, а не строкой: тег живой и со значком.
  final Widget? subtitleTrailing;

  /// Когда плейлист завели. У списков, заведённых до появления этой метки
  /// (`createdAt == 0`), даты нет — строка тогда не встаёт вовсе.
  final SheetMeta? meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final width = MediaQuery.of(context).size.width - kSheetEdge * 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 4, kSheetEdge, 8),
      child: ClipRRect(
        // То же скругление, что у блоков пунктов под ней.
        borderRadius: BorderRadius.circular(kSheetPanelRadius),
        child: SizedBox(
          width: width,
          // Карточка низкая: у плейлиста шапка не должна съедать шторку —
          // название с числом треков помещается и в полосу.
          height: width * 0.42,
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
                      Row(
                        children: [
                          // Число треков ужимается первым: тег справа короткий
                          // и обрезать его нечем.
                          Flexible(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          ?subtitleTrailing,
                        ],
                      ),
                    ],
                    if (meta case final meta?) ...[
                      const SizedBox(height: 2),
                      _MetaLine(meta: meta, onCover: true),
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
