/// Фон полноэкранного плеера: персист настройки, цвет из обложки и градиент.
///
/// Проверяем то, что ломается тихо: незнакомая запись в `bloom.json` не должна
/// ронять плеер; цвет, посчитанный от обложки, обязан остаться в тёмном
/// коридоре (поверх него стоят белые подписи), а градиент — не доходить до
/// цвета темы, иначе нижняя треть экрана выглядит как выключенный фон.
library;

import 'dart:ui' as ui;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/player/player_bg_store.dart';
import 'package:bloom/features/player/ui/player_backdrop.dart';
import 'package:bloom/features/settings/cover_accent.dart';
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Готовый кадр без декодера: `createTestImage` в `testWidgets` не доезжает —
/// декодирование настоящее, а часы там поддельные, и `await` виснет навсегда
/// (наступил). `toImageSync` отдаёт картинку тут же.
ui.Image _solidImage(int side) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = const Color(0xFFB01020),
  );
  return recorder.endRecording().toImageSync(side, side);
}

/// Готовая картинка вместо сетевой: в тестах сеть молчит, а проверять надо
/// раскладку уже загруженного кадра.
class _FakeImage extends ImageProvider<_FakeImage> {
  _FakeImage(this.image);

  final ui.Image image;

  @override
  Future<_FakeImage> obtainKey(ImageConfiguration configuration) async => this;

  @override
  ImageStreamCompleter loadImage(_FakeImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        Future<ImageInfo>.value(ImageInfo(image: image.clone())),
      );
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
    test('по умолчанию фона нет', () {
      final c = _container(JsonStore.memory());
      expect(c.read(playerBgProvider), PlayerBg.none);
      expect(c.read(playerBgProvider).isNone, isTrue);
    });

    test('выбранный режим читается с диска', () {
      final c = _container(JsonStore.memory({'playerBg': 'cover'}));
      expect(c.read(playerBgProvider), PlayerBg.cover);
    });

    test('незнакомая запись — это «Нет»', () {
      final c = _container(JsonStore.memory({'playerBg': 'wallpaper'}));
      expect(c.read(playerBgProvider), PlayerBg.none);
    });

    test('выбор уезжает на диск', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(playerBgProvider.notifier).set(PlayerBg.color);
      expect(c.read(playerBgProvider), PlayerBg.color);
      expect(store.read('playerBg'), 'color');

      c.read(playerBgProvider.notifier).set(PlayerBg.none);
      expect(store.read('playerBg'), 'none');
    });
  });

  group('цвет из обложки', () {
    test('почти чёрная обложка всё равно даёт видимый цвет', () {
      final hsl = HSLColor.fromColor(
        playerBgFromHsl(const CoverHsl(0, 0.9, 0)),
      );
      expect(hsl.lightness, closeTo(0.16, 0.01));
    });

    test('светлая обложка притемняется', () {
      final hsl = HSLColor.fromColor(
        playerBgFromHsl(const CoverHsl(210, 0.9, 0.95)),
      );
      expect(hsl.lightness, lessThanOrEqualTo(0.35));
    });

    test('кислотная насыщенность подрезана', () {
      final hsl = HSLColor.fromColor(
        playerBgFromHsl(const CoverHsl(120, 1, 0.4)),
      );
      expect(hsl.saturation, closeTo(0.72, 0.02));
    });

    test('серая обложка остаётся серой', () {
      final hsl = HSLColor.fromColor(
        playerBgFromHsl(const CoverHsl(0, 0, 0.5)),
      );
      expect(hsl.saturation, 0);
    });

    test('заметно живее тона миниплеера: та же обложка — светлее и сочнее', () {
      const cover = CoverHsl(350, 0.8, 0.45);
      final player = HSLColor.fromColor(playerBgFromHsl(cover));
      final mini = HSLColor.fromColor(miniBgFromHsl(cover));
      expect(player.lightness, greaterThan(mini.lightness));
      expect(player.saturation, greaterThan(mini.saturation));
    });
  });

  group('градиент', () {
    const bg = Color(0xFF0A0A0A);
    const color = Color(0xFF7A1220);

    test('сверху — сам цвет обложки', () {
      expect(playerBgGradient(color, bg).first, color);
    });

    test('снизу темнее, но не цвет темы', () {
      final colors = playerBgGradient(color, bg);
      expect(colors.last, isNot(bg));
      // Нижняя точка ближе к теме, чем середина, — иначе градиента не видно.
      double distance(Color a, Color b) =>
          ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs());
      expect(distance(colors.last, bg), lessThan(distance(colors[1], bg)));
    });

    test('границы цветов совпадают по числу с самими цветами', () {
      // `LinearGradient` требует ровно столько же стопов — иначе ассерт на
      // отрисовке, а не в тесте.
      expect(playerBgGradient(color, bg).length, kPlayerBgStops.length);
      expect(kPlayerBgDim.length, 3);
    });
  });

  testWidgets('размытая обложка занимает ВЕСЬ отведённый прямоугольник', (
    tester,
  ) async {
    final image = _solidImage(8);
    addTearDown(image.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 600,
            // Тот же `Stack` со свободными ограничениями, в который кладёт детей
            // `AnimatedSwitcher`: на нём первая версия и провалилась — картинка
            // вставала своим размером посреди экрана вместо фона во всю его
            // площадь.
            child: Stack(children: [BlurredCover(image: _FakeImage(image))]),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(Image)), const Size(300, 600));
  });

  group('шапка на фоне', () {
    Future<GlassBox> pumpButton(WidgetTester tester, {bool? glass}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [jsonStoreProvider.overrideWithValue(JsonStore.memory())],
          child: MaterialApp(
            theme: buildBloomTheme(BloomThemes.dark),
            home: Scaffold(
              body: GlassGroup(
                child: CircleIconButton(
                  icon: Icons.close,
                  background: const Color(0x11FFFFFF),
                  glass: glass,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.widget<GlassBox>(find.byType(GlassBox));
    }

    testWidgets('плёнка поверхности стекло НЕ гасит', (tester) async {
      // Шапка плеера на фоне красится плёнкой блоков, и это поверхность темы:
      // при включённой «Прозрачности» стекло ей положено.
      expect((await pumpButton(tester, glass: true)).enabled, isTrue);
    });

    testWidgets('своя заливка без просьбы стекло гасит', (tester) async {
      // Умолчание не поехало: акцент под play и прозрачный кружок миниплеера —
      // это состояние, стеклом они не становятся.
      expect((await pumpButton(tester)).enabled, isFalse);
    });
  });

  testWidgets('в режиме «Нет» слоя нет вовсе', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [jsonStoreProvider.overrideWithValue(JsonStore.memory())],
        child: MaterialApp(
          theme: buildBloomTheme(BloomThemes.dark),
          home: const Scaffold(body: PlayerBackdrop()),
        ),
      ),
    );
    // Ни картинки, ни градиента: фон выключен, и рисовать поверх заливки темы
    // нечего.
    expect(find.byType(DecoratedBox), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
}
