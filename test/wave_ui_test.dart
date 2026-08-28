/// Интерфейс волны: геометрия кольца, карточка на главной и шторка дизлайков.
///
/// Кольцо проверяем числами, а не на глаз: слоты стоят по эллипсу вокруг
/// центра, и съехавший масштаб виден только тем, что обложки уезжают за край
/// блока — на скриншоте это заметишь не сразу.
library;

import 'dart:math';

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/wave/ui/wave_card.dart';
import 'package:bloom/features/wave/ui/wave_dislikes_sheet.dart';
import 'package:bloom/features/wave/ui/wave_ring.dart';
import 'package:bloom/features/wave/wave_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_icons/solar_icons.dart';

Track _track(String id, {String? cover}) => Track(
  id: id,
  name: 'Song $id',
  artist: 'Artist $id',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
  cover: cover,
);

ProviderContainer _container([JsonStore? store]) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store ?? JsonStore.memory()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildBloomTheme(BloomThemes.dark),
      home: Scaffold(body: child),
    ),
  ),
);

void main() {
  group('масштаб кольца', () {
    test('узкий экран сжимает кольцо, но не ниже дна читаемости', () {
      // Телефон: кольцо ужимается примерно вдвое от десктопного размера.
      final phone = ringScale(360);
      expect(phone, closeTo(360 / kRingDesignWidth, 0.001));
      expect(phone, greaterThan(0.46));
      // Совсем узкий блок упирается в дно: ниже обложки не читаются.
      expect(ringScale(120), 0.46);
    });

    test('широкий блок кольцо НЕ растягивает', () {
      // Дизайн-размер — потолок: на планшете кольцо просто стоит по центру.
      expect(ringScale(1200), 1.0);
      expect(ringScale(kRingDesignWidth), 1.0);
    });
  });

  group('слоты кольца', () {
    test('восемь слотов и все внутри дизайн-бокса', () {
      expect(kRingSlots.length, 8);
      for (final slot in kRingSlots) {
        // Половина стороны плитки от центра слота не должна вылезать за бокс.
        expect(
          slot.x.abs() + slot.size / 2,
          lessThanOrEqualTo(kRingDesignWidth / 2),
        );
        expect(
          slot.y.abs() + slot.size / 2,
          lessThanOrEqualTo(kRingDesignHeight / 2),
        );
      }
    });

    test('плитки стоят по окружности — просветы вокруг героя одинаковые', () {
      // Ровно этого и не хватало на десктопной геометрии: там кольцо — эллипс
      // 250×155, и боковые просветы выходили вдвое шире верхних.
      final distances = [
        for (final slot in kRingSlots) sqrt(slot.x * slot.x + slot.y * slot.y),
      ];
      for (final d in distances) {
        expect(d, closeTo(distances.first, 0.001));
      }
      // И плитки одного размера: разнобой на окружности читается неровностью.
      expect({for (final s in kRingSlots) s.size}.length, 1);
    });

    test('в центре кольца пусто — там стоит герой', () {
      for (final slot in kRingSlots) {
        final clearance =
            sqrt(slot.x * slot.x + slot.y * slot.y) - slot.size / 2;
        expect(clearance, greaterThan(100), reason: 'слот ${slot.x},${slot.y}');
      }
    });

    test('у плиток разные периоды качания — кольцо не ходит строем', () {
      final periods = {for (final s in kRingSlots) s.period};
      expect(periods.length, greaterThan(4));
    });
  });

  group('кольцо', () {
    testWidgets('обложек меньше, чем слотов — дырок нет, стоят заглушки', (
      tester,
    ) async {
      await _pump(
        tester,
        _container(),
        WaveRing(
          faces: [_track('sc_1', cover: 'https://x/1.jpg')],
          scale: 0.6,
          loading: false,
          onTap: (_) {},
        ),
      );
      // Восемь слотов на месте независимо от того, сколько обложек пришло, —
      // дырок в кольце быть не должно.
      expect(find.byType(Positioned), findsNWidgets(kRingSlots.length));
      // Нажимается ровно одна плитка: у остальных семи стоят заглушки.
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('тап по обложке отдаёт её трек', (tester) async {
      Track? tapped;
      await _pump(
        tester,
        _container(),
        WaveRing(
          faces: [_track('sc_7', cover: 'https://x/7.jpg')],
          scale: 0.6,
          loading: false,
          onTap: (t) => tapped = t,
        ),
      );
      await tester.tap(find.byType(GestureDetector).first);
      expect(tapped?.id, 'sc_7');
    });

    testWidgets('пустое кольцо тапов не ловит', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        _container(),
        WaveRing(
          faces: const [],
          scale: 0.6,
          loading: true,
          onTap: (_) => taps++,
        ),
      );
      expect(find.byType(GestureDetector), findsNothing);
      expect(taps, 0);
    });
  });

  group('карточка на главной', () {
    // `pumpAndSettle` здесь НЕЛЬЗЯ: плитки кольца качаются бесконечно, и он
    // ждёт покоя до таймаута. Крутим кадры руками.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('кольцо и заголовок — на месте', (tester) async {
      // Библиотека пуста: сидов нет, значит и в сеть карточка не пойдёт.
      await _pump(tester, _container(), const WaveCard());
      await settle(tester);

      expect(find.byType(WaveRing), findsOneWidget);
      expect(find.text('Моя волна'), findsOneWidget);
      // Отдельной кнопки «Настроить» на карточке нет — шторка открывается
      // долгим нажатием (см. тесты ниже).
      expect(find.text('Настроить'), findsNothing);
    });

    testWidgets('долгое нажатие по заголовку открывает настройку', (
      tester,
    ) async {
      await _pump(tester, _container(), const WaveCard());
      await settle(tester);

      await tester.longPress(find.text('Моя волна'));
      await settle(tester);

      expect(find.text('Дизлайки'), findsOneWidget);
      // Переключатель площадки стоит ВСЕГДА — спрятанный, он выглядел бы так,
      // будто выбора нет вовсе. Без входа в Яндекс его плитка просто гаснет.
      expect(find.text('SoundCloud'), findsOneWidget);
      expect(find.text('Яндекс.Музыка'), findsOneWidget);
    });

    testWidgets('долгое нажатие по кнопке — та же настройка, а тап её не '
        'открывает', (tester) async {
      await _pump(tester, _container(), const WaveCard());
      await settle(tester);

      // Короткое нажатие — это запуск волны, а не настройка: сидов в пустой
      // библиотеке нет, поэтому оно ничего и не откроет.
      await tester.tap(find.byIcon(SolarIconsBold.play));
      await settle(tester);
      expect(find.text('Дизлайки'), findsNothing);

      await tester.longPress(find.byIcon(SolarIconsBold.play));
      await settle(tester);
      expect(find.text('Дизлайки'), findsOneWidget);
    });
  });

  group('шторка дизлайков', () {
    testWidgets('пустой список объясняет себя словами', (tester) async {
      final container = _container();
      await _pump(
        tester,
        container,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showWaveDislikesSheet(context),
            child: const Text('открыть'),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();

      expect(find.text('Дизлайков пока нет'), findsOneWidget);
    });

    testWidgets('строка показывает трек, крестик снимает метку', (
      tester,
    ) async {
      final container = _container();
      container.read(waveStoreProvider.notifier).toggleDislike(_track('sc_1'));

      await _pump(
        tester,
        container,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showWaveDislikesSheet(context),
            child: const Text('открыть'),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();

      expect(find.text('Song sc_1'), findsOneWidget);
      expect(find.text('Artist sc_1'), findsOneWidget);

      // Крестик в строке — второй круглый значок после «очистить всё» в шапке.
      await tester.tap(find.byIcon(SolarIconsOutline.closeCircle));
      await tester.pumpAndSettle();

      expect(container.read(waveStoreProvider).isDisliked('sc_1'), isFalse);
      expect(find.text('Дизлайков пока нет'), findsOneWidget);
      // Запись файла отложенная — дожидаемся её, иначе тест уходит с висящим
      // таймером.
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
