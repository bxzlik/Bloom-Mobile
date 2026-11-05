/// A built-in theme for content over a surface that isn't the theme's: a cover's
/// picture or colour stays dark on a light theme, and a bright picture stays
/// bright on a dark one. `true` is the dark theme's ink.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../settings/user_fonts.dart';

final inkThemeProvider = Provider.family<ThemeData, bool>(
  (ref, dark) => buildBloomTheme(
    dark ? BloomThemes.dark : BloomThemes.light,
    fontFamily: ref.watch(uiFontProvider),
  ),
);
