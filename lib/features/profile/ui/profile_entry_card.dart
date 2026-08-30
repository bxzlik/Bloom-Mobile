/// Карточка-вход под профилем: статистика, достижения и входы в «Итоги».
///
/// Вид задал он макетом: слева крупное число со значком, справа второе число, у
/// края — плитка 56 (коллаж обложек топа / медаль). Отсюда и рост карточки —
/// плитка плюс поля.
///
/// Отдельным файлом, а не приватным классом страницы, ради [kProfileEntryHeight]:
/// его спрашивают и «Итоги» (`wrapped/ui/wrapped_entries.dart`), у которых своя
/// начинка, но тот же рост — иначе ряд входов идёт ступеньками.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/glass.dart';

/// Рост карточки-входа: плитка 56 плюс поля 18 сверху и снизу.
const double kProfileEntryHeight = 92;

/// Заливка ряда входов — ВДВОЕ слабее общей `pill`: 8/245 вместо 16/245, то
/// есть #121212 при фоне #0a0a0a. Он попросил эти три блока темнее обычных
/// плашек; рамки у них при этом нет — форму держит сама заливка.
Color profileEntryFill(BloomTokens t) => Color.lerp(
  t.blockColor,
  t.isLight ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
  8 / 245,
)!;

class ProfileEntryCard extends StatelessWidget {
  const ProfileEntryCard({
    super.key,
    required this.value,
    required this.icon,
    required this.side,
    required this.tile,
    required this.onTap,
  });

  final String value;
  final IconData icon;
  final String side;
  final Widget tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return GlassBox(
      color: profileEntryFill(t),
      borderRadius: BorderRadius.circular(t.radius),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: kProfileEntryHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
            child: Row(
              children: [
                Text(value, style: theme.headlineSmall?.copyWith(fontSize: 30)),
                const SizedBox(width: 8),
                Icon(icon, size: 16, color: t.muted),
                const Spacer(),
                Text(side, style: theme.titleLarge?.copyWith(fontSize: 20)),
                const SizedBox(width: 14),
                tile,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
