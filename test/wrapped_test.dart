/// «Итоги»: периоды, расчёт по журналу, сам журнал, входы в профиле и шторка.
///
/// Часы везде подменные (`playLogClockProvider`): доступность года завязана на
/// число, и на настоящих часах половина проверок зависела бы от даты прогона.
///
/// В тестах шторки `pumpAndSettle` НЕЛЬЗЯ: слайд крутит полосу прогресса на
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
import 'package:bloom/features/profile/ui/profile_entry_card.dart'
    show kProfileEntryHeight;
import 'package:bloom/features/wrapped/periods.dart';
import 'package:bloom/features/wrapped/play_log.dart';
import 'package:bloom/features/wrapped/ui/wrapped_entries.dart';
import 'package:bloom/features/wrapped/ui/wrapped_poster.dart';
import 'package:bloom/features/wrapped/ui/wrapped_sheet.dart';
import 'package:bloom/features/wrapped/wrapped_data.dart';
import 'package:bloom/features/wrapped/wrapped_format.dart';
import 'package:bloom/features/wrapped/wrapped_store.dart';
import 'package:bloom/shared/ui/bloom_sheet.dart' show SheetHandle;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// 3 августа 2026: прошедший месяц — июль, окно года закрыто.
final _now = DateTime(2026, 8, 3, 12);

