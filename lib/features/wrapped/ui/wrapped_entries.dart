/// Входы в «Итоги» на странице профиля — порт десктопных `WrappedYearBanner` и
/// `MonthTakeoverCard`.
///
/// Их два, и появляются они по разным правилам:
///   • [WrappedMonthCard] ПОДМЕНЯЕТ карточку статистики, пока итоги месяца не
///     посмотрели; после просмотра карточка возвращается на место до следующего
///     месяца. Своей постоянной плашки у месяца намеренно нет: пересмотреть
///     итоги можно кнопкой внизу шторки статистики;
///   • [WrappedYearBanner] стоит над карточками и живёт ТОЛЬКО в декабрьском
///     окне (см. `periods.dart`) — в остальное время года плашки просто нет.
///
/// Оба входа знают свой период и открывают шторку сразу на нём: экрана выбора
/// периода больше не существует.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/glass.dart';
import '../../profile/ui/profile_entry_card.dart'
    show kProfileEntryHeight, profileEntryFill;
import '../periods.dart';
import '../wrapped_data.dart';
import '../wrapped_format.dart';
import 'wrapped_sheet.dart';

/// Период пробега блика по волне и период её течения.
const int kWrYearShineMs = 4200;
const int kWrYearFlowMs = 9000;

/// Подменённая карточка статистики: заголовок с меткой «Новое», даты периода и
/// капсула «Смотреть». Форма — та же, что у соседних карточек профиля, чтобы
/// ряд входов читался единым.
class WrappedMonthCard extends StatelessWidget {
  const WrappedMonthCard({super.key, required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;

    return _EntryShell(
      onTap: () =>
          showWrappedSheet(context, period: PeriodKind.month, data: data),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(child: _EntryTitle(l.wrMonth)),
                    const SizedBox(width: 9),
                    const _NewBadge(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  periodDatesLabel(data.range, locale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _WatchPill(),
        ],
      ),
    );
  }
}

/// Плашка «Итоги года»: та же карточка, что у соседей по ряду.
/// Единственное украшение — тонкая дуга во всю ширину, по которой бежит блик;
/// она нарисована дважды (тусклая основа и яркий дубль под подвижным
/// градиентом), как `.wry-line` / `.wry-shine` на ПК.
class WrappedYearBanner extends StatefulWidget {
  const WrappedYearBanner({super.key, required this.data, this.unseen = true});

  final WrappedData data;

  /// Год ещё не смотрели — горит метка «Новое».
  final bool unseen;

  @override
  State<WrappedYearBanner> createState() => _WrappedYearBannerState();
}

class _WrappedYearBannerState extends State<WrappedYearBanner>
    with TickerProviderStateMixin {
  /// Течение волны. От его же фазы считается вертикальный дрейф: возьми дрейф
  /// свой период — на стыке цикла линия дёргалась бы.
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kWrYearFlowMs),
  )..repeat();

  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kWrYearShineMs),
  )..repeat();

  @override
  void dispose() {
    _flow.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;

    return _EntryShell(
      onTap: () =>
          showWrappedSheet(context, period: PeriodKind.year, data: widget.data),
      // `StackFit.expand` обязателен: непозиционированный ребёнок иначе встаёт
      // по ВЕРХНЕМУ краю стопки, и текст плашки сидит выше середины (заметил он).
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_flow, _shine]),
                builder: (_, _) => CustomPaint(
                  painter: _WavePainter(
                    flow: _flow.value,
                    shine: _shine.value,
                    color: t.text,
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(child: _EntryTitle(l.wrYear)),
                        if (widget.unseen) ...[
                          const SizedBox(width: 9),
                          const _NewBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${l.wrPlaysN(widget.data.plays)} · '
                      '${fmtListenTime(l, widget.data.seconds)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const _WatchPill(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Волна с бегущим бликом.
///
/// Путь нарисован ВДВОЕ шире плашки и содержит два одинаковых периода, а
/// анимация двигает его ровно на один — кадр «до» и кадр «после» совпадают, и
/// шва на стыке нет. Блик — тот же путь, обведённый подвижным градиентом:
/// подсветка едет строго по линии, повторяя её изгибы.
class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.flow,
    required this.shine,
    required this.color,
  });

  /// Фазы 0..1: течение волны и пробег блика.
  final double flow;
  final double shine;
  final Color color;

  /// Ширина окна блика в долях плашки.
  static const double _shineWidth = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final mid = size.height / 2;
    // Амплитуда и дрейф — те же 4–5 точек, что у `--wry-sway` на ПК.
    final sway = math.sin(flow * 2 * math.pi) * 4.5;

    final path = Path()..moveTo(0, mid);
    // Половина ширины на период: два периода на видимой части, ещё два — в
    // запасе справа, откуда волна и «втекает».
    final period = w / 2;
    for (var i = 0; i < 4; i++) {
      final x = i * period;
      final up = i.isEven ? -1 : 1;
      path.cubicTo(
        x + period / 3,
        mid + up * 21,
        x + period * 2 / 3,
        mid + up * 21,
        x + period,
        mid,
      );
    }

    canvas.save();
    canvas.translate(-flow * period * 2, sway);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.16),
    );

    // Окно блика ездит слева направо в координатах ПЛАШКИ, поэтому его
    // положение поправлено на сдвиг самой волны.
    final head =
        (shine * (1 + _shineWidth * 2) - _shineWidth) * w + flow * period * 2;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..shader =
            LinearGradient(
              colors: [
                color.withValues(alpha: 0),
                color,
                color.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTWH(head - _shineWidth * w, 0, _shineWidth * 2 * w, 1),
            ),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.flow != flow || old.shine != shine || old.color != color;
}

/// Общая оболочка входа: та же стеклянная плашка и та же затемнённая заливка
/// [profileEntryFill], что у соседних карточек профиля.
///
/// Заливка здесь обязательна, а не украшение: голая прозрачная карточка при
/// включённой прозрачности пропадала на светлых обоях — белый заголовок
/// ложился прямо на картинку (его скриншот).
///
/// Рост — общий [kProfileEntryHeight]: входы стоят одним рядом со статистикой и
/// достижениями, и своя высота у них читалась бы ступенькой (его правка).
class _EntryShell extends StatelessWidget {
  const _EntryShell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GlassBox(
      color: profileEntryFill(t),
      borderRadius: BorderRadius.circular(t.radius),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: kProfileEntryHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _EntryTitle extends StatelessWidget {
  const _EntryTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: context.bloom.text,
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      height: 1.1,
    ),
  );
}

/// Метка «Новое» — гаснет после первого просмотра.
class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.text,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.l.wrNew.toUpperCase(),
        style: TextStyle(
          color: t.bg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Единственное цветное пятно карточки — залито акцентом.
/// Стрелки внутри нет: капсула и так читается кнопкой.
class _WatchPill extends StatelessWidget {
  const _WatchPill();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.l.wrWatch,
        style: TextStyle(
          color: t.accentText,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
