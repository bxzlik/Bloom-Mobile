import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:flutter_test/flutter_test.dart';

/// The icons on screen drawn with this glyph.
Finder findGlyph(BloomGlyph glyph) =>
    find.byWidgetPredicate((w) => w is BloomIcon && w.glyph == glyph);
