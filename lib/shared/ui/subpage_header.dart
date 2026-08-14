/// Шапка подстраницы настроек: круглая «назад» и название широкой пилюлей.
///
/// Пилюля тянется на всю оставшуюся ширину, название по центру — так раздел
/// читается как заголовок экрана, а не как подпись рядом с кнопкой.
///
/// Рядом — [SubPage], каркас такой страницы целиком: шапка прибита, листается
/// только содержимое под ней.
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../app/theme/tokens.dart';
import 'atoms.dart';

class SubPageHeader extends StatelessWidget {
  const SubPageHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Row(
      children: [
        CircleIconButton(icon: SolarIconsOutline.arrowLeft, onTap: onBack),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: kHeaderControl,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.pill,
              // Скруглена полностью, а не на радиус темы: рядом круглая
              // кнопка, и эти двое должны читаться одной парой.
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ],
    );
  }
}

/// Каркас подстраницы настроек: [SubPageHeader] прибит сверху, скролл живёт
/// только в содержимом под ним.
///
/// Так «назад» и название раздела всегда под пальцем: раньше шапка ехала
/// первым элементом общего списка и уползала за край с первым же движением.
class SubPage extends StatelessWidget {
  const SubPage({
    super.key,
    required this.title,
    required this.onBack,
    required this.children,
  });

  final String title;
  final VoidCallback onBack;

  /// Содержимое страницы — дети скроллящегося списка под шапкой.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SubPageHeader(title: title, onBack: onBack),
          ),
          // Часть просвета — распоркой, а не отступом списка: она остаётся на
          // месте при скролле, и содержимое обрезается не по самому краю
          // пилюли, а на этот зазор ниже. Вплотную к ней карточки касаются
          // некрасиво.
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              // Вместе с распоркой сверху выходят прежние 22 — просвет под
              // шапкой в покое не изменился. Снизу добавлены бары каркаса:
              // они плавают над содержимым.
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                24 + bottomBarsInset(context),
              ),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
