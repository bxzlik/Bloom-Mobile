/// Жесты строки трека: обложка — тянучка, остальная строка — меню.
///
/// Проверяем именно разведение двух долгих жестов: если оба висят на всей
/// строке, они спорят в арене и зажатие обложки через раз открывает меню
/// вместо перетаскивания.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/entity_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = Track(
  id: 'sc_1',
  name: 'sleep mode',
  artist: 'ONDA ANDAR',
  duration: Duration(minutes: 2, seconds: 53),
  source: MusicSource.soundcloud,
);

/// Что случилось со строкой за прогон.
final _log = <String>[];

/// [dragIndex] строки: null — обычный список, где двигать нечего.
Future<void> _pumpRow(WidgetTester tester, {int? dragIndex}) async {
  _log.clear();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [jsonStoreProvider.overrideWithValue(JsonStore.memory())],
      child: MaterialApp(
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          // Список настоящий: `ReorderableDelayedDragStartListener` без него
          // не находит хозяина и падает на зажатии.
          body: ReorderableListView(
            buildDefaultDragHandles: false,
            onReorder: (from, to) => _log.add('reorder $from→$to'),
            children: [
              SizedBox(
                key: const ValueKey('row'),
                child: TrackRowShell(
                  track: _track,
                  active: false,
                  onTap: () => _log.add('tap'),
                  onMenu: () => _log.add('menu'),
                  dragIndex: dragIndex,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Обложка строки — по ней жмут, чтобы потащить.
Finder get _cover => find.byType(Cover);

/// Название трека — по нему жмут, чтобы открыть меню.
Finder get _title => find.text('sleep mode');

void main() {
  testWidgets('зажатие обложки не открывает меню трека', (tester) async {
    await _pumpRow(tester, dragIndex: 0);

    await tester.longPress(_cover);
    await tester.pumpAndSettle();

    expect(_log, isEmpty);
  });

  testWidgets('меню открывается долгим тапом по остальной строке', (
    tester,
  ) async {
    await _pumpRow(tester, dragIndex: 0);

    await tester.longPress(_title);
    await tester.pumpAndSettle();

    expect(_log, ['menu']);
  });

  testWidgets('тап по обложке остаётся тапом строки', (tester) async {
    await _pumpRow(tester, dragIndex: 0);

    await tester.tap(_cover);
    await tester.pumpAndSettle();

    expect(_log, ['tap']);
  });

  testWidgets('без тянучки меню открывается и с обложки', (tester) async {
    await _pumpRow(tester);

    await tester.longPress(_cover);
    await tester.pumpAndSettle();

    expect(_log, ['menu']);
  });
}
