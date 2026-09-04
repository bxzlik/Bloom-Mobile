/// Авто-тема: цвета всего интерфейса едут за обложкой играющего трека.
///
/// Проверяем формулу поверхности (она должна остаться тёмной и не кислотной —
/// поверх неё стоит весь текст) и правила переключения: авто-тема и
/// авто-акцент не могут быть включены разом, а снятый с обложки цвет не имеет
/// права пережить уход на обычный пресет.
library;

import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/settings/cover_accent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container([JsonStore? store]) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store ?? JsonStore.memory()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('поверхность из обложки', () {
    test('светлота десктопная — 0.075, обложка сюда входит оттенком', () {
      final hsl = HSLColor.fromColor(
        autoThemeSurfaceFromHsl(const CoverHsl(210, 0.9, 0.7)),
      );
      expect(hsl.lightness, closeTo(0.075, 0.005));
      // Допуск на тон широкий не просто так: на такой темноте весь цвет живёт
      // в паре младших ступеней канала, и обратный перевод в HSL их округляет.
      expect(hsl.hue, closeTo(210, 3));
    });

    test(
      'насыщенность подрезана: цветного пятна вместо интерфейса не выйдет',
      () {
        final hsl = HSLColor.fromColor(
          autoThemeSurfaceFromHsl(const CoverHsl(120, 1, 0.5)),
        );
        expect(hsl.saturation, lessThanOrEqualTo(0.5));
      },
    );

    test('серая обложка остаётся серой', () {
      final hsl = HSLColor.fromColor(
        autoThemeSurfaceFromHsl(const CoverHsl(0, 0, 0.5)),
      );
      expect(hsl.saturation, 0);
    });

    test('темнее миниплеерного тона той же обложки', () {
      // Поверхность — фон всего приложения, а не полоса среди хрома: она обязана
      // быть самой тихой из посчитанных от обложки заливок.
      const cover = CoverHsl(350, 0.8, 0.45);
      expect(
        HSLColor.fromColor(autoThemeSurfaceFromHsl(cover)).lightness,
        lessThan(HSLColor.fromColor(miniBgFromHsl(cover)).lightness),
      );
    });
  });

  group('переключение', () {
    test('включение затравливает тему текущими цветами', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme('midnight');
      final before = c.read(settingsProvider).tokens;

      settings.setTheme(kAutoThemeId);
      final state = c.read(settingsProvider);
      expect(state.autoTheme, isTrue);
      // Своих цветов у авто-темы до первой обложки нет — перекрашивать не из
      // чего, и экран не должен мигнуть в чужую тему.
      expect(state.tokens.bg, before.bg);
      expect(state.tokens.accent, before.accent);
    });

    test('авто-акцент гаснет: два режима за один акцент не спорят', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setAutoAccent(true);
      settings.setTheme(kAutoThemeId);
      expect(c.read(settingsProvider).autoAccent, isFalse);
    });

    test('включённый авто-акцент уводит с авто-темы', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme(kAutoThemeId);
      settings.applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));

      settings.setAutoAccent(true);
      final state = c.read(settingsProvider);
      expect(state.autoTheme, isFalse);
      expect(state.themeId, kThemePresets.first.id);
      // Снятый с обложки акцент ушёл вместе с режимом: пресету он чужой.
      expect(state.tokens.accent, kThemePresets.first.accent);
    });

    test('обложка красит фон, блоки и акцент разом', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme(kAutoThemeId);
      settings.applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));

      final tokens = c.read(settingsProvider).tokens;
      expect(tokens.bg, const Color(0xFF141018));
      expect(tokens.blockColor, const Color(0xFF141018));
      expect(tokens.accent, const Color(0xFF9B5DE5));
    });

    test('опоздавший скан на другую тему не действует', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme(kAutoThemeId);
      settings.setTheme('warm');

      settings.applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));
      final state = c.read(settingsProvider);
      expect(state.tokens.bg, const Color(0xFF1C1610));
      expect(state.tokens.accent, const Color(0xFFD4875A));
    });

    test('уход на пресет сбрасывает акцент обложки', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme(kAutoThemeId);
      settings.applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));

      settings.setTheme('nord');
      expect(c.read(settingsProvider).tokens.accent, const Color(0xFF88C0D0));
    });
  });

  group('хранилище', () {
    test('режим и снятый цвет переживают перезапуск', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(settingsProvider.notifier).setTheme(kAutoThemeId);
      c
          .read(settingsProvider.notifier)
          .applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));

      final restored = _container(store).read(settingsProvider);
      expect(restored.autoTheme, isTrue);
      expect(restored.tokens.bg, const Color(0xFF141018));
      expect(restored.tokens.accent, const Color(0xFF9B5DE5));
    });
  });
}
