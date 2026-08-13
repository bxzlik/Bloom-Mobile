/// Липкая шапка: кнопки остаются наверху, название с рядом действий уезжает.
///
/// Проверяем геометрию и нажатия, а не картинку: где стоит ряд кнопок после
/// прокрутки, до какой высоты сжимается шапка и что погасший ряд действий уже
/// не ловит тапы — он оказывается ровно под кнопками.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/shared/ui/sticky_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/core/l10n/l10n.dart';

/// Системная строка — её высоту шапка обязана оставить под кнопками.
const double _top = 40;

/// Сжатая шапка: системная строка + отступ + ряд кнопок + отступ.
const double _collapsed = _top + 10 + 48 + 10;

/// Нажали ли «Воспроизвести» в ряду действий.
bool _played = false;

Future<void> _pumpList(WidgetTester tester) async {
  _played = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildBloomTheme(BloomThemes.dark),
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: _top)),
        child: CustomScrollView(
          slivers: [
            StickyHero(
              height: 400,
              background: const ColoredBox(color: Colors.blue),
              barHeight: 48,
              bar: const SizedBox(height: 48, child: Text('назад')),
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Название списка'),
                  GestureDetector(
                    onTap: () => _played = true,
                    child: const SizedBox(height: 46, child: Text('играть')),
                  ),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: 40,
              itemBuilder: (context, i) =>
                  SizedBox(height: 60, child: Text('строка $i')),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Видимая высота шапки — её внешняя обрезка скруглённого низа.
double _headerHeight(WidgetTester tester) => tester
    .getSize(
      find
          .descendant(
            of: find.byType(StickyHero),
            matching: find.byType(ClipRRect),
          )
          .first,
    )
    .height;

Future<void> _scroll(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
  await tester.pump();
}

void main() {
  testWidgets('шапка сжимается, но ряд кнопок остаётся наверху', (
    tester,
  ) async {
    await _pumpList(tester);
    final bar = find.text('назад');
    expect(tester.getTopLeft(bar).dy, _top + 10);
    expect(_headerHeight(tester), 400);

    final titleBefore = tester.getTopLeft(find.text('Название списка')).dy;
    await _scroll(tester, -150);

    // Кнопки на месте, название уехало вместе с обложкой ровно на прокрутку.
    expect(tester.getTopLeft(bar).dy, _top + 10);
    expect(_headerHeight(tester), 250);
    expect(
      tester.getTopLeft(find.text('Название списка')).dy,
      titleBefore - 150,
    );
  });

  testWidgets('дальше сжатой шапки прокрутка её не трогает', (tester) async {
    await _pumpList(tester);
    await _scroll(tester, -2000);

    expect(_headerHeight(tester), _collapsed);
    expect(tester.getTopLeft(find.text('назад')).dy, _top + 10);
    // Список ушёл под шапку: первая строка уже не первая на экране.
    expect(find.text('строка 0'), findsNothing);
  });

  testWidgets('погасший ряд действий не ловит тапы под кнопками', (
    tester,
  ) async {
    await _pumpList(tester);
    await tester.tap(find.text('играть'));
    expect(_played, isTrue, reason: 'в раскрытой шапке кнопка работает');

    _played = false;
    await _scroll(tester, -2000);
    await tester.tap(find.text('играть'), warnIfMissed: false);
    expect(_played, isFalse);
  });
}
