/// Коллаж обложек: что попадает в него из списка треков и сколько плиток
/// получается. Раскладка одна и та же у плитки библиотеки и у шапки списка,
/// поэтому проверяется отдельно от обеих.
library;

import 'package:bloom/shared/ui/cover_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сколько картинок собрал коллаж. Сами картинки в тесте не грузятся (сети
/// нет), но виджеты `Image` в дереве стоят — по ним и считаем.
Future<int> _images(WidgetTester tester, List<String?> covers) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 120,
          height: 120,
          child: CoverCollage(
            covers: covers,
            fallback: const ColoredBox(color: Color(0xFF101010)),
          ),
        ),
      ),
    ),
  );
  return tester.widgetList(find.byType(Image)).length;
}

void main() {
  group('pickCollageCovers', () {
    test('берёт первые четыре разных, пустые пропускает', () {
      expect(pickCollageCovers(['a', null, '', 'b', 'c', 'd', 'e']), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('повторы не считаются — у альбома одна обложка на все треки', () {
      expect(pickCollageCovers(['a', 'a', 'a', 'b']), ['a', 'b']);
    });

    test('обложек нет — пусто', () {
      expect(pickCollageCovers([null, '', null]), isEmpty);
    });
  });

  group('CoverCollage', () {
    testWidgets('одна обложка — одна картинка на всю площадь', (tester) async {
      expect(await _images(tester, ['a', 'a']), 1);
    });

    testWidgets('две, три, четыре — столько же плиток', (tester) async {
      expect(await _images(tester, ['a', 'b']), 2);
      expect(await _images(tester, ['a', 'b', 'c']), 3);
      expect(await _images(tester, ['a', 'b', 'c', 'd', 'e']), 4);
    });

    testWidgets('обложек нет — остаётся заглушка', (tester) async {
      expect(await _images(tester, [null, '']), 0);
      expect(find.byType(ColoredBox), findsOneWidget);
    });
  });
}
