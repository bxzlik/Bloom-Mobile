/// Онбординг первого запуска: гейт, порядок шагов и то, что мастер реально
/// записывает.
///
/// Проверяем то, что ломается тихо. Флаг [onboardingPending] читает `redirect`
/// роутера, и если он разойдётся с провайдером — приложение либо покажет мастер
/// поверх настроенного плеера, либо не покажет его вовсе. Профиль коммитится
/// ОДНИМ куском на финише (чтобы «Назад» не оставлял следов), а язык и тема,
/// наоборот, применяются сразу — эти два правила и держим тестами.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/onboarding/onboarding_store.dart';
import 'package:bloom/features/onboarding/ui/onboarding_screen.dart';
import 'package:bloom/features/profile/profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

ProviderContainer _container([JsonStore? store]) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store ?? JsonStore.memory()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Мастер на своём маршруте — как в настоящем роутере: `context.go('/home')` на
/// финише должно куда-то приводить, а `PopScope` без маршрута-предка молчит.
Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Center(child: Text('ГЛАВНАЯ'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        routerConfig: router,
      ),
    ),
  );
  await _settle(tester);
}

/// Пережить смену слайда. `pumpAndSettle` тут не годится: на «Привет» кольца
/// вокруг знака пульсируют вечно, и он ждал бы конца анимации до таймаута.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await _settle(tester);
}

