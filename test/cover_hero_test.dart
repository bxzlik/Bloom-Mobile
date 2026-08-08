/// Перелёт обложки: карточка → шапка страницы.
///
/// Проверяем не «красиво», а два места, где легко ошибиться и незаметно жить с
/// ошибкой: летящая копия должна МЕНЯТЬ форму по дороге (иначе кружок аватарки
/// щёлкает в прямоугольник на старте) и должна считать долю пути в правильную
/// сторону на «назад» (там навигатор гонит кадры от 1 к 0).
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/shared/ui/cover_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Скругление на карточке и в шапке — намеренно крайние значения, чтобы любое
/// промежуточное было видно однозначно.
const double _card = 50;
const double _page = 0;

/// Скругление летящей копии: единственный `ClipRRect`, который не совпадает ни
/// с одним из концов.
double? _flying(WidgetTester tester) {
  for (final clip in tester.widgetList<ClipRRect>(find.byType(ClipRRect))) {
    final shape = clip.borderRadius;
    if (shape is! BorderRadius) continue;
    final r = shape.topLeft.x;
    if (r > _page && r < _card) return r;
  }
  return null;
}

Widget _end({
  required Object tag,
  required double radius,
  required Size size,
}) => CoverHero(
  tag: tag,
  shape: BorderRadius.circular(radius),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: size.width,
      height: size.height,
      child: const ColoredBox(color: Color(0xFF00FF00)),
    ),
  ),
);

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: Column(
                        children: [
                          _end(
                            tag: 'cover',
                            radius: _page,
                            size: const Size(360, 300),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Text('назад'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: _end(
                  tag: 'cover',
                  radius: _card,
                  size: const Size(100, 100),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('обложка летит и меняет форму по дороге', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      _flying(tester),
      isNotNull,
      reason: 'посреди перехода в оверлее должна быть копия своей формы',
    );

    await tester.pumpAndSettle();
    expect(_flying(tester), isNull, reason: 'копия убирается после посадки');
  });

  testWidgets('на «назад» форма идёт от шапки к карточке, а не наоборот', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(GestureDetector));
    await tester.pumpAndSettle();

    await tester.tap(find.text('назад'));
    await tester.pump();
    // Четверть пути назад: копия ещё почти прямоугольник шапки. Если долю
    // перелёта считать без поправки на направление, здесь будет кружок
    // карточки — тот самый щелчок формы на старте.
    await tester.pump(const Duration(milliseconds: 75));

    final radius = _flying(tester);
    expect(radius, isNotNull);
    expect(radius, lessThan(_card / 2));

    await tester.pumpAndSettle();
  });

  testWidgets('страница под перелётом не едет по горизонтали', (tester) async {
    const key = Key('страница');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBloomTheme(BloomThemes.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: GestureDetector(
              onTap: () => Navigator.of(context).push(
                detailPageRoute<void>(
                  (_) => const Scaffold(
                    body: SizedBox.expand(child: Placeholder(key: key)),
                  ),
                ),
              ),
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pump();
    // Общий переход приложения на этом кадре увёл бы страницу вбок на четверть
    // ширины — вместе со всем, кроме летящей обложки.
    await tester.pump(const Duration(milliseconds: 150));

    expect(tester.getTopLeft(find.byKey(key)).dx, 0);

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(key)).dx, 0);
  });
}
