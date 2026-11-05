/// How the full player's repeat and shuffle buttons show their modes.
library;

import 'dart:typed_data' show Uint8List;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/customization/custom_store.dart';
import 'package:bloom/features/player/player_bg_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/ui/full_player.dart';
import 'package:bloom/features/player/ui/player_ink.dart';
import 'package:bloom/features/settings/cover_accent.dart';
import 'package:bloom/l10n/app_localizations.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/glyphs.dart';

class _FakePlayback extends PlaybackController {
  _FakePlayback(this.initial);

  final PlaybackState initial;

  @override
  PlaybackState build() => initial;
}

const _track = Track(
  id: 'sc:1',
  name: 'Трек',
  artist: 'Артист',
  duration: Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

Future<void> _pump(
  WidgetTester tester, {
  PlayerRepeat repeat = PlayerRepeat.off,
  bool shuffle = false,
  BloomTokens? theme,
  String? bg,
  String? fx,
  String? cover,
  List<double>? rows,
  Color? color,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jsonStoreProvider.overrideWithValue(
          JsonStore.memory({'playerBg': ?bg, 'playerBgCoverFx': ?fx}),
        ),
        dbProvider.overrideWithValue(BloomDb.memory()),
        playbackProvider.overrideWith(
          () => _FakePlayback(
            PlaybackState(
              queue: const [_track],
              index: 0,
              repeat: repeat,
              shuffle: shuffle,
            ),
          ),
        ),
        playingProvider.overrideWith((ref) => Stream.value(false)),
        playingNowProvider.overrideWithValue(false),
        playheadProvider.overrideWith((ref) => const Stream.empty()),
        playerCoverProvider.overrideWithValue(cover),
        coverRowsProvider.overrideWith((ref, _) async => rows),
        playerBgColorProvider.overrideWith((ref, _) async => color),
      ],
      child: MaterialApp(
        theme: buildBloomTheme(theme ?? BloomThemes.dark),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FullPlayerBody(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// The last icon of this kind: the source pill above may show a small shuffle.
Color _colorOf(WidgetTester tester, BloomGlyph glyph) =>
    tester.widget<BloomIcon>(findGlyph(glyph).last).color!;

void main() {
  final t = BloomThemes.dark;
  final dimmed = t.iconFg.withValues(alpha: 0.5);

  testWidgets('both off: the plain icons at half brightness', (tester) async {
    await _pump(tester);
    expect(_colorOf(tester, Bi.repeat), dimmed);
    expect(_colorOf(tester, Bi.shuffle), dimmed);
    expect(findGlyph(Bi.repeatOne), findsNothing);
  });

  testWidgets('repeat all: the same loop, lit', (tester) async {
    await _pump(tester, repeat: PlayerRepeat.all);
    expect(_colorOf(tester, Bi.repeat), t.accent);
    expect(findGlyph(Bi.repeatOne), findsNothing);
  });

  testWidgets('repeat one: the loop with a 1 inside, lit', (tester) async {
    await _pump(tester, repeat: PlayerRepeat.one);
    expect(_colorOf(tester, Bi.repeatOne), t.accent);
    expect(findGlyph(Bi.repeat), findsNothing);
  });

  testWidgets('shuffle on: lit', (tester) async {
    await _pump(tester, shuffle: true);
    expect(_colorOf(tester, Bi.shuffle), t.accent);
  });

  group('ink over the background', () {
    final dark = BloomThemes.dark;
    final light = BloomThemes.light;

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Color fillOf(WidgetTester tester) =>
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!;

    testWidgets('a light theme with no background keeps its own ink', (
      tester,
    ) async {
      await _pump(tester, theme: light);
      await settle(tester);
      expect(_colorOf(tester, Bi.kebab), light.iconFg);
      expect(_colorOf(tester, Bi.skipNextBold), light.iconFg);
    });

    testWidgets('a gradient dark on top and light below: each row its own', (
      tester,
    ) async {
      await _pump(
        tester,
        theme: light,
        bg: 'color',
        color: const Color(0xFF333333),
      );
      await settle(tester);
      expect(_colorOf(tester, Bi.kebab), dark.iconFg);
      expect(_colorOf(tester, Bi.skipNextBold), light.iconFg);
      // The background stays the theme's.
      expect(fillOf(tester), light.bg);
    });

    testWidgets('a white cover under the film: dark on top, light below', (
      tester,
    ) async {
      await _pump(
        tester,
        theme: light,
        bg: 'cover',
        cover: 'white',
        rows: List.filled(32, 1.0),
      );
      await settle(tester);
      expect(_colorOf(tester, Bi.kebab), light.iconFg);
      expect(_colorOf(tester, Bi.skipNextBold), dark.iconFg);
    });

    testWidgets('a bare bright cover on a dark theme takes dark ink', (
      tester,
    ) async {
      await _pump(
        tester,
        bg: 'cover',
        fx: 'original',
        cover: 'bright',
        rows: List.filled(32, 0.9),
      );
      await settle(tester);
      expect(_colorOf(tester, Bi.kebab), light.iconFg);
      expect(fillOf(tester), dark.bg);
    });

    testWidgets('a matching ink keeps the theme accent', (tester) async {
      const red = Color(0xFFE03030);
      final own = BloomTokens.from(
        bg: dark.bg,
        blockColor: dark.blockColor,
        accent: red,
      );
      await _pump(
        tester,
        theme: own,
        bg: 'cover',
        cover: 'dark',
        rows: List.filled(32, 0.1),
        shuffle: true,
      );
      await settle(tester);
      expect(_colorOf(tester, Bi.shuffle), red);
    });
  });

  test('lightness is counted row by row and ignores alpha', () {
    expect(
      rowLightness(
        Uint8List.fromList([
          255,
          255,
          255,
          0,
          255,
          255,
          255,
          0,
          0,
          0,
          0,
          255,
          0,
          0,
          0,
          255,
        ]),
        width: 2,
      ),
      [closeTo(1, 0.001), closeTo(0, 0.001)],
    );
  });

  test('dark ink only over a light background', () {
    expect(inkIsDark(0.9), isTrue);
    expect(inkIsDark(0.2), isFalse);
  });
}
