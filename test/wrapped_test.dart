/// «Итоги»: расписание периодов, расчёт по журналу, сам журнал и вход на
/// главной.
///
/// Часы везде подменные (`playLogClockProvider`): расписание завязано на день
/// недели и число, и на настоящих часах половина проверок зависела бы от даты
/// прогона.
///
/// В тестах истории `pumpAndSettle` НЕЛЬЗЯ: слайд крутит полосу прогресса на
/// 6 секунд и по её концу переключается на следующий — «устоится» такое дерево
/// только в конце последнего слайда. Кадры крутим руками (те же грабли, что с
/// кольцами онбординга и качанием плиток волны).
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/shared/ui/atoms.dart' show kHeaderControl;
import 'package:bloom/features/wrapped/periods.dart';
import 'package:bloom/features/wrapped/play_log.dart';
import 'package:bloom/features/wrapped/ui/wrapped_circle.dart';
import 'package:bloom/features/wrapped/ui/wrapped_poster.dart';
import 'package:bloom/features/wrapped/wrapped_data.dart';
import 'package:bloom/features/wrapped/wrapped_format.dart';
import 'package:bloom/features/wrapped/wrapped_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Понедельник 3 августа 2026 года — в этот день открыто окно «недели».
final _monday = DateTime(2026, 8, 3, 12);

