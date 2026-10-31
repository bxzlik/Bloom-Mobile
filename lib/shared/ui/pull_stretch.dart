/// A full-bleed block at the top of a page that grows up into a pull past the
/// top, so the springy edge shows more of it rather than the page's colour.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class PullStretch extends StatefulWidget {
  const PullStretch({super.key, required this.child});

  /// Laid out taller by the pull and kept to the bottom edge; whatever clips
  /// it has to sit inside, or the pull gets clipped away.
  final Widget child;

  @override
  State<PullStretch> createState() => _PullStretchState();
}

class _PullStretchState extends State<PullStretch> {
  ScrollPosition? _pos;
  double _pull = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos == _pos) return;
    _pos?.removeListener(_onScroll);
    _pos = pos?..addListener(_onScroll);
    _pull = _read();
  }

  @override
  void dispose() {
    _pos?.removeListener(_onScroll);
    super.dispose();
  }

  double _read() {
    final p = _pos;
    if (p == null || !p.hasPixels || !p.hasContentDimensions) return 0;
    return math.max(0.0, p.minScrollExtent - p.pixels);
  }

  void _onScroll() {
    final pull = _read();
    if (pull != _pull) setState(() => _pull = pull);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => OverflowBox(
      alignment: Alignment.bottomCenter,
      minHeight: box.maxHeight + _pull,
      maxHeight: box.maxHeight + _pull,
      child: widget.child,
    ),
  );
}
