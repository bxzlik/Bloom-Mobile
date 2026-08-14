/// Бегущая строка названия: когда катится, куда и как быстро.
///
/// Проверяем поведение, а не картинку: влезающий текст остаётся одной статичной
/// строкой с эллипсисом, длинный раздваивается и едет влево ровно на «текст +
/// зазор», а длительность цикла считается по скорости с полом в 4 s. Ширину
/// строки берём с самого виджета (шрифт в тестах свой, считать её по кеглю
/// нельзя) — сверяем именно зависимости между числами.
library;

import 'package:bloom/shared/ui/marquee_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 20);

/// Зазор между копиями — совпадает с умолчанием виджета (десктопные 64 px).
const double _gap = 64;

Future<void> _pump(WidgetTester tester, String text, double width) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: MarqueeText(text, style: _style),
          ),
        ),
      ),
    ),
  );
}

/// Смещения обеих копий строки от левого края обёртки.
List<double> _offsets(WidgetTester tester) {
  final wrap = tester.renderObject<RenderBox>(find.byType(ClipRect));
  return tester
      .renderObjectList<RenderBox>(find.byType(Text))
      .map((box) => box.localToGlobal(Offset.zero, ancestor: wrap).dx)
      .toList();
}

void main() {
  testWidgets('короткое название не раздваивается и не катится', (
    tester,
  ) async {
    await _pump(tester, 'Трек', 400);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Трек'), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);
    // Пустых кадров анимация не заказывает — таймер не заведён вовсе.
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('длинное название едет влево на «текст + зазор»', (tester) async {
    const text = 'ААААААААААААААААААААААААААААААААААААААААА';
    await _pump(tester, text, 200);
    await tester.pump();

    // Две копии одной строки — вторая закрывает хвост цикла и стоит ровно в
    // шаге правее первой, поэтому в конце цикла встаёт на её место и
    // «перемотки» на глаз нет.
    expect(find.text(text), findsNWidgets(2));
    final start = _offsets(tester);
    expect(start.first, 0);
    final step = start[1] - start.first;

    // Скорость 55 px/s, дальше округление до целых секунд — как на ПК.
    final seconds = (step / 55).round();
    expect(seconds, greaterThan(4));

    // Допуск — пара процентов шага: цикл стартует кадром позже первой
    // раскладки, и на длинной строке этот кадр стоит несколько пикселей.
    await tester.pump(Duration(seconds: seconds ~/ 2));
    expect(_offsets(tester).first, closeTo(-step / 2, step * 0.02));

    // Иначе тест уйдёт с бесконечной анимацией на руках.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('чуть переросшее название крутится не быстрее 4 s', (
    tester,
  ) async {
    const text = 'ААААА';
    await _pump(tester, text, 60);
    await tester.pump();

    final start = _offsets(tester);
    final step = start[1] - start.first;
    // Строка переросла обёртку, но по 55 px/s прошла бы шаг быстрее 4 s —
    // значит цикл упёрся в пол и едет медленнее расчётного.
    expect(step - _gap, greaterThan(60 + 4));
    expect((step / 55).round(), lessThan(4));

    // Половина шага за 2 s — это ровно четырёхсекундный цикл. Если бы пол не
    // сработал, за те же 2 s строка ушла бы заметно дальше.
    await tester.pump(const Duration(seconds: 2));
    expect(_offsets(tester).first, closeTo(-step / 2, step * 0.02));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
