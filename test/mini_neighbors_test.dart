/// «Соседние треки» — карусель миниплеера: настройка, геометрия и жест.
///
/// Проверяем то, что ломается тихо: полоска соседа обязана встать в обычное
/// поле экрана (иначе карточка просто худеет ни за чем), шаг карусели —
/// в точности заменять середину соседом, строка соседа — не показывать чужой
/// прогресс и не ловить нажатий, а перелистывание в карусели — не въезжать
/// с другого края поверх уже приехавшей карточки.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/player/mini_style_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/ui/mini_player.dart';
import 'package:bloom/l10n/app_localizations.dart';
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/track_flick.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Трек $id',
  artist: 'Артист $id',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

/// Очередь без звука: настоящий контроллер лезет за `audioHandlerProvider`,
/// которого в тестах нет, а строке карточки нужен только сам список.
class _FakePlayback extends PlaybackController {
  _FakePlayback(this.initial);

  final PlaybackState initial;

  @override
  PlaybackState build() => initial;
}

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('настройка', () {
    test('по умолчанию соседей нет', () {
      expect(
        _container(JsonStore.memory()).read(miniStyleProvider).neighbors,
        isFalse,
      );
    });

    test('включённые читаются с диска', () {
      final c = _container(
        JsonStore.memory({
          'miniStyle': {'neighbors': true},
        }),
      );
      expect(c.read(miniStyleProvider).neighbors, isTrue);
    });

    test('битая запись — это «выключено», а не падение', () {
      final c = _container(
        JsonStore.memory({
          'miniStyle': {'neighbors': 'yes'},
        }),
      );
      expect(c.read(miniStyleProvider).neighbors, isFalse);
    });

    test('выбор уезжает на диск и не сносит соседние настройки', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(miniStyleProvider.notifier).setRadius(MiniRadius.pill);
      c.read(miniStyleProvider.notifier).setNeighbors(true);

      final saved = store.read('miniStyle')! as Map;
      expect(saved['neighbors'], isTrue);
      expect(saved['radius'], 'pill');
    });
  });

  group('геометрия', () {
    const screen = Size(360, 800);

    Rect card({required bool neighbors}) =>
        miniCardRect(screen: screen, navInset: 58, neighbors: neighbors);

    test('без соседей карточка стоит как стояла — поля по 8', () {
      expect(card(neighbors: false).left, kFloatGap);
      expect(card(neighbors: false).width, screen.width - kFloatGap * 2);
    });

    test('полоска соседа встаёт в обычное поле экрана', () {
      final rect = card(neighbors: true);
      // Правый край левого соседа: он стоит на шаг левее карточки.
      final edge = rect.left - miniStride(rect.width) + rect.width;
      expect(edge - kFloatGap, kMiniPeek);
    });

    test('шаг карусели ставит соседа ровно на место карточки', () {
      final rect = card(neighbors: true);
      final stride = miniStride(rect.width);
      expect(rect.left - stride + stride, rect.left);
      // И между карточками остаётся тот же просвет, что по краям экрана.
      expect(stride - rect.width, kFloatGap);
    });

    test('карточка ужимается ровно на две полоски с просветами', () {
      expect(
        card(neighbors: false).width - card(neighbors: true).width,
        (kMiniPeek + kFloatGap) * 2,
      );
    });
  });

  group('строка соседа', () {
    /// Строка играющего трека тут не строится вовсе: её индикаторы и кнопка
    /// play лезут за живым плеером, которого в тестах нет. Это же и держит
    /// проверку «соседу чужой прогресс не достаётся» — включённая по умолчанию
    /// линия прогресса на соседе просто уронила бы тест.
    Future<void> pump(WidgetTester tester, {required bool neighbor}) async {
      final queue = [_track('a'), _track('b')];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jsonStoreProvider.overrideWithValue(
              JsonStore.memory({
                // Линия прогресса включена по умолчанию — на ней и проверяем,
                // что соседу чужой прогресс не достаётся.
                'miniStyle': {'neighbors': true},
              }),
            ),
            playbackProvider.overrideWith(
              () => _FakePlayback(PlaybackState(queue: queue, index: 0)),
            ),
          ],
          child: MaterialApp(
            theme: buildBloomTheme(BloomThemes.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              // Ширина карточки, а не всего экрана: у строки во всю ширину
              // теста подписи разъезжаются, и проверять было бы нечего.
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: MiniCardRow(neighbor: neighbor ? queue[1] : null),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('показывает СВОЙ трек, а не играющий', (tester) async {
      await pump(tester, neighbor: true);
      expect(find.text('Трек b'), findsOneWidget);
      expect(find.text('Трек a'), findsNothing);
    });

    testWidgets('кнопки стоят, но не нажимаются', (tester) async {
      await pump(tester, neighbor: true);
      final buttons = tester
          .widgetList<CircleIconButton>(find.byType(CircleIconButton))
          .toList();
      // Умолчание — трио перемотки: раскладка у соседа та же, иначе на въезде
      // подпись прыгала бы.
      expect(buttons, hasLength(3));
      expect(buttons.every((b) => b.onTap == null), isTrue);
    });
  });

  group('жест карусели', () {
    Future<double> flick(
      WidgetTester tester, {
      required bool carousel,
      required double dx,
    }) async {
      final shift = ValueNotifier<double>(0);
      addTearDown(shift.dispose);
      var flips = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 64,
              child: TrackFlick(
                shift: shift,
                carousel: carousel,
                onLeft: () => flips++,
                builder: (context, value) => CarouselSlide(
                  shift: value,
                  stride: 308,
                  child: Container(color: const Color(0xFF101010)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(TrackFlick), Offset(dx, 0));
      await tester.pumpAndSettle();
      expect(flips, dx.abs() > 100 ? 1 : 0);
      return shift.value;
    }

    testWidgets('перелистнули — карточка стоит на месте, без въезда', (
      tester,
    ) async {
      // Сосед уже приехал в середину: вводить его с другого края нечего, и
      // сдвиг обязан быть ровно нулём.
      expect(await flick(tester, carousel: true, dx: -200), 0);
    });

    testWidgets('не дотянули — сдвиг возвращается', (tester) async {
      expect(await flick(tester, carousel: true, dx: -20), 0);
    });

    testWidgets('чужой сдвиг живёт дольше жеста', (tester) async {
      // Карусель двигает им ещё и соседей: `TrackFlick` не имеет права его
      // освобождать — иначе слой соседей слушал бы мёртвый `ValueNotifier`.
      final shift = ValueNotifier<double>(0);
      addTearDown(shift.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TrackFlick(
            shift: shift,
            carousel: true,
            onLeft: () {},
            builder: (context, value) => const SizedBox(width: 300, height: 64),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => shift.value = 0.5, returnsNormally);
    });
  });
}
