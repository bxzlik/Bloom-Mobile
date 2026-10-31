/// Plays per day for the last 30 days round a ring: a segment a day,
/// clockwise from the top, today last. Shades of the theme by the busiest day
/// shown, empty days faint. The middle tells the 30 days' total, or the day
/// under the finger.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/days_store.dart';
import '../../../core/store/play_stats.dart';

const int _days = 30;
const double _stroke = 10;
const double _gapDeg = 3;

class ActivityRing extends ConsumerStatefulWidget {
  const ActivityRing({super.key, this.size = 220});

  final double size;

  @override
  ConsumerState<ActivityRing> createState() => _ActivityRingState();
}

class _ActivityRingState extends ConsumerState<ActivityRing> {
  /// The day under the finger; -1 is none.
  int _hot = -1;

  double get _r => widget.size / 2 - _stroke;

  DateTime _dateAt(int i) {
    final d = DateTime.now();
    return DateTime(d.year, d.month, d.day - (_days - 1 - i));
  }

  /// Only over the band of the ring, a little wider than its stroke; anywhere
  /// else lets go of the day.
  void _touch(Offset p) {
    final c = widget.size / 2;
    final dx = p.dx - c, dy = p.dy - c;
    final d = math.sqrt(dx * dx + dy * dy);
    var hot = -1;
    if ((d - _r).abs() <= _stroke * 2) {
      final a = (math.atan2(dy, dx) * 180 / math.pi + 90 + 360) % 360;
      hot = math.min(_days - 1, (a / (360 / _days)).floor());
    }
    if (hot != _hot) setState(() => _hot = hot);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final perDay = ref.watch(playStatsProvider.select((s) => s.perDay));
    final counts = [
      for (var i = 0; i < _days; i++) perDay[dayKey(_dateAt(i))] ?? 0,
    ];
    final total = counts.fold(0, (a, b) => a + b);
    final hot = _hot;

    return GestureDetector(
      onTapDown: (d) => _touch(d.localPosition),
      onPanDown: (d) => _touch(d.localPosition),
      onPanUpdate: (d) => _touch(d.localPosition),
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _RingPainter(counts: counts, hot: hot, tokens: t, r: _r),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${hot >= 0 ? counts[hot] : total}',
                  style: bloomText(size: 28, weight: 700, color: t.text),
                ),
                const SizedBox(height: 4),
                Text(
                  (hot >= 0
                          ? DateFormat.MMMd(
                              Localizations.localeOf(context).toString(),
                            ).format(_dateAt(hot))
                          : context.l.profileActivityDays)
                      .toUpperCase(),
                  style: bloomText(
                    size: 10,
                    weight: 700,
                    color: t.text2,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.counts,
    required this.hot,
    required this.tokens,
    required this.r,
  });

  final List<int> counts;
  final int hot;
  final BloomTokens tokens;
  final double r;

  /// White to grey on a dark theme, black to grey on a light one; an empty
  /// day only fades.
  Color _tone(int n, int max) {
    final t = tokens;
    if (n <= 0) return t.text.withValues(alpha: 0.1);
    final k = n / max;
    final toBlock = k >= 0.75
        ? 0.0
        : k >= 0.5
        ? 0.28
        : k >= 0.25
        ? 0.5
        : 0.7;
    return Color.lerp(t.text, t.blockColor, toBlock)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final max = math.max(1, counts.fold(0, math.max));
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    const step = 2 * math.pi / _days;
    const gap = _gapDeg * math.pi / 180;
    for (var i = 0; i < counts.length; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * step + gap / 2,
        step - gap,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == hot ? _stroke * 1.6 : _stroke
          ..color = _tone(counts[i], max),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.hot != hot || old.tokens != tokens || !_same(old.counts, counts);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
