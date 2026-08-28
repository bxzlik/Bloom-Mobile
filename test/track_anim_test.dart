/// Анимация смены трека: направление перехода, настройка и сами слои.
///
/// Проверяем то, на чём анимация ломается незаметно: что обе поверхности едут
/// в одну сторону (направление считается один раз, в плеере), что смену «под
/// пальцем» слои не рисуют поверх жеста и что уехавший слой снимается.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/player/track_anim_store.dart';
import 'package:bloom/features/player/track_swap_dir.dart';
import 'package:bloom/features/player/ui/track_swap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderClipRect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

/// Слои узнаём по тексту: у каждого трека свой.
Future<void> _pumpSwap(WidgetTester tester, String id, TrackAnimKind kind) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: TrackSwap(id: id, kind: kind, child: Text(id)),
            ),
          ),
        ),
      ),
    );

/// Сдвиг слоя с этим текстом, доля ширины.
double _shiftOf(WidgetTester tester, String text) {
  final translation = tester.widget<FractionalTranslation>(
    find
        .ancestor(
          of: find.text(text),
          matching: find.byType(FractionalTranslation),
        )
        .first,
  );
  return translation.translation.dx;
}

void main() {
  setUp(resetSwapDirForTest);

  group('направление перехода', () {
    test('дальше по очереди — вперёд, назад — назад', () {
      final queue = ['a', 'b', 'c'];
      commitSwapDir(queue, 0);
      commitSwapDir(queue, 1);
      expect(swapDir, 1);
      commitSwapDir(queue, 0);
      expect(swapDir, -1);
    });

    test('явное направление сильнее номеров: закольцовка', () {
      final queue = ['a', 'b', 'c'];
      commitSwapDir(queue, 2);
      // «Дальше» с последнего на первый — по номерам это «назад».
      markSwapDir(1);
      commitSwapDir(queue, 0);
      expect(swapDir, 1);
    });

    test('явное направление одноразовое', () {
      final queue = ['a', 'b', 'c'];
      commitSwapDir(queue, 2);
      markSwapDir(-1);
      commitSwapDir(queue, 1);
      expect(swapDir, -1);
      // Следующее переключение считается уже по номерам.
      commitSwapDir(queue, 2);
      expect(swapDir, 1);
    });

    test('другая очередь — всегда вперёд: номера несравнимы', () {
      commitSwapDir(['a', 'b', 'c'], 2);
      commitSwapDir(['x', 'y'], 0);
      expect(swapDir, 1);
    });

    test('«не анимировать» держится ровно до ближайшей смены', () {
      final queue = ['a', 'b'];
      commitSwapDir(queue, 0);
      markSwapSilent();
      commitSwapDir(queue, 1);
      expect(swapSilent, isTrue);
      commitSwapDir(queue, 0);
      expect(swapSilent, isFalse);
    });

    test('несостоявшийся жест флаг за собой убирает', () {
      final queue = ['a', 'b'];
      commitSwapDir(queue, 0);
      // «Назад» в середине трека отматывает его в начало, а не листает.
      markSwapSilent();
      cancelSwapSilent();
      commitSwapDir(queue, 1);
      expect(swapSilent, isFalse);
    });
  });

  group('настройка', () {
    test('по умолчанию — слайд у всего, как на ПК', () {
      final settings = _container(JsonStore.memory()).read(trackAnimProvider);
      for (final surface in TrackAnimSurface.values) {
        expect(settings.of(surface).cover, TrackAnimKind.slide);
        expect(settings.of(surface).text, TrackAnimKind.slide);
      }
    });

    test('поверхности и цели независимы и переживают перезапуск', () {
      final store = JsonStore.memory();
      _container(store)
          .read(trackAnimProvider.notifier)
          .setKind(
            TrackAnimSurface.mini,
            TrackAnimTarget.text,
            TrackAnimKind.fade,
          );

      final again = _container(store).read(trackAnimProvider);
      expect(again.of(TrackAnimSurface.mini).text, TrackAnimKind.fade);
      // Соседи не поехали.
      expect(again.of(TrackAnimSurface.mini).cover, TrackAnimKind.slide);
      expect(again.of(TrackAnimSurface.player).text, TrackAnimKind.slide);
    });

    test('незнакомая запись заменяется умолчанием, а не роняет запуск', () {
      final store = JsonStore.memory({
        'trackAnim': {
          'mini': {'cover': 'вертушка', 'text': 'none'},
          'player': 'мусор',
        },
      });
      final settings = _container(store).read(trackAnimProvider);
      expect(settings.of(TrackAnimSurface.mini).cover, TrackAnimKind.slide);
      expect(settings.of(TrackAnimSurface.mini).text, TrackAnimKind.none);
      expect(settings.of(TrackAnimSurface.player).cover, TrackAnimKind.slide);
    });
  });

  group('слои', () {
    testWidgets('первый трек за сессию не анимируется — уезжать нечему', (
      tester,
    ) async {
      await _pumpSwap(tester, 'первый', TrackAnimKind.slide);
      expect(find.text('первый'), findsOneWidget);
      expect(_shiftOf(tester, 'первый'), 0);
    });

    testWidgets('слайд: старый уезжает, новый приезжает и слой снимается', (
      tester,
    ) async {
      await _pumpSwap(tester, 'первый', TrackAnimKind.slide);
      await _pumpSwap(tester, 'второй', TrackAnimKind.slide);
      await tester.pump();

      // Оба слоя в дереве, и разъезжаются они в одну сторону: новый идёт
      // справа к нулю, старый уходит влево.
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('первый'), findsOneWidget);
      expect(_shiftOf(tester, 'второй'), greaterThan(0));
      expect(_shiftOf(tester, 'первый'), lessThan(0));

      await tester.pumpAndSettle();
      expect(find.text('первый'), findsNothing);
      expect(_shiftOf(tester, 'второй'), 0);
    });

    testWidgets('назад — зеркально', (tester) async {
      await _pumpSwap(tester, 'первый', TrackAnimKind.slide);
      markSwapDir(-1);
      commitSwapDir(['первый', 'второй'], 0);
      await _pumpSwap(tester, 'второй', TrackAnimKind.slide);
      await tester.pump(const Duration(milliseconds: 60));

      expect(_shiftOf(tester, 'второй'), lessThan(0));
      expect(_shiftOf(tester, 'первый'), greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('уезжающий слой режется по своей коробке', (tester) async {
      await _pumpSwap(tester, 'первый', TrackAnimKind.slide);
      await _pumpSwap(tester, 'второй', TrackAnimKind.slide);
      await tester.pump(const Duration(milliseconds: 60));

      // Слои разъехались — и обрезка обязана быть на месте: `Stack` считает
      // переполнением только позиционированных детей, а сдвиг случается на
      // покраске. Без неё подпись миниплеера наезжает на обложку.
      expect(_shiftOf(tester, 'первый'), isNot(0));
      final clip = tester.renderObject<RenderClipRect>(
        find
            .descendant(
              of: find.byType(TrackSwap),
              matching: find.byType(ClipRect),
            )
            .first,
      );
      expect(clip.clipBehavior, isNot(Clip.none));
      await tester.pumpAndSettle();
    });

    testWidgets('затухание не двигает слои', (tester) async {
      await _pumpSwap(tester, 'первый', TrackAnimKind.fade);
      await _pumpSwap(tester, 'второй', TrackAnimKind.fade);
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('первый'), findsOneWidget);
      expect(_shiftOf(tester, 'первый'), 0);
      expect(_shiftOf(tester, 'второй'), 0);
      await tester.pumpAndSettle();
    });

    testWidgets('«нет» — подмена без второго слоя', (tester) async {
      await _pumpSwap(tester, 'первый', TrackAnimKind.none);
      await _pumpSwap(tester, 'второй', TrackAnimKind.none);
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('первый'), findsNothing);
      expect(find.text('второй'), findsOneWidget);
    });

    testWidgets('смену под пальцем слои не рисуют', (tester) async {
      await _pumpSwap(tester, 'первый', TrackAnimKind.slide);
      markSwapSilent();
      commitSwapDir(['первый', 'второй'], 1);
      await _pumpSwap(tester, 'второй', TrackAnimKind.slide);
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('первый'), findsNothing);
      expect(_shiftOf(tester, 'второй'), 0);
    });
  });
}
