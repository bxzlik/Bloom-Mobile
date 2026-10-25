/// Расширенный вид очереди: настройка, разбиение на секции и перевод номеров.
///
/// Проверяем то, что ломается тихо. Номеров у строки два — свой в секции
/// (тянучка) и свой в очереди (запуск, меню, «Убрать из очереди»), и перепутать
/// их на второй секции ничего не мешает: список выглядит правильно, а действия
/// бьют по чужим строкам. Плюс сама раскладка: играющий обязан быть закреплён,
/// а пустых секций быть не должно.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/player_view_store.dart';
import 'package:bloom/features/player/ui/queue_sheet.dart';
import 'package:bloom/l10n/app_localizations.dart';
import 'package:bloom/shared/ui/entity_tiles.dart';
import 'package:bloom/shared/ui/track_swipes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';
import 'package:just_audio/just_audio.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Трек $id',
  artist: 'Артист $id',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

/// Очередь без звука: настоящий контроллер лезет за `audioHandlerProvider`,
/// которого в тестах нет. Перестановку не делает, а записывает — проверяем
/// именно то, какие номера до неё доехали.
class _FakePlayback extends PlaybackController {
  _FakePlayback(this.initial);

  final PlaybackState initial;
  final List<(int, int)> reorders = [];

  @override
  PlaybackState build() => initial;

  @override
  void reorder(int from, int to) => reorders.add((from, to));
}

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('настройка', () {
    test('по умолчанию вид обычный, как на ПК', () {
      final c = _container(JsonStore.memory());
      expect(c.read(queueViewProvider), QueueView.normal);
      expect(c.read(queueViewProvider).isExtended, isFalse);
    });

    test('выбранный вид читается с диска', () {
      final c = _container(
        JsonStore.memory({
          'playerView': {'queueView': 'extended'},
        }),
      );
      expect(c.read(queueViewProvider).isExtended, isTrue);
    });

    test('незнакомая запись — это обычный вид, а не падение', () {
      final c = _container(
        JsonStore.memory({
          'playerView': {'queueView': 'sections'},
        }),
      );
      expect(c.read(queueViewProvider), QueueView.normal);
    });

    test('выбор уезжает на диск и не сносит соседнюю настройку', () {
      final store = JsonStore.memory({
        'playerView': {'titleAlign': 'left'},
      });
      final c = _container(store);
      c.read(queueViewProvider.notifier).set(QueueView.extended);

      final saved = store.read('playerView')! as Map;
      expect(saved['queueView'], 'extended');
      expect(saved['titleAlign'], 'left');
      expect(c.read(titleAlignProvider), TitleAlign.left);
    });
  });

  group('промотка при открытии', () {
    test('обычный вид оставляет две строки запаса сверху', () {
      expect(queueScrollOffset(index: 2, extended: false), 0);
      expect(queueScrollOffset(index: 5, extended: false), 3 * kTrackRowHeight);
    });

    test('расширенный ставит наверх заголовок «Сейчас играет»', () {
      // Выше него — вся секция «Прослушано» вместе со СВОИМ заголовком.
      expect(
        queueScrollOffset(index: 3, extended: true),
        3 * kTrackRowHeight + kQueueSectionLabel,
      );
    });

    test('играет первый — прокручивать нечего, заголовка «Прослушано» нет', () {
      expect(queueScrollOffset(index: 0, extended: true), 0);
    });
  });

  group('секции', () {
    /// Шторка очереди на пять треков; [index] — какой играет.
    Future<_FakePlayback> pump(
      WidgetTester tester, {
      required bool extended,
      int index = 2,
      int length = 5,
    }) async {
      final playback = _FakePlayback(
        PlaybackState(
          queue: [
            for (var i = 0; i < length; i++)
              _track(String.fromCharCode(97 + i)),
          ],
          index: index,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jsonStoreProvider.overrideWithValue(
              JsonStore.memory({
                if (extended) 'playerView': {'queueView': 'extended'},
              }),
            ),
            dbProvider.overrideWithValue(BloomDb.memory()),
            playbackProvider.overrideWith(() => playback),
            // Строке играющего трека нужен поток play/pause (эквалайзер вместо
            // длительности). Настоящего звука в тестах нет — отдаём молчащий
            // плеер, его `playingStream` живёт внутри самого объекта.
            audioPlayerProvider.overrideWithValue(AudioPlayer()),
          ],
          child: MaterialApp(
            theme: buildBloomTheme(BloomThemes.dark),
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showQueueSheet(context),
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      // Не `pumpAndSettle`: у играющей строки эквалайзер, и на паузе он замирает
      // не сразу — кадры крутим сами.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return playback;
    }

    /// Пары «номер в очереди → номер в своей секции» по всем строкам шторки.
    List<(int, int?)> rows(WidgetTester tester) => [
      for (final swipe in tester.widgetList<TrackSwipe>(
        find.byType(TrackSwipe),
      ))
        (swipe.queueIndex!, (swipe.child as dynamic).dragIndex as int?),
    ];

    testWidgets('обычный вид секций не рисует', (tester) async {
      await pump(tester, extended: false);
      expect(find.text('ПРОСЛУШАНО'), findsNothing);
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsNothing);
      expect(find.text('ДАЛЕЕ'), findsNothing);
      // Номер строки в списке и в очереди — один и тот же.
      expect(rows(tester), [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)]);
    });

    testWidgets('расширенный бьёт очередь на три секции', (tester) async {
      await pump(tester, extended: true);
      expect(find.text('ПРОСЛУШАНО'), findsOneWidget);
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsOneWidget);
      expect(find.text('ДАЛЕЕ'), findsOneWidget);
    });

    testWidgets('номер тянучки — свой в секции, номер очереди — общий', (
      tester,
    ) async {
      await pump(tester, extended: true);
      expect(rows(tester), [
        // «Прослушано» начинается с нуля очереди — номера совпадают.
        (0, 0),
        (1, 1),
        // Играющий закреплён: тянучки у него нет вовсе.
        (2, null),
        // «Далее» начинается с третьего трека очереди, а внутри себя — с нуля.
        (3, 0),
        (4, 1),
      ]);
    });

    testWidgets('перестановка в «Далее» уходит номерами очереди', (
      tester,
    ) async {
      final playback = await pump(tester, extended: true);
      final lists = tester
          .widgetList<SliverReorderableList>(find.byType(SliverReorderableList))
          .toList();
      expect(lists, hasLength(2));
      // Первую строку «Далее» (третью в очереди) тащим в конец секции.
      lists.last.onReorder(0, 2);
      expect(playback.reorders, [(3, 5)]);
    });

    testWidgets('играет первый — секции «Прослушано» нет', (tester) async {
      await pump(tester, extended: true, index: 0);
      expect(find.text('ПРОСЛУШАНО'), findsNothing);
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsOneWidget);
      expect(find.text('ДАЛЕЕ'), findsOneWidget);
      expect(rows(tester), [(0, null), (1, 0), (2, 1), (3, 2), (4, 3)]);
    });

    testWidgets('играет последний — секции «Далее» нет', (tester) async {
      await pump(tester, extended: true, index: 4);
      expect(find.text('ПРОСЛУШАНО'), findsOneWidget);
      expect(find.text('ДАЛЕЕ'), findsNothing);
    });

    testWidgets('один трек в очереди — только «Сейчас играет»', (tester) async {
      await pump(tester, extended: true, index: 0, length: 1);
      expect(find.text('ПРОСЛУШАНО'), findsNothing);
      expect(find.text('ДАЛЕЕ'), findsNothing);
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsOneWidget);
      expect(rows(tester), [(0, null)]);
    });
  });
}