ProviderContainer _container({
  DateTime? now,
  JsonStore? plays,
  JsonStore? main,
}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(main ?? JsonStore.memory()),
      playLogStoreProvider.overrideWithValue(plays ?? JsonStore.memory()),
      playLogClockProvider.overrideWithValue(() => now ?? _monday),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Track _track(
  String id, {
  String name = 'Track',
  String artist = 'Artist',
  String? cover,
  int seconds = 180,
}) => Track(
  id: id,
  name: name,
  artist: artist,
  duration: Duration(seconds: seconds),
  source: MusicSource.fromId(id),
  cover: cover,
);

/// Журнал прямо из событий — расчёт проверяется без плеера и без файла.
PlayLog _log(List<(DateTime, Track)> events) {
  final meta = <String, PlayMeta>{};
  final list = <PlayEvent>[];
  for (final (at, track) in events) {
    list.add(PlayEvent(at.millisecondsSinceEpoch, track.id));
    meta[track.id] = PlayMeta(
      name: track.name,
      artist: track.artist,
      cover: track.cover,
      seconds: track.duration.inSeconds,
    );
  }
  list.sort((a, b) => a.ts.compareTo(b.ts));
  return PlayLog(events: list, meta: meta);
}

void main() {
  // В приложении названия месяцев поднимает `flutter_localizations` при
  // загрузке локали; здесь дерева нет, поэтому даты инициализируем сами.
  setUpAll(() => initializeDateFormatting('ru'));

  group('периоды', () {
    test('неделя — прошлая, пн по вс', () {
      final r = periodRange(PeriodKind.week, _monday);
      expect(r.from, DateTime(2026, 7, 27));
      expect(r.to, DateTime(2026, 8, 3));
    });

    test('месяц — прошлый целиком', () {
      final r = periodRange(PeriodKind.month, _monday);
      expect(r.from, DateTime(2026, 7, 1));
      expect(r.to, DateTime(2026, 8, 1));
    });

    test('год — с 1 января по сейчас', () {
      final r = periodRange(PeriodKind.year, _monday);
      expect(r.from, DateTime(2026, 1, 1));
      expect(r.to, _monday);
    });

    test('окна показа: понедельник, 1-е число, 21–31 декабря', () {
      expect(availablePeriods(now: _monday), [PeriodKind.week]);
      // 1 августа 2026 — суббота: только месяц.
      expect(availablePeriods(now: DateTime(2026, 8, 1)), [PeriodKind.month]);
      // 1 июня 2026 — понедельник: месяц и неделя, месяц важнее.
      expect(availablePeriods(now: DateTime(2026, 6, 1)), [
        PeriodKind.month,
        PeriodKind.week,
      ]);
      expect(availablePeriods(now: DateTime(2026, 12, 22)), [PeriodKind.year]);
      // 20 декабря — окно года ещё не открылось, и это вторник.
      expect(availablePeriods(now: DateTime(2026, 12, 20)), isEmpty);
    });

    test('«показывать всегда» открывает все три', () {
      expect(
        availablePeriods(now: DateTime(2026, 12, 20), force: true),
        kPeriodOrder,
      );
    });

    test('ключ периода стабилен и различает виды', () {
      expect(periodKey(periodRange(PeriodKind.year, _monday)), '2026');
      expect(periodKey(periodRange(PeriodKind.month, _monday)), '2026-07');
      // Неделя 27 июля — 2 августа 2026.
      expect(periodKey(periodRange(PeriodKind.week, _monday)), '2026-W31');
      // Тот же период, спрошенный в другой час дня, даёт тот же ключ.
      expect(
        periodKey(periodRange(PeriodKind.week, DateTime(2026, 8, 3, 23))),
        periodKey(periodRange(PeriodKind.week, _monday)),
      );
    });

    test('подпись недели не повторяет месяц дважды', () {
      final same = PeriodRange(
        PeriodKind.week,
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 10),
      );
      expect(periodDatesLabel(same, 'ru'), '3 — 9 августа');
      final across = periodRange(PeriodKind.week, _monday);
      expect(periodDatesLabel(across, 'ru'), '27 июля — 2 августа');
      expect(
        periodDatesLabel(periodRange(PeriodKind.month, _monday), 'ru'),
        'Июль 2026',
      );
    });
  });

  group('расчёт', () {
    final week = periodRange(PeriodKind.week, _monday);

    test('считает только события периода', () {
      final inside = _track('sc_1');
      final before = _track('sc_2');
      final after = _track('sc_3');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 20), before), // раньше периода
          (DateTime(2026, 7, 28, 10), inside),
          (DateTime(2026, 7, 28, 11), inside),
          (DateTime(2026, 8, 5), after), // позже периода
        ]),
        week,
      );
      expect(data.plays, 2);
      expect(data.uniqueTracks, 1);
      expect(data.seconds, 360);
      expect(data.topTracks.single.id, 'sc_1');
    });

    test('топ треков по числу прослушиваний', () {
      final one = _track('sc_1', name: 'Один');
      final two = _track('sc_2', name: 'Два');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), one),
          (DateTime(2026, 7, 28, 9), two),
          (DateTime(2026, 7, 29, 9), two),
        ]),
        week,
      );
      expect(data.topTracks.map((t) => t.name), ['Два', 'Один']);
      expect(data.topTracks.first.plays, 2);
    });

    test('артисты группируются без учёта регистра и пробелов', () {
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('sc_1', artist: 'Boards')),
          (DateTime(2026, 7, 28, 9), _track('sc_2', artist: ' boards ')),
        ]),
        week,
      );
      expect(data.uniqueArtists, 1);
      expect(data.topArtists.single.plays, 2);
    });

    test('открытия — только те, кого не было ДО периода', () {
      final old = _track('sc_1', artist: 'Старый');
      final fresh = _track('sc_2', artist: 'Новый');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 1), old), // звучал раньше
          (DateTime(2026, 7, 28, 9), old),
          (DateTime(2026, 7, 28, 10), fresh),
        ]),
        week,
      );
      expect(data.newArtistsCount, 1);
      expect(data.newArtists.single.name, 'Новый');
      expect(data.newTracksCount, 1);
    });

    test('площадки разбираются по префиксу id', () {
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('sc_1')),
          (DateTime(2026, 7, 27, 10), _track('ym_1')),
          (DateTime(2026, 7, 27, 11), _track('ym_2')),
        ]),
        week,
      );
      expect(data.sources.first.source, MusicSource.yandex);
      expect(data.sources.first.plays, 2);
      expect(data.sources.last.source, MusicSource.soundcloud);
    });

    test('рекорд дня, серия и активные дни', () {
      final t = _track('sc_1');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), t),
          (DateTime(2026, 7, 28, 9), t),
          (DateTime(2026, 7, 28, 10), t),
          (DateTime(2026, 7, 28, 11), t),
          // Пропуск 29-го рвёт серию.
          (DateTime(2026, 7, 30, 9), t),
        ]),
        week,
      );
      expect(data.recordDay!.plays, 3);
      expect(data.recordDay!.date, DateTime(2026, 7, 28));
      expect(data.activeDays, 3);
      expect(data.streak, 2);
    });

    test('часы, пик и доля ночи', () {
      final t = _track('sc_1');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 2), t),
          (DateTime(2026, 7, 27, 2, 30), t),
          (DateTime(2026, 7, 27, 15), t),
        ]),
        week,
      );
      expect(data.hours[2], 2);
      expect(data.hours[15], 1);
      expect(data.peakHour, 2);
      expect(data.nightShare, closeTo(2 / 3, 0.001));
    });

    test('пустой период — пустые итоги', () {
      final data = buildWrapped(const PlayLog(), week);
      expect(data.isEmpty, isTrue);
      expect(data.recordDay, isNull);
      expect(data.nightShare, 0);
    });

    test('событие без снимка трека всё равно считается', () {
      // Снимок мог не сохраниться (трек не резолвился) — на ПК это тот же
      // STUB: прослушивание не должно пропадать из итогов.
      final data = buildWrapped(
        PlayLog(
          events: [
            PlayEvent(DateTime(2026, 7, 28, 9).millisecondsSinceEpoch, 'ym_9'),
          ],
        ),
        week,
      );
      expect(data.plays, 1);
      expect(data.uniqueTracks, 1);
      expect(data.uniqueArtists, 0);
      expect(data.sources.single.source, MusicSource.yandex);
    });
  });

  group('журнал', () {
    test('пишет событие и снимок, читает обратно из файла', () {
      final file = JsonStore.memory();
      final c = _container(plays: file);
      c
          .read(playLogProvider.notifier)
          .log(_track('sc_1', name: 'Песня', artist: 'Артист', seconds: 200));

      final again = _container(plays: file);
      final log = again.read(playLogProvider);
      expect(log.events.single.id, 'sc_1');
      expect(log.events.single.ts, _monday.millisecondsSinceEpoch);
      expect(log.meta['sc_1']!.name, 'Песня');
      expect(log.meta['sc_1']!.seconds, 200);
    });

    test('битые записи не роняют чтение', () {
      final file = JsonStore.memory({
        'events': [
          [1, 'sc_1'],
          'мусор',
          [null, 'sc_2'],
          [2, 'sc_3'],
        ],
        'meta': {
          'sc_1': ['Имя', 'Артист', null, 100],
          'sc_3': 'мусор',
        },
      });
      final log = _container(plays: file).read(playLogProvider);
      expect(log.events.map((e) => e.id), ['sc_1', 'sc_3']);
      expect(log.meta.keys, ['sc_1']);
    });

    test('события всегда по возрастанию времени', () {
      final file = JsonStore.memory({
        'events': [
          [200, 'sc_2'],
          [100, 'sc_1'],
        ],
      });
      final log = _container(plays: file).read(playLogProvider);
      expect(log.events.map((e) => e.ts), [100, 200]);
    });

    test('очистка обнуляет и файл', () {
      final file = JsonStore.memory();
      final c = _container(plays: file);
      c.read(playLogProvider.notifier)
        ..log(_track('sc_1'))
        ..clear();
      expect(c.read(playLogProvider).isEmpty, isTrue);
      expect(_container(plays: file).read(playLogProvider).isEmpty, isTrue);
    });
  });

  group('что показывать', () {
    ProviderContainer withPlays(
      List<(DateTime, Track)> events, {
      DateTime? now,
      JsonStore? main,
    }) {
      final file = JsonStore.memory();
      final seed = _container(plays: file, now: now, main: main);
      final log = seed.read(playLogProvider.notifier);
      for (final (at, track) in events) {
        seed.updateOverrides([
          jsonStoreProvider.overrideWithValue(main ?? JsonStore.memory()),
          playLogStoreProvider.overrideWithValue(file),
          playLogClockProvider.overrideWithValue(() => at),
        ]);
        log.log(track);
      }
      seed.updateOverrides([
        jsonStoreProvider.overrideWithValue(main ?? JsonStore.memory()),
        playLogStoreProvider.overrideWithValue(file),
        playLogClockProvider.overrideWithValue(() => now ?? _monday),
      ]);
      return seed;
    }

    test('есть журнал и открыто окно — итоги есть', () {
      final c = withPlays([
        (DateTime(2026, 7, 28, 9), _track('sc_1')),
        (DateTime(2026, 7, 29, 9), _track('sc_2')),
      ]);
      final ready = c.read(wrappedProvider);
      expect(ready, isNotNull);
      expect(ready!.periods, [PeriodKind.week]);
      expect(ready.primaryData.plays, 2);
      expect(ready.unseen, isTrue);
    });

    test('пустой период — итогов нет', () {
      // Слушали ДО прошлой недели: окно открыто, а подводить нечего.
      final c = withPlays([(DateTime(2026, 6, 1, 9), _track('sc_1'))]);
      expect(c.read(wrappedProvider), isNull);
    });

    test('тумблер «показывать» убирает вход', () {
      final c = withPlays([(DateTime(2026, 7, 28, 9), _track('sc_1'))]);
      c.read(wrappedPrefsProvider.notifier).setShow(false);
      expect(c.read(wrappedProvider), isNull);
    });

    test('«показывать всегда» открывает итоги вне расписания', () {
      // Вторник, все окна закрыты.
      final c = withPlays([
        (DateTime(2026, 8, 3, 9), _track('sc_1')),
      ], now: DateTime(2026, 8, 4, 12));
      expect(c.read(wrappedProvider), isNull);
      c.read(wrappedPrefsProvider.notifier).setAlways(true);
      final ready = c.read(wrappedProvider);
      expect(ready, isNotNull);
      // Значимость: год важнее месяца, месяц — недели.
      expect(ready!.primary, PeriodKind.year);
    });

    test('просмотр гасит кольцо и переживает перезапуск', () {
      final main = JsonStore.memory();
      final c = withPlays([
        (DateTime(2026, 7, 28, 9), _track('sc_1')),
      ], main: main);
      final range = c.read(wrappedProvider)!.primaryData.range;
      c.read(wrappedPrefsProvider.notifier).markSeen(range);
      expect(c.read(wrappedProvider)!.unseen, isFalse);
      expect(c.read(wrappedPrefsProvider.notifier).isSeen(range), isTrue);

      // Другой период того же вида просмотренным не считается.
      final older = PeriodRange(
        PeriodKind.week,
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 27),
      );
      expect(c.read(wrappedPrefsProvider.notifier).isSeen(older), isFalse);
    });
  });

  group('формат', () {
    testWidgets('время прослушивания по-русски', (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(fmtListenTime(l, 20), 'Меньше минуты');
      expect(fmtListenTime(l, 60 * 45), '45 минут');
      expect(fmtListenTime(l, 3600 * 2), '2 часа');
      expect(fmtListenTime(l, 3600 * 12 + 60 * 34), '12 часов 34 минуты');
      expect(fmtHourRange(l, 23), '23:00 — 00:00');
    });
  });

  group('постер', () {
    testWidgets('полный топ из пяти строк влезает в карточку 3:4', (
      tester,
    ) async {
      // Раскладка постера считается в фиксированном дизайн-боксе, и при
      // полном топе запас там маленький: переполнение Column'а вылезло бы
      // жёлто-чёрной полосой прямо в отправленной картинке.
      final week = periodRange(PeriodKind.week, _monday);
      final data = buildWrapped(
        _log([
          for (var i = 0; i < 5; i++)
            for (var n = 0; n <= i; n++)
              (
                DateTime(2026, 7, 28, 9, i * 10 + n),
                _track(
                  'sc_$i',
                  name: 'Довольно длинное название трека номер $i',
                  artist: 'Исполнитель с длинным именем $i',
                ),
              ),
        ]),
        week,
      );
      expect(data.topTracks.length, 5);
      expect(data.topArtists.length, 5);

      final c = _container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildBloomTheme(BloomThemes.dark),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  height: 560,
                  child: WrappedPosterCard(
                    data: data,
                    accent: BloomThemes.dark.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.text('Поделиться'), findsOneWidget);
      expect(find.text('ТОП-ТРЕКИ'), findsOneWidget);
      expect(find.text('ТОП-АРТИСТЫ'), findsOneWidget);
    });
  });

  group('вход на главной', () {
    Future<void> pump(WidgetTester tester, ProviderContainer c) =>
        tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildBloomTheme(BloomThemes.dark),
              home: const Scaffold(body: WrappedCircle()),
            ),
          ),
        );

    testWidgets('без итогов кнопка не занимает места в ряду', (tester) async {
      await pump(tester, _container());
      // Не «спрятана», а схлопнута в ноль вместе со своим зазором: иначе в
      // шапке главной осталась бы дырка между «Bloom» и колокольчиком.
      expect(tester.getSize(find.byType(WrappedCircle)), Size.zero);
    });

    testWidgets('с итогами показывает период и открывает историю', (
      tester,
    ) async {
      final file = JsonStore.memory({
        'events': [
          [DateTime(2026, 7, 28, 9).millisecondsSinceEpoch, 'sc_1'],
          [DateTime(2026, 7, 29, 9).millisecondsSinceEpoch, 'sc_1'],
        ],
        'meta': {
          'sc_1': ['Песня', 'Артист', null, 180],
        },
      });
      final c = _container(plays: file);
      await pump(tester, c);
      // Кнопка ростом с соседей по ряду шапки плюс зазор до колокольчика.
      expect(
        tester.getSize(find.byType(WrappedCircle)),
        const Size(kHeaderControl + 8, kHeaderControl),
      );

      await tester.tap(find.byType(WrappedCircle));
      // Один кадр перехода: `pumpAndSettle` здесь зациклится на полосе
      // прогресса слайда (см. шапку файла).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Открылся экран выбора периода — на карточке даты и цифры.
      expect(find.text('27 июля — 2 августа'), findsOneWidget);
      expect(find.text('2 прослушивания'), findsOneWidget);
      // Докрутить кадры до конца каскада появления: пока в очереди висит хоть
      // один таймер, тест валится на `!timersPending`.
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
