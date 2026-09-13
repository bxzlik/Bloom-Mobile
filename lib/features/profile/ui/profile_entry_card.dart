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

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/glass.dart';

/// Рост карточки-входа: плитка 56 плюс поля 18 сверху и снизу.
const double kProfileEntryHeight = 92;

/// Чередование числа и надписи (порт десктопного `SwapValue`): сколько висит
/// каждая из двух, сколько едет слайд и высота слота — она же путь слайда.
const int kProfileSwapHoldMs = 10000;
const int kProfileSwapMs = 800;
const double kProfileSwapHeight = 40;

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
    this.alt,
  });

  final String value;
  final IconData icon;
  final String side;
  final Widget tile;
  final VoidCallback onTap;

  /// Задан — левый слот чередует число с этой надписью (см. [_SwapValue]).
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final valueStyle = theme.headlineSmall?.copyWith(fontSize: 30);
    final number = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: valueStyle),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: t.muted),
      ],
    );
    final alt = this.alt;

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
                if (alt == null) ...[
                  number,
                  const Spacer(),
                ] else ...[
                  // Слот во всю свободную ширину: правая половина карточки не
                  // дёргается при смене, а длинная надпись на узком экране
                  // ужимается, а не выталкивает время.
                  Expanded(
                    child: _SwapValue(
                      first: number,
                      // Тот же кегль, что у числа: слайд читается как подмена
                      // одного заголовка другим. Трекинг чуть слабее — как на ПК.
                      second: Text(
                        alt,
                        maxLines: 1,
                        style: valueStyle?.copyWith(letterSpacing: -0.4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
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

/// Слот, который раз в [kProfileSwapHoldMs] сменяет [first] на [second] и
/// обратно: уходящее уезжает вверх, приходящее подъезжает снизу (слот обрезан).
///
/// Первый показ без анимации: контроллер стартует в конечном кадре, иначе на
/// монтировании второй слой мигнул бы поверх первого.
class _SwapValue extends StatefulWidget {
  const _SwapValue({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  State<_SwapValue> createState() => _SwapValueState();
}

class _SwapValueState extends State<_SwapValue>
    with SingleTickerProviderStateMixin {
  /// Кривая слайда — `cubic-bezier(.22,.61,.36,1)` десктопа.
  static const Curve _curve = Cubic(0.22, 0.61, 0.36, 1);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kProfileSwapMs),
    value: 1,
  );
  late final Timer _timer;
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: kProfileSwapHoldMs),
      (_) => _swap(),
    );
  }

  void _swap() {
    setState(() => _phase ^= 1);
    // Системное «убрать анимации» — смена мгновенная, как reduced-motion на ПК.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: kProfileSwapHeight,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final p = _curve.transform(_c.value);
            Widget layer(int i, Widget child) {
              final incoming = _phase == i;
              // Слой ростом во весь слот: сдвиг на ±1 уносит его ровно за
              // край обрезки, и макушки букв не торчат.
              return Opacity(
                opacity: incoming ? p : 1 - p,
                child: FractionalTranslation(
                  translation: Offset(0, incoming ? 1 - p : -p),
                  child: SizedBox(
                    height: kProfileSwapHeight,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FittedBox(fit: BoxFit.scaleDown, child: child),
                    ),
                  ),
                ),
              );
            }

            return Stack(
              children: [layer(0, widget.first), layer(1, widget.second)],
            );
          },
        ),
      ),
    );
  }
}
