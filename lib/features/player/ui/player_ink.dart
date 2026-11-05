/// The player's content over its own background. A background may be dark on top
/// and light below, so no one ink suits the whole screen: each row of controls
/// looks at what really lies under it and picks light or dark for itself. The
/// background itself is never touched.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import 'ink_theme.dart';
import 'player_backdrop.dart';

/// Lightness above which dark ink reads better than light: where the contrast of
/// the two icon colours meets.
const double kInkFlipLightness = 0.48;

/// How fast a row changes ink: quick enough to arrive with the new cover.
const Duration _kInkFade = Duration(milliseconds: 300);

/// Whether dark ink goes over this lightness.
bool inkIsDark(double lightness) => lightness > kInkFlipLightness;

/// The player's context above all the [PlayerInkZone]s. Sheets open from here,
/// or a sheet opened from a row would take that row's ink instead of the theme.
class PlayerSheetAnchor extends InheritedWidget {
  const PlayerSheetAnchor({
    super.key,
    required this.anchor,
    required super.child,
  });

  final BuildContext anchor;

  /// Where to open a sheet from. Outside the player, [context] itself.
  static BuildContext of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerSheetAnchor>()?.anchor ??
      context;

  @override
  bool updateShouldNotify(PlayerSheetAnchor oldWidget) => false;
}

/// One row of controls: takes the ink for the background under its own centre.
class PlayerInkZone extends ConsumerStatefulWidget {
  const PlayerInkZone({super.key, required this.at, required this.child});

  /// Where the row is expected, 0–1 down the screen. The first frame goes by
  /// this, and after layout the row measures itself.
  final double at;

  final Widget child;

  @override
  ConsumerState<PlayerInkZone> createState() => _PlayerInkZoneState();
}

class _PlayerInkZoneState extends ConsumerState<PlayerInkZone> {
  late double _y = widget.at;

  /// The last lightness known: a new cover takes a moment to read, and blinking
  /// to the theme's ink between two dark ones would be worse than waiting.
  double? _light;

  void _measure(Duration _) {
    if (!mounted) return;
    final box = context.findRenderObject();
    final root = PlayerSheetAnchor.of(context).findRenderObject();
    if (box is! RenderBox || root is! RenderBox) return;
    if (!box.hasSize || !root.hasSize || root.size.height <= 0) return;
    final y =
        box.localToGlobal(box.size.center(Offset.zero), ancestor: root).dy /
        root.size.height;
    if ((y - _y).abs() > 0.005) setState(() => _y = y.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<BloomTokens>()!;
    final light = playerBgLightAt(ref, _y, tokens);
    if (!light.isLoading) _light = light.value;
    WidgetsBinding.instance.addPostFrameCallback(_measure);

    return AnimatedTheme(
      data: _inkFor(theme, tokens, _light),
      duration: _kInkFade,
      curve: Curves.easeOut,
      child: widget.child,
    );
  }

  /// The theme for this lightness. With no background, the theme as it is.
  ThemeData _inkFor(ThemeData theme, BloomTokens tokens, double? light) {
    if (light == null) return theme;
    final dark = inkIsDark(light);
    // A match keeps the theme's own accent. Otherwise the theme's accent is the
    // very colour that vanishes here.
    final base = dark == tokens.isLight
        ? theme
        : ref.watch(inkThemeProvider(!dark));
    final ink = base.extension<BloomTokens>()!;
    // Secondary text counts from the theme's plate, which isn't what's under it
    // now: the ink's own colour, quieter, reads on any background.
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: ink.text.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

/// System bars for the open player: the status icons follow what's under them,
/// the rest stays the theme's.
SystemUiOverlayStyle playerBarsStyle(BloomTokens theme, double? statusLight) {
  final style = systemBarsStyle(theme);
  if (statusLight == null) return style;
  final dark = inkIsDark(statusLight);
  return style.copyWith(
    statusBarBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarIconBrightness: dark ? Brightness.dark : Brightness.light,
  );
}
