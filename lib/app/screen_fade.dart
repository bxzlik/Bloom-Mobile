/// Over the whole app: a screen that replaces another comes up out of the
/// theme's background, and fades into it before it goes. Taps stop here while
/// it fades out.
library;

import 'package:flutter/widgets.dart';

class ScreenFade extends StatefulWidget {
  const ScreenFade({
    super.key,
    required this.bg,
    required this.fadeIn,
    required this.child,
  });

  final Color bg;

  /// False for the first screen of a launch: the splash hands it over as is.
  final bool fadeIn;
  final Widget child;

  @override
  State<ScreenFade> createState() => ScreenFadeState();
}

class ScreenFadeState extends State<ScreenFade>
    with SingleTickerProviderStateMixin {
  static const Duration _in = Duration(milliseconds: 320);
  static const Duration _out = Duration(milliseconds: 200);

  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: _in,
    reverseDuration: _out,
    value: widget.fadeIn ? 0 : 1,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _shown,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInQuad,
  );
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.fadeIn) _shown.forward();
  }

  /// Fades the screen into the background; done once nothing of it shows.
  Future<void> out() async {
    if (!mounted) return;
    setState(() => _leaving = true);
    await _shown.reverse().orCancel.catchError((_) {});
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.bg,
    child: IgnorePointer(
      ignoring: _leaving,
      child: FadeTransition(opacity: _opacity, child: widget.child),
    ),
  );
}
