/// Динамика места в чарте: «▲2» / «▼3» / «нов.» / «—». Порт десктопного
/// `ChartTrend.tsx`.
///
/// Данные есть только у треков из чарта ([Track.chartPos]). Рисуется и на
/// карточке витрины ([chip] — тёмная пилюля поверх обложки), и в строке
/// страницы «Чарт» — голым бейджем под номером, как у Яндекса.
///
/// Цвета семантические и к акценту приложения отношения не имеют — они одни
/// в обеих темах.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';

const Color _up = Color(0xFF4EC98A);
const Color _down = Color(0xFFE0655F);
const Color _new = Color(0xFFE8C15A);

class ChartTrend extends StatelessWidget {
  const ChartTrend({super.key, required this.track, this.chip = false});

  final Track track;

  /// Пилюлей поверх обложки (витрина), а не голым бейджем (строка).
  final bool chip;

  @override
  Widget build(BuildContext context) {
    if (track.chartPos == null) return const SizedBox.shrink();
    final t = context.bloom;
    final l = context.l;
    final shift = track.chartShift;
    final base = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final (String label, Widget body) = track.chartNew
        ? (
            l.chartNew,
            Text(
              l.chartNewShort.toUpperCase(),
              style: base?.copyWith(
                color: _new,
                fontSize: 9.5,
                letterSpacing: 0.6,
              ),
            ),
          )
        : shift == 0
        ? (l.chartSame, Text('—', style: base?.copyWith(color: t.muted)))
        : (
            shift > 0 ? l.chartUp(shift) : l.chartDown(-shift),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shift > 0 ? '▲' : '▼',
                  style: base?.copyWith(
                    color: shift > 0 ? _up : _down,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  '${shift.abs()}',
                  style: base?.copyWith(color: shift > 0 ? _up : _down),
                ),
              ],
            ),
          );

    final content = Semantics(
      label: label,
      excludeSemantics: true,
      child: body,
    );
    if (!chip) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: content,
      ),
    );
  }
}
