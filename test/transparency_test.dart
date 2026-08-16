/// Прозрачность: формулы стекла, персист, гейт оверлеев и сами поверхности.
///
/// Проверяем то, что ломается тихо. Яркость стекла считается той же формулой,
/// что на ПК (`applyTransparency`), — разойдись она, и одна и та же цифра дала
/// бы там и здесь разное стекло. Тумблер оверлеев — ПОДРЕЖИМ: при выключенной
/// прозрачности стекла не должно быть нигде. А ползунок в настройках
/// показывает «уровень прозрачности», то есть ОБРАТНОЕ тому, что лежит в
/// хранилище.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/settings/transparency_store.dart';
import 'package:bloom/shared/ui/bloom_sheet.dart';
import 'package:bloom/shared/ui/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

/// Экран с одной стеклянной плашкой.
Future<void> _pumpBox(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: const Scaffold(
          body: GlassGroup(
            child: GlassBox(child: SizedBox(width: 100, height: 40)),
          ),
        ),
      ),
    ),
  );
}

/// Экран с кнопкой, открывающей шторку без обложки.
Future<void> _pumpSheet(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBloomSheetChild<void>(
                context: context,
                child: const SizedBox(height: 80),
              ),
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
}

/// Заливка плашки: `GlassBox` красит её материалом.
Color _fillOf(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(
        of: find.byType(GlassBox),
        matching: find.byType(Material),
      ),
    )
    .color!;

void main() {
  group('формулы', () {
    test('яркость стекла — те же три точки, что на ПК', () {
      // 0 → 0.4 (тёмное), 50 → 1.0 (нейтрально), 100 → 1.8 (светлое).
      expect(const Transparency(glassStr: 0).brightness, closeTo(0.4, 1e-9));
      expect(const Transparency(glassStr: 25).brightness, closeTo(0.7, 1e-9));
      expect(const Transparency(glassStr: 50).brightness, closeTo(1, 1e-9));
      expect(const Transparency(glassStr: 75).brightness, closeTo(1.4, 1e-9));
      expect(const Transparency(glassStr: 100).brightness, closeTo(1.8, 1e-9));
    });

    test('«уровень прозрачности» — обратная непрозрачность', () {
      expect(const Transparency(blockOpacity: 60).transparencyPercent, 40);
      expect(const Transparency(blockOpacity: 100).transparencyPercent, 0);
      expect(const Transparency(blockOpacity: 0).transparencyPercent, 100);
    });

    test('оверлеи не включаются без основной прозрачности', () {
      const off = Transparency(overlayGlass: true);
      expect(off.overlaysOn, isFalse);
      expect(off.copyWith(on: true).overlaysOn, isTrue);
    });
  });

  group('стор', () {
    test('умолчания: выключено, 60/50/12', () {
      final tr = _container(JsonStore.memory()).read(transparencyProvider);
      expect(tr.on, isFalse);
      expect(tr.overlayGlass, isFalse);
      expect(tr.blockOpacity, kTrOpacityDefault);
      expect(tr.glassStr, kTrBrightnessDefault);
      expect(tr.glassBlur, kTrBlurDefault);
    });

    test('ползунок уровня пишет в хранилище непрозрачность', () {
      final store = JsonStore.memory();
      _container(store).read(transparencyProvider.notifier)
        ..setOn(true)
        ..setTransparencyPercent(40);

      final tr = _container(store).read(transparencyProvider);
      expect(tr.on, isTrue);
      expect(tr.blockOpacity, 60);
      expect(tr.transparencyPercent, 40);
    });

    test('значения переживают перезапуск', () {
      final store = JsonStore.memory();
      _container(store).read(transparencyProvider.notifier)
        ..setOn(true)
        ..setOverlayGlass(true)
        ..setGlassStr(70)
        ..setGlassBlur(20);

      final tr = _container(store).read(transparencyProvider);
      expect(tr.overlayGlass, isTrue);
      expect(tr.glassStr, 70);
      expect(tr.glassBlur, 20);
    });

    test(
      'битая запись читается умолчанием, а слишком большая — подрезается',
      () {
        final store = JsonStore.memory({
          'transparency': {
            'on': 'ага',
            'blockOpacity': 'много',
            'glassStr': 500,
            'glassBlur': 999,
          },
        });
        final tr = _container(store).read(transparencyProvider);
        expect(tr.on, isFalse);
        expect(tr.blockOpacity, kTrOpacityDefault);
        expect(tr.glassStr, 100);
        expect(tr.glassBlur, kTrBlurMax);
      },
    );
  });

  group('стекло', () {
    test('выключено — стекла нет ни у блоков, ни у оверлеев', () {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier).setOverlayGlass(true);
      expect(c.read(glassProvider), isNull);
      expect(c.read(overlayGlassProvider), isNull);
    });

    test('включено — блоки стеклянные, оверлеи ждут своего тумблера', () {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier).setOn(true);
      expect(c.read(glassProvider), isNotNull);
      expect(c.read(overlayGlassProvider), isNull);
      c.read(transparencyProvider.notifier).setOverlayGlass(true);
      expect(c.read(overlayGlassProvider), isNotNull);
    });

    test('нейтральное стекло без размытия обходится без фильтра', () {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier)
        ..setOn(true)
        ..setGlassBlur(0)
        ..setGlassStr(50);
      // Ни размывать, ни осветлять нечего — лишний слой заводить незачем.
      expect(c.read(glassProvider)!.filter, isNull);
      c.read(transparencyProvider.notifier).setGlassStr(70);
      expect(c.read(glassProvider)!.filter, isNotNull);
    });
  });

  group('GlassBox', () {
    testWidgets('выключено — сплошная плашка без фильтра', (tester) async {
      final c = _container(JsonStore.memory());
      await _pumpBox(tester, c);

      expect(_fillOf(tester), BloomThemes.dark.pill);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('включено — заливка редеет и появляется фильтр', (
      tester,
    ) async {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier)
        ..setOn(true)
        ..setTransparencyPercent(40);
      await _pumpBox(tester, c);
      await tester.pump();

      expect(_fillOf(tester).a, closeTo(0.6, 0.01));
      expect(find.byType(BackdropFilter), findsOneWidget);
      // `JsonStore` откладывает запись на 400 мс — без этого тест уходит с
      // висящим таймером.
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('размытие 0 и нейтральная яркость — фильтра нет', (
      tester,
    ) async {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier)
        ..setOn(true)
        ..setGlassBlur(0);
      await _pumpBox(tester, c);
      await tester.pump();

      // Заливка всё равно полупрозрачная — стекло без размытия это плёнка.
      expect(_fillOf(tester).a, lessThan(1));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('шторки', () {
    testWidgets('стекло оверлеев доходит и до шторки, и до затемнения', (
      tester,
    ) async {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier)
        ..setOn(true)
        ..setOverlayGlass(true);
      await _pumpSheet(tester, c);

      // Два фильтра: поверхность шторки и её затемнение (`_BloomSheetRoute`).
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('без тумблера оверлеев шторка остаётся сплошной', (
      tester,
    ) async {
      final c = _container(JsonStore.memory());
      // Прозрачность блоков включена, а оверлеев — нет: шторку это не трогает.
      c.read(transparencyProvider.notifier).setOn(true);
      await _pumpSheet(tester, c);

      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