void main() {
  group('гейт', () {
    test('чистое хранилище — онбординг не пройден', () {
      final c = _container();
      expect(c.read(onboardedProvider), isFalse);
      expect(onboardingPending, isTrue);
    });

    test('пройденный не показывается снова', () {
      final store = JsonStore.memory({'onboarded': true});
      final c = _container(store);
      expect(c.read(onboardedProvider), isTrue);
      expect(onboardingPending, isFalse);
    });

    test('finish пишет флаг, reset его снимает', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(onboardedProvider);

      c.read(onboardedProvider.notifier).finish();
      expect(store.read('onboarded'), isTrue);
      expect(onboardingPending, isFalse);

      // Повтор мастера (отладочная строка настроек) обязан снять и флаг, и
      // запись: иначе `redirect` уведёт обратно на главную.
      c.read(onboardedProvider.notifier).reset();
      expect(store.read('onboarded'), isNull);
      expect(onboardingPending, isTrue);
    });
  });

  group('живой фон', () {
    // Эффект по краям обязан быть виден в КАЖДОЙ теме: он пожаловался, что в
    // части тем его нет. Виден он ровно тогда, когда светлота пятна заметно
    // отличается от светлоты фона.
    for (final preset in kThemePresets) {
      test('пятно отличимо от фона: ${preset.name}', () {
        final tokens = preset.tokens();
        final blob = blobColor(tokens.accent, tokens.bg, tokens.isLight);
        final diff =
            (HSLColor.fromColor(blob).lightness -
                    HSLColor.fromColor(tokens.bg).lightness)
                .abs();
        expect(
          diff,
          greaterThanOrEqualTo(0.29),
          reason: 'в теме ${preset.name} пятно сливается с фоном',
        );
        // На светлой теме пятно — тень, на тёмных — свет.
        expect(
          HSLColor.fromColor(blob).lightness <
              HSLColor.fromColor(tokens.bg).lightness,
          tokens.isLight,
        );
      });
    }

    test('ахроматичный акцент не подкрашивается', () {
      // Белый акцент тёмных тем обязан остаться белым: тона, которого в теме
      // нет, в фоне быть не должно.
      final blob = blobColor(
        const Color(0xFFFFFFFF),
        const Color(0xFF0A0A0A),
        false,
      );
      expect(HSLColor.fromColor(blob).saturation, lessThan(0.05));
    });
  });

  group('мастер', () {
    testWidgets('приветствие и язык — один шаг; выбор применяется на месте', (
      tester,
    ) async {
      final c = _container();
      await _pump(tester, c);

      // Вордмарк и карточки языка стоят на одном экране.
      expect(find.text('Bloom'), findsOneWidget);
      expect(find.text('Русский'), findsOneWidget);
      expect(c.read(settingsProvider).locale, isNull);

      await _tapText(tester, 'Русский');

      expect(c.read(settingsProvider).locale, const Locale('ru'));
      // Тап по языку НЕ уводит со слайда — дальше ведёт только «Поехали».
      expect(find.text('Bloom'), findsOneWidget);

      await _tapText(tester, 'Поехали');
      expect(find.text('Расскажи о себе'), findsOneWidget);
    });

    testWidgets('стрелка в шапке возвращает на предыдущий шаг', (tester) async {
      final c = _container();
      await _pump(tester, c);
      await _tapText(tester, 'Поехали');

      expect(find.text('Расскажи о себе'), findsOneWidget);

      await tester.tap(find.byIcon(SolarIconsOutline.altArrowLeft));
      await _settle(tester);
      expect(find.text('Bloom'), findsOneWidget);
    });

    testWidgets('свайп листает шаги в обе стороны', (tester) async {
      final c = _container();
      await _pump(tester, c);
      expect(find.text('Bloom'), findsOneWidget);

      // Влево — дальше.
      await tester.fling(find.text('Bloom'), const Offset(-200, 0), 800);
      await _settle(tester);
      expect(find.text('Расскажи о себе'), findsOneWidget);

      // Вправо — назад.
      await tester.fling(
        find.text('Расскажи о себе'),
        const Offset(200, 0),
        800,
      );
      await _settle(tester);
      expect(find.text('Bloom'), findsOneWidget);
    });

    testWidgets('тема применяется на тап, не дожидаясь финиша', (tester) async {
      final c = _container();
      await _pump(tester, c);
      await _tapText(tester, 'Поехали');
      await _tapText(tester, 'Далее'); // профиль → тема

      expect(find.text('Выбери оформление'), findsOneWidget);
      await _tapText(tester, 'AMOLED');
      expect(c.read(settingsProvider).themeId, 'amoled');
    });

    testWidgets('на шаге «Музыка» три площадки, YouTube Music уже настроен', (
      tester,
    ) async {
      final c = _container();
      await _pump(tester, c);
      await _tapText(tester, 'Поехали');
      await _tapText(tester, 'Далее'); // профиль → тема
      await _tapText(tester, 'Далее'); // тема → музыка

      expect(find.text('Подключи музыку'), findsOneWidget);
      expect(find.text('SoundCloud'), findsOneWidget);
      expect(find.text('Яндекс.Музыка'), findsOneWidget);
      expect(find.text('YouTube Music'), findsOneWidget);
      // Авторизации YTM не требует — вместо «Не подключено» стоит свой статус,
      // а две оставшиеся площадки на чистом хранилище не подключены.
      expect(find.text('Настроен'), findsOneWidget);
      expect(find.text('Не подключено'), findsNWidgets(2));
    });

    testWidgets('ник уходит в профиль только на финише, и мастер закрывается', (
      tester,
    ) async {
      final store = JsonStore.memory();
      final c = _container(store);
      await _pump(tester, c);
      await _tapText(tester, 'Поехали');

      await tester.enterText(find.byType(TextField), 'Онига');
      await _settle(tester);
      // Пока мастер идёт, профиль не тронут — «Назад» не должен оставлять следов.
      expect(c.read(profileProvider).name, '');

      await _tapText(tester, 'Далее'); // профиль → тема
      await _tapText(tester, 'Далее'); // тема → музыка
      expect(c.read(profileProvider).name, '');

      await _tapText(tester, 'Готово');
      expect(c.read(profileProvider).name, 'Онига');
      expect(find.text('Привет, Онига!'), findsOneWidget);
      // Флаг ставится не сразу: «Финал» ещё висит на экране.
      expect(c.read(onboardedProvider), isFalse);

      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(c.read(onboardedProvider), isTrue);
      expect(store.read('onboarded'), isTrue);
      expect(find.text('ГЛАВНАЯ'), findsOneWidget);
    });
  });
}