ProviderContainer _container({
  DateTime? now,
  JsonStore? plays,
  JsonStore? main,
}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(main ?? JsonStore.memory()),
      playLogStoreProvider.overrideWithValue(plays ?? JsonStore.memory()),
      playLogClockProvider.overrideWithValue(() => now ?? _now),
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
    test('месяц — прошлый целиком', () {
      final r = periodRange(PeriodKind.month, _now);
      expect(r.from, DateTime(2026, 7, 1));
      expect(r.to, DateTime(2026, 8, 1));
    });

    test('«показывать всегда» берёт у месяца идущий месяц', () {
      // Иначе проверять было бы нечего: журнал копится только с обновления, и
      // у прошедшего месяца сплошь и рядом ноль событий.
      final r = periodRange(PeriodKind.month, _now, true);
      expect(r.from, DateTime(2026, 8, 1));
      expect(r.to, _now);
    });

    test('год — с 1 января по сейчас', () {
      final r = periodRange(PeriodKind.year, _now);
      expect(r.from, DateTime(2026, 1, 1));
      expect(r.to, _now);
    });

    test('окно года — 21–31 декабря', () {
      expect(inYearWindow(_now), isFalse);
      expect(inYearWindow(DateTime(2026, 12, 20)), isFalse);
      expect(inYearWindow(DateTime(2026, 12, 22)), isTrue);
      expect(inYearWindow(DateTime(2026, 12, 31)), isTrue);
      // «Показывать всегда» открывает окно в любой день.
      expect(inYearWindow(_now, force: true), isTrue);
    });

    test('напоминать уместно 1-го числа и в декабрьском окне', () {
      // Это НЕ «доступны ли итоги» (месяц смотрят когда угодно), а только
      // повод кинуть уведомление.
      expect(scheduledPeriods(_now), isEmpty);
      expect(scheduledPeriods(DateTime(2026, 8, 1)), [PeriodKind.month]);
      expect(scheduledPeriods(DateTime(2026, 12, 22)), [PeriodKind.year]);
      // 1 декабря окно года ещё закрыто — только месяц.
      expect(scheduledPeriods(DateTime(2026, 12, 1)), [PeriodKind.month]);
      // 21 декабря совпали оба: год важнее.
      expect(scheduledPeriods(DateTime(2026, 12, 21)), [PeriodKind.year]);
      expect(scheduledPeriods(_now, force: true), kPeriodOrder);
    });

    test('ключ периода стабилен и различает виды', () {
      expect(periodKey(periodRange(PeriodKind.year, _now)), '2026');
      expect(periodKey(periodRange(PeriodKind.month, _now)), '2026-07');
      // Тот же период, спрошенный в другой час дня, даёт тот же ключ.
      expect(
        periodKey(periodRange(PeriodKind.month, DateTime(2026, 8, 3, 23))),
        periodKey(periodRange(PeriodKind.month, _now)),
      );
    });

    test('подпись периода — месяц с заглавной, год числом', () {
      expect(
        periodDatesLabel(periodRange(PeriodKind.month, _now), 'ru'),
        'Июль 2026',
      );
      expect(
        periodDatesLabel(periodRange(PeriodKind.year, _now), 'ru'),
        '2026',
      );
    });
  });

  group('расчёт', () {
    final month = periodRange(PeriodKind.month, _now);

    test('считает только события периода', () {
      final inside = _track('sc_1');
      final before = _track('sc_2');
      final after = _track('sc_3');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 6, 20), before), // раньше периода
          (DateTime(2026, 7, 28, 10), inside),
          (DateTime(2026, 7, 28, 11), inside),
          (DateTime(2026, 8, 2), after), // позже периода
        ]),
        month,
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
        month,
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
        month,
      );
      expect(data.uniqueArtists, 1);
      expect(data.topArtists.single.plays, 2);
    });

    test('мультиартистная строка считается по каждому участнику', () {
      final duo = _track('sc_1', artist: 'reidenshi, Øneheart', cover: 'a.jpg');
      final solo = _track('sc_2', artist: 'Øneheart');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), duo),
          (DateTime(2026, 7, 28, 9), solo),
        ]),
        month,
      );
      expect(data.uniqueArtists, 2);
      // Совместный трек идёт в зачёт обоим, вместе с обложкой.
      expect(data.topArtists.map((a) => a.name), ['Øneheart', 'reidenshi']);
      expect(data.topArtists.map((a) => a.plays), [2, 1]);
      expect(data.topArtists.map((a) => a.cover), ['a.jpg', 'a.jpg']);
    });

    test('площадка артиста — та, где его слушали чаще', () {
      // Аватар и страница берутся именно у неё: аккаунт с тем же именем на
      // соседней площадке принадлежит другому человеку.
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('sc_1', artist: 'Boards')),
          (DateTime(2026, 7, 28, 9), _track('ym_1', artist: 'Boards')),
          (DateTime(2026, 7, 29, 9), _track('ym_2', artist: 'Boards')),
        ]),
        month,
      );
      expect(data.topArtists.single.source, MusicSource.yandex);
    });

    test('свои файлы не отбирают у артиста площадку', () {
      // У локального артиста страницы нет, и искать его там, где слушали хотя
      // бы раз, — единственный способ на неё попасть.
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('local_1', artist: 'Boards')),
          (DateTime(2026, 7, 28, 9), _track('local_2', artist: 'Boards')),
          (DateTime(2026, 7, 29, 9), _track('sc_1', artist: 'Boards')),
        ]),
        month,
      );
      expect(data.topArtists.single.source, MusicSource.soundcloud);
    });

    test('открытия — только те, кого не было ДО периода', () {
      final old = _track('sc_1', artist: 'Старый');
      final fresh = _track('sc_2', artist: 'Новый');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 6, 1), old), // звучал раньше
          (DateTime(2026, 7, 28, 9), old),
          (DateTime(2026, 7, 28, 10), fresh),
        ]),
        month,
      );
      expect(data.newArtistsCount, 1);
      expect(data.newArtists.single.name, 'Новый');
      expect(data.newTracksCount, 1);
    });

    test('совместный трек ДО периода закрывает открытие обоим', () {
      // Строка «до периода» тоже разбирается: иначе оба участника навсегда
      // оставались бы «открытием» — по склеенному имени их не узнать.
      final duo = _track('sc_1', artist: 'reidenshi, Øneheart');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 6, 1), duo), // звучал раньше
          (DateTime(2026, 7, 28, 9), _track('sc_2', artist: 'Øneheart')),
          (DateTime(2026, 7, 28, 10), _track('sc_3', artist: 'reidenshi')),
        ]),
        month,
      );
      expect(data.uniqueArtists, 2);
      expect(data.newArtistsCount, 0);
      expect(data.newArtists, isEmpty);
    });

    test('площадки разбираются по префиксу id', () {
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('sc_1')),
          (DateTime(2026, 7, 27, 10), _track('ym_1')),
          (DateTime(2026, 7, 27, 11), _track('ym_2')),
        ]),
        month,
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
        month,
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
        month,
      );
      expect(data.hours[2], 2);
      expect(data.hours[15], 1);
      expect(data.peakHour, 2);
      expect(data.nightShare, closeTo(2 / 3, 0.001));
    });

    test('пустой период — пустые итоги', () {
      final data = buildWrapped(const PlayLog(), month);
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
        month,
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
      expect(log.events.single.ts, _now.millisecondsSinceEpoch);
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
        playLogClockProvider.overrideWithValue(() => now ?? _now),
      ]);
      return seed;
    }

    test('месяц доступен всегда, год — только в декабре', () {
      final c = withPlays([
        (DateTime(2026, 7, 28, 9), _track('sc_1')),
        (DateTime(2026, 7, 29, 9), _track('sc_2')),
      ]);
      final entries = c.read(wrappedEntriesProvider);
      expect(entries.month!.plays, 2);
      expect(entries.monthUnseen, isTrue);
      // 3 августа окно года закрыто — плашки нет, хотя данные за год есть.
      expect(entries.year, isNull);
    });

    test('в декабрьском окне появляется и год', () {
      final c = withPlays([
        (DateTime(2026, 12, 5, 9), _track('sc_1')),
      ], now: DateTime(2026, 12, 22, 12));
      final entries = c.read(wrappedEntriesProvider);
      expect(entries.year, isNotNull);
      expect(entries.yearUnseen, isTrue);
      // Ноябрь пустой — итогов месяца не существует.
      expect(entries.month, isNull);
    });

    test('пустой период — входа нет', () {
      // Слушали до июля: подводить за месяц нечего.
      final c = withPlays([(DateTime(2026, 6, 1, 9), _track('sc_1'))]);
      expect(c.read(wrappedEntriesProvider).month, isNull);
    });

    test('тумблер «показывать» убирает все входы', () {
      final c = withPlays([(DateTime(2026, 7, 28, 9), _track('sc_1'))]);
      c.read(wrappedPrefsProvider.notifier).setShow(false);
      expect(c.read(wrappedEntriesProvider).isEmpty, isTrue);
    });

    test('«показывать всегда» открывает год и берёт идущий месяц', () {
      final c = withPlays([(DateTime(2026, 8, 2, 9), _track('sc_1'))]);
      // Событие в августе: прошедший месяц (июль) пуст, окно года закрыто.
      expect(c.read(wrappedEntriesProvider).isEmpty, isTrue);

      c.read(wrappedPrefsProvider.notifier).setAlways(true);
      final entries = c.read(wrappedEntriesProvider);
      expect(entries.year, isNotNull);
      expect(entries.month!.range.from, DateTime(2026, 8, 1));
    });

    test('про период напоминаем один раз — и после перезапуска тоже', () {
      final main = JsonStore.memory();
      final c = withPlays([
        (DateTime(2026, 7, 28, 9), _track('sc_1')),
      ], main: main);
      final prefs = c.read(wrappedPrefsProvider.notifier);
      final range = c.read(wrappedEntriesProvider).month!.range;

      expect(prefs.isNotified(range), isFalse);
      prefs.markNotified(range);
      expect(prefs.isNotified(range), isTrue);
      // Список уведомлений живёт только сессию, а отметка — на диске.
      final again = _container(main: main);
      expect(
        again.read(wrappedPrefsProvider.notifier).isNotified(range),
        isTrue,
      );
      // Просмотр и напоминание — разные отметки: одна не гасит другую.
      expect(again.read(wrappedPrefsProvider.notifier).isSeen(range), isFalse);
    });

    test('просмотр снимает подмену и переживает перезапуск', () {
      final main = JsonStore.memory();
      final c = withPlays([
        (DateTime(2026, 7, 28, 9), _track('sc_1')),
      ], main: main);
      final range = c.read(wrappedEntriesProvider).month!.range;
      c.read(wrappedPrefsProvider.notifier).markSeen(range);
      expect(c.read(wrappedEntriesProvider).monthUnseen, isFalse);
      expect(c.read(wrappedPrefsProvider.notifier).isSeen(range), isTrue);

      // Другой месяц просмотренным не считается.
      final older = PeriodRange(
        PeriodKind.month,
        DateTime(2026, 6, 1),
        DateTime(2026, 7, 1),
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

      // Слайду нужны отдельные числа с подписью, а не готовая строка.
      expect(splitListenTime(l, 20), isEmpty);
      expect(splitListenTime(l, 3600 * 2), [(n: 2, word: 'часа')]);
      expect(splitListenTime(l, 3600 * 12 + 60 * 34), [
        (n: 12, word: 'часов'),
        (n: 34, word: 'минуты'),
      ]);
      expect(splitListenTime(l, 60 * 45), [(n: 45, word: 'минут')]);
    });
  });

  group('постер', () {
    testWidgets('полный топ из пяти строк влезает в карточку 3:4', (
      tester,
    ) async {
      // Раскладка постера считается в фиксированном дизайн-боксе, и при
      // полном топе запас там маленький: переполнение Column'а вылезло бы
      // жёлто-чёрной полосой прямо в отправленной картинке.
      final month = periodRange(PeriodKind.month, _now);
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
        month,
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

  group('входы и шторка', () {
    /// Данные месяца из пары прослушиваний — их хватает всем входам.
    WrappedData monthData() => buildWrapped(
      _log([
        (DateTime(2026, 7, 28, 9), _track('sc_1', name: 'Песня')),
        (DateTime(2026, 7, 29, 9), _track('sc_1', name: 'Песня')),
      ]),
      periodRange(PeriodKind.month, _now),
    );

    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(),
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildBloomTheme(BloomThemes.dark),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

    testWidgets('карточка месяца называет период и зовёт смотреть', (
      tester,
    ) async {
      await pump(tester, WrappedMonthCard(data: monthData()));
      expect(find.text('Итоги месяца'), findsOneWidget);
      expect(find.text('Июль 2026'), findsOneWidget);
      expect(find.text('НОВОЕ'), findsOneWidget);
      expect(find.text('Смотреть'), findsOneWidget);
      // Ростом с соседей по ряду: своя высота читалась бы ступенькой.
      expect(
        tester.getSize(find.byType(WrappedMonthCard)).height,
        kProfileEntryHeight,
      );
    });

    testWidgets('плашка года показывает прослушивания и время', (tester) async {
      final year = buildWrapped(
        _log([(DateTime(2026, 3, 1, 9), _track('sc_1', seconds: 3600))]),
        periodRange(PeriodKind.year, _now),
      );
      await pump(tester, WrappedYearBanner(data: year));
      expect(find.text('Итоги года'), findsOneWidget);
      expect(find.text('1 прослушивание · 1 час'), findsOneWidget);
      expect(
        tester.getSize(find.byType(WrappedYearBanner)).height,
        kProfileEntryHeight,
      );
      // Текст стоит по центру плашки: непозиционированный ребёнок `Stack` без
      // `StackFit.expand` уезжает к верхнему краю — наступил 2026-08-30.
      final title = tester.getRect(find.text('Итоги года'));
      final banner = tester.getRect(find.byType(WrappedYearBanner));
      expect(
        (title.center.dy - banner.center.dy).abs(),
        lessThan(banner.height / 4),
      );
      // Волна анимируется вечно — снимаем виджет, чтобы тест не ждал таймеров.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('шторка открывается на своём периоде и листается', (
      tester,
    ) async {
      late BuildContext ctx;
      await pump(
        tester,
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      );

      showWrappedSheet(ctx, period: PeriodKind.month, data: monthData());
      // Один кадр открытия: `pumpAndSettle` здесь зациклится на полосе
      // прогресса слайда (см. шапку файла).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Первый слайд называет период датами (кикер идёт капсом), дальше ведёт
      // кнопка.
      expect(find.text('ИЮЛЬ 2026'), findsOneWidget);
      // Внизу обе кнопки: выйти можно с любого слайда, а не только с последнего.
      expect(find.text('Далее'), findsOneWidget);
      expect(find.text('Закрыть'), findsOneWidget);
      // Пилюля тянется во всю ширину шторки. Без растяжки она обтягивает своё
      // слово и вырождается в кружок — наступил 2026-08-30.
      final pill = tester.getSize(find.widgetWithText(Material, 'Далее').last);
      final screen = tester.getSize(find.byType(MaterialApp));
      expect(pill.width, greaterThan(screen.width / 2));
      // И сама шторка крупная — не полоска у нижней кромки: её верх (ручка)
      // выше середины экрана.
      expect(
        tester.getTopLeft(find.byType(SheetHandle)).dy,
        lessThan(screen.height / 2),
      );

      final top = tester.getTopLeft(find.byType(SheetHandle)).dy;

      await tester.tap(find.text('Далее'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // Второй слайд — время прослушивания.
      expect(find.text('Ты слушал музыку'), findsOneWidget);

      // Долистываем до постера: там «Далее» уходит, и его место обязано забрать
      // тело — иначе шторка на последнем слайде становится ниже (наступил
      // 2026-08-30).
      for (var i = 0; i < 20 && find.text('Далее').evaluate().isNotEmpty; i++) {
        await tester.tap(find.text('Далее'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }
      expect(find.text('Далее'), findsNothing);
      // «Не ниже», а не «ровно столько же»: на узком экране постер сам просит
      // больше места, и шторка честно подрастает. Ловим именно усадку.
      expect(
        tester.getTopLeft(find.byType(SheetHandle)).dy,
        lessThanOrEqualTo(top),
      );

      // Уносим шторку со сцены: иначе тест валится на неостывших таймерах.
      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
