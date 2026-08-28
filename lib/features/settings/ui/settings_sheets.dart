/// Строка «название — что сейчас выбрано» и шторки выбора к ней.
///
/// Общие для «Плеера» и «Мини плеера»: страницы разъехались, а строки и шторки
/// на них одни и те же — раздвоив их, мы получили бы два набора, которые
/// разойдутся на первой же правке.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/bloom_sheet.dart';

/// Строка настройки: название, под ним выбранное, справа — ЗНАЧОК ВЫБРАННОГО.
///
/// Своей плёнки у строки нет — она живёт внутри `SettingsGroupCard`, одного на
/// всю группу: связанные настройки стоят одной карточкой, как в корневых
/// «Настройках».
///
/// Шеврона нет: строка и так открывается вся целиком, а стрелка занимала место
/// справа, ничего не сообщая. Вместо неё — тот же значок, что стоит у выбранного
/// варианта в шторке: выбор видно, не открывая её. У строк, которые настраивают
/// НАБОР («Индикаторы прогресса», «Кнопки управления») или сразу несколько
/// настроек («Оформление» текста), значок один и общий — про что строка, а не
/// про первый включённый пункт.
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
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
            // Кружок-подложка — тот же, что у строк с ползунком в «Интерфейсе»
            // («Яркость акцента» и соседи): значок справа читается как значок
            // строки, а не как приклеившаяся к краю картинка. Коробка одна на
            // все значки: они разной ширины (полоска слайдера шире круга
            // пластинки), а стоять в колонке должны ровно.
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: IconTheme(
                data: IconThemeData(color: t.iconFg, size: 21),
                child: glyph,
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
Widget settingsSheetHeader(
  BuildContext context,
  String title, [
  String? subtitle,
]) {
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

/// Шторка «одно из»: список вариантов; выбор применяется и ЗАКРЫВАЕТ шторку.
///
/// Закрывает, в отличие от шторок анимации: настройка меняет карточку над
/// таб-баром, а шторка её собой и закрывает — смотреть на результат из-под неё
/// всё равно нечем (та же причина, что у выбора вида таб-бара).
Future<void> pickOneSheet<T>({
  required BuildContext context,
  String? title,
  String? subtitle,
  required List<T> values,
  required T current,
  required IconData Function(T) icon,
  required String Function(T) label,

  /// Пояснение под названием варианта. `null` — вариантам хватает подписи.
  String Function(T)? sub,

  /// Можно ли выбрать вариант. `null` — можно все; иначе недоступные гаснут и
  /// не нажимаются (пока что это один «Фон приложения» без самого фона).
  bool Function(T)? enabled,
  required void Function(T) apply,
}) async {
  final picked = await showBloomSheetChild<T>(
    context: context,
    // Шапки может не быть вовсе: у «Фона плеера» варианты объясняют себя сами.
    header: title == null
        ? null
        : settingsSheetHeader(context, title, subtitle),
    // Закрывать шторку надо ЕЁ контекстом: она живёт в корневом навигаторе, а
    // страница — во вложенном, и `pop` со страничным закрыл бы «Настройки».
    child: Builder(
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            SheetOptionTile(
              icon: icon(value),
              label: label(value),
              sub: sub?.call(value),
              active: value == current,
              enabled: enabled?.call(value) ?? true,
              onTap: () => Navigator.of(sheetContext).pop(value),
            ),
        ],
      ),
    ),
  );
  if (picked != null) apply(picked);
}

/// Строка варианта в шторке: значок, подпись и отметка справа. Каждая — своим
/// блоком ([SheetPanel]), как пункты обычной шторки: сплошным списком с
/// разделителями выбранную строку не подсветить.
class SheetOptionTile extends StatelessWidget {
  const SheetOptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.sub,
    this.check = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;

  /// Пояснение под названием. `null` — строка в одну строку, как у мини-плеера.
  final String? sub;

  /// Выбранный вариант (или включённый индикатор).
  final bool active;

  /// Строка набора: справа не галочка, а квадратик-флажок, и подсветки строки
  /// нет — включённых бывает несколько, и подсвеченными оказались бы почти все.
  final bool check;

  /// Вариант недоступен: строка гасится целиком и не нажимается. Прячем такие
  /// строки не совсем — из шторки должно быть видно, ЧТО можно включить, и
  /// пояснение под названием говорит, чего для этого не хватает.
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final tint = active && !check;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: _panel(context, t, theme, tint),
    );
  }

  Widget _panel(
    BuildContext context,
    BloomTokens t,
    TextTheme theme,
    bool tint,
  ) {
    return SheetPanel(
      // Строки списка стоят вплотную друг к другу: сами они крупные, и полный
      // просвет блока рвал бы список на отдельные плашки.
      gap: 3,
      children: [
        InkWell(
          onTap: enabled ? onTap : null,
          child: Ink(
            color: tint ? t.accent.withValues(alpha: 0.12) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 15, 18, 15),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? t.accent.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(t.radius * 0.6),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: active ? t.accent : t.iconFg,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.titleMedium,
                        ),
                        if (sub case final text?) ...[
                          const SizedBox(height: 2),
                          Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodySmall,
                          ),
                        ],
                      ],
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
