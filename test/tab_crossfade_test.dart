/// Переключение вкладок каркаса: растворение вместо смены одним кадром.
///
/// Проверяем не картинку, а три вещи, ради которых контейнер веток написан
/// свой: на покое видна ровно одна ветка, во время перехода — обе (одна
/// гаснет, вторая проявляется), и неактивная ветка не ловит тапы.
library;

import 'package:bloom/app/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Прозрачность ветки: `null` — ветка убрана со сцены (`Offstage`).
double? _opacity(WidgetTester tester, String label) {
  final branch = find.ancestor(
    of: find.text(label, skipOffstage: false),
    matching: find.byType(Offstage),
  );
  if (tester.widget<Offstage>(branch.first).offstage) return null;
  return tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.text(label, skipOffstage: false),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;
}

/// Каркас с двумя ветками и кнопкой-переключателем вместо таб-бара.
Future<void> _pump(WidgetTester tester) async {
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            Expanded(
              child: BranchCrossfade(
                index: index,
                children: const [Text('Главная'), Text('Библиотека')],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => index = 1 - index),
              child: const Text('таб'),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('на покое видна одна вкладка, вторая убрана со сцены', (
    tester,
  ) async {
    await _pump(tester);

    expect(_opacity(tester, 'Главная'), 1);
    expect(_opacity(tester, 'Библиотека'), isNull);
  });

  testWidgets('во время перехода видны обе: одна гаснет, вторая проявляется', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('таб'));
    await tester.pump();
    // Восьмая часть перехода: уходящая ещё не догорела (гаснет за первую
    // четверть), приходящая ещё не проявилась (её интервал — 3/4).
    await tester.pump(kTabTransition ~/ 8);

    final leaving = _opacity(tester, 'Главная');
    final entering = _opacity(tester, 'Библиотека');
    expect(leaving, isNotNull);
    expect(leaving, greaterThan(0));
    expect(leaving, lessThan(1));
    expect(entering, isNotNull);
    expect(entering, greaterThan(0));
    expect(entering, lessThan(1));

    await tester.pumpAndSettle();
    expect(_opacity(tester, 'Главная'), isNull);
    expect(_opacity(tester, 'Библиотека'), 1);
  });

  testWidgets('уходящая вкладка не ловит тапы уже с первого кадра', (
    tester,
  ) async {
    var tapped = false;
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              Expanded(
                child: BranchCrossfade(
                  index: index,
                  children: [
                    GestureDetector(
                      onTap: () => tapped = true,
                      child: const SizedBox.expand(child: Text('Главная')),
                    ),
                    const Text('Библиотека'),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => index = 1),
                child: const Text('таб'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('таб'));
    await tester.pump();
    await tester.tap(find.text('Главная'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tapped, isFalse);
  });
}
