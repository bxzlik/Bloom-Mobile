/// Главная. Пока сделана только шапка из референса (пилюля профиля + круглые
/// кнопки). Созвездие «Моя волна», карточка «Недавние» и ленты «Для вас» /
/// «Популярное» — следующим заходом.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_mark.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TopBar(),
          Expanded(
            child: Center(
              child: Text(
                'Здесь будет «Моя волна», недавние и ленты',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: t.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          // Пилюля профиля: знак bloom + имя. Знак без подложки — он и так
          // читается на плёнке пилюли. Высота ровно как у круглых кнопок
          // справа, иначе шапка выглядит съехавшей.
          Container(
            height: kHeaderControl,
            padding: const EdgeInsets.fromLTRB(15, 0, 19, 0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.pill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BloomMark(size: 20, color: t.text),
                const SizedBox(width: 10),
                Text('Bloom', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const Spacer(),
          CircleIconButton(icon: SolarIconsOutline.bell, onTap: () {}),
          const SizedBox(width: 8),
          CircleIconButton(
            icon: SolarIconsOutline.magnifier,
            onTap: () => context.go('/home/search'),
          ),
          const SizedBox(width: 8),
          // user-circle в шрифте Solar нарисован диском — берём настоящий SVG.
          CircleSvgButton(
            asset: 'assets/icons/user-circle-linear.svg',
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
