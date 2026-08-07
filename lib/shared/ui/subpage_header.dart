/// Шапка подстраницы настроек: круглая «назад» и название широкой пилюлей.
///
/// Пилюля тянется на всю оставшуюся ширину, название по центру — так раздел
/// читается как заголовок экрана, а не как подпись рядом с кнопкой.
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
