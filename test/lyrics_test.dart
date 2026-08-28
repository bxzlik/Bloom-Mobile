/// Текст песни: разбор LRC, подбор строки под позицию, единицы заливки,
/// нормализация запроса со скорингом, кеш и сам стор.
///
/// Проверяем то, что ломается незаметно: подсветку не на той строке, деление
/// строки на слова с неверными таймингами, ответ сети для уже сменённого трека
/// и повторный поход в сеть за тем же треком.
///
/// Текст в тестах синтетический («line one») — настоящие песни тут не нужны и
/// не должны попадать в репозиторий.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/lyrics/lrc.dart';
import 'package:bloom/features/lyrics/lyrics_api.dart';
import 'package:bloom/features/lyrics/lyrics_cache.dart';
import 'package:bloom/features/lyrics/lyrics_store.dart';
import 'package:bloom/features/lyrics/lyrics_style_store.dart';
import 'package:bloom/features/lyrics/ui/lyrics_view.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = Track(
  id: 'sc_1',
  name: 'Song',
  artist: 'Band',
  duration: Duration(seconds: 180),
  source: MusicSource.soundcloud,
);

/// Контейнер с подменённой сетью: [answer] — что «нашлось» в LRCLIB.
ProviderContainer _container({
  required Future<LyricsResult> Function() answer,
  JsonStore? store,
  void Function(String artist, String title)? onFetch,
}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store ?? JsonStore.memory()),
      lyricsFetcherProvider.overrideWithValue(({
        required artist,
        required title,
        durationSec,
      }) {
        onFetch?.call(artist, title);
        return answer();
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('parseLrc', () {
    test('разбирает тайм-коды и сортирует по времени', () {
      final lines = parseLrc('[00:12.50]second\n[00:03.00]first\n');
      expect(lines.map((l) => l.text), ['first', 'second']);
      expect(lines.first.time, 3.0);
      expect(lines.last.time, 12.5);
    });

    test('минуты переводятся в секунды', () {
      expect(parseLrc('[02:05.00]x').single.time, 125.0);
    });

    test('строки без текста выбрасываются — это разделители куплетов', () {
      final lines = parseLrc('[00:01.00]a\n[00:02.00]\n[00:03.00]   \n');
      expect(lines.map((l) => l.text), ['a']);
    });

    test('строки без тайм-кода игнорируются', () {
      expect(parseLrc('[ar:Band]\nplain row\n[00:01.00]a').length, 1);
    });

    test('дробная часть необязательна', () {
      expect(parseLrc('[00:07]a').single.time, 7.0);
    });
  });

  test('stripLrc убирает тайм-коды', () {
    expect(stripLrc('[00:01.00]a\n[00:02.50]b'), 'a\nb');
  });

  test('looksLikeLrc отличает синхронный текст от простого', () {
    expect(looksLikeLrc('[00:01.00]a'), isTrue);
    expect(looksLikeLrc('just a line'), isFalse);
  });

  group('activeLineAt', () {
    final lines = parseLrc('[00:10.00]a\n[00:20.00]b\n[00:30.00]c');

    test('до первой строки — вступление', () {
      expect(activeLineAt(lines, 0), -1);
      expect(activeLineAt(lines, 9.5), -1);
    });

    test('строка загорается на четверть секунды раньше своего времени', () {
      expect(activeLineAt(lines, 9.8), 0);
      expect(activeLineAt(lines, 19.9), 1);
    });

    test('после последней остаётся последняя', () {
      expect(activeLineAt(lines, 300), 2);
    });

    test('пустой текст — подсвечивать нечего', () {
      expect(activeLineAt(const [], 10), -1);
    });
  });

  group('lrcUnits', () {
    test('по словам: смещения по границам слов, время делится по длине', () {
      final u = lrcUnits('ab cd', byLetter: false, from: 0, to: 10);
      expect(u.offsets, [0, 3, 5]);
      // Слова равной длины — вторая половина интервала достаётся второму.
      expect(u.starts, [0.0, 5.0]);
    });

    test('время делится ПРОПОРЦИОНАЛЬНО длине, а не поровну', () {
      final u = lrcUnits('a bbb', byLetter: false, from: 0, to: 8);
      expect(u.starts, [0.0, 2.0]);
    });

    test('по буквам: единица — символ, пробелы не в счёт', () {
      final u = lrcUnits('ab c', byLetter: true, from: 0, to: 3);
      expect(u.offsets, [0, 1, 3, 4]);
      expect(u.starts, [0.0, 1.0, 2.0]);
    });

    test('несколько пробелов подряд не создают пустых единиц', () {
      final u = lrcUnits('a   b', byLetter: false, from: 0, to: 2);
      expect(u.starts.length, 2);
    });
  });

  group('normalizeForSearch', () {
    test('срезает (feat. …)', () {
      expect(normalizeForSearch('Song (feat. Someone)'), 'Song');
    });

    test('срезает мусор с видеоплощадок', () {
      expect(normalizeForSearch('Song (Official Video)'), 'Song');
      expect(normalizeForSearch('Song prod. by Someone'), 'Song');
    });

    test('чистое название не трогает', () {
      expect(normalizeForSearch('Song'), 'Song');
    });
  });

  test('primaryArtist берёт первого из строки', () {
    expect(primaryArtist('A, B & C'), 'A');
    expect(primaryArtist('A feat. B'), 'A');
    expect(primaryArtist('Solo'), 'Solo');
  });

  group('scoreHit', () {
    test('точное совпадение названия и артиста — максимум', () {
      expect(
        scoreHit(
          hitTitle: 'Song',
          hitArtist: 'Band',
          queryTitle: 'Song',
          queryArtist: 'Band',
        ),
        100,
      );
    });

    test('чужая песня не дотягивает до порога выдачи', () {
      expect(
        scoreHit(
          hitTitle: 'Totally Other',
          hitArtist: 'Someone Else',
          queryTitle: 'Song',
          queryArtist: 'Band',
        ),
        lessThan(kMinSearchScore),
      );
    });

    test('название с мусором всё ещё узнаётся', () {
      expect(
        scoreHit(
          hitTitle: 'Song',
          hitArtist: 'Band',
          queryTitle: 'Song (Official Video)',
          queryArtist: 'Band',
        ),
        greaterThanOrEqualTo(kMinSearchScore),
      );
    });
  });

  group('LyricsCache', () {
    test('найденное отдаётся из памяти', () async {
      final cache = LyricsCache();
      await cache.write(
        'Band',
        'Song',
        const LyricsResult(found: true, plain: 'x'),
      );
      expect((await cache.read('Band', 'Song'))?.plain, 'x');
    });

    test('регистр в ключе не важен', () async {
      final cache = LyricsCache();
      await cache.write(
        'Band',
        'Song',
        const LyricsResult(found: true, plain: 'x'),
      );
      expect(await cache.read('band', 'song'), isNotNull);
    });

    test('ненайденное тоже помнится — но недолго', () async {
      final cache = LyricsCache();
      await cache.write('Band', 'Song', const LyricsResult.notFound());
      expect((await cache.read('Band', 'Song'))?.found, isFalse);
    });

    test('имя файла детерминировано и одинаково для разного регистра', () {
      expect(
        LyricsCache.fileNameOf('Band', 'Song'),
        LyricsCache.fileNameOf('BAND', 'song'),
      );
      expect(
        LyricsCache.fileNameOf('Band', 'Song'),
        isNot(LyricsCache.fileNameOf('Band', 'Other')),
      );
    });
  });

  group('LyricsController', () {
    test('синхронный ответ разбирается в строки', () async {
      final c = _container(
        answer: () async =>
            const LyricsResult(found: true, synced: '[00:01.00]line one'),
      );
      await c.read(lyricsProvider.notifier).ensureFor(_track);
      final state = c.read(lyricsProvider);
      expect(state.status, LyricsStatus.ready);
      expect(state.synced, isTrue);
      expect(state.lines.single.text, 'line one');
      // Простой текст собирается из синхронного, если своего не прислали.
      expect(state.plain, 'line one');
    });

    test('несинхронный ответ остаётся простым текстом', () async {
      final c = _container(
        answer: () async => const LyricsResult(found: true, plain: 'line one'),
      );
      await c.read(lyricsProvider.notifier).ensureFor(_track);
      expect(c.read(lyricsProvider).lines, isEmpty);
      expect(c.read(lyricsProvider).synced, isFalse);
    });

    test('не нашли — статус «пусто», а не вечная загрузка', () async {
      final c = _container(answer: () async => const LyricsResult.notFound());
      await c.read(lyricsProvider.notifier).ensureFor(_track);
      expect(c.read(lyricsProvider).status, LyricsStatus.empty);
    });

    test('за тем же треком второй раз в сеть не идём', () async {
      var calls = 0;
      final c = _container(
        answer: () async => const LyricsResult(found: true, plain: 'x'),
        onFetch: (_, _) => calls++,
      );
      await c.read(lyricsProvider.notifier).ensureFor(_track);
      await c.read(lyricsProvider.notifier).ensureFor(_track);
      expect(calls, 1);
    });

    test('ответ для уже сменённого трека отбрасывается', () async {
      // Первый запрос отвечает медленно и не тем: к его приходу играет уже
      // другая песня, и текст прошлой не должен встать поверх неё.
      var first = true;
      final c = _container(
        answer: () async {
          if (first) {
            first = false;
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return const LyricsResult(found: true, plain: 'stale');
          }
          return const LyricsResult(found: true, plain: 'fresh');
        },
      );
      final ctrl = c.read(lyricsProvider.notifier);
      final stale = ctrl.ensureFor(_track);
      await ctrl.ensureFor(
        const Track(
          id: 'sc_2',
          name: 'Other',
          artist: 'Band',
          duration: Duration(seconds: 60),
          source: MusicSource.soundcloud,
        ),
      );
      await stale;
      expect(c.read(lyricsProvider).plain, 'fresh');
      expect(c.read(lyricsProvider).trackId, 'sc_2');
    });

    test('трека нет — состояние сбрасывается', () async {
      final c = _container(
        answer: () async => const LyricsResult(found: true, plain: 'x'),
      );
      await c.read(lyricsProvider.notifier).ensureFor(_track);
      await c.read(lyricsProvider.notifier).ensureFor(null);
      expect(c.read(lyricsProvider).status, LyricsStatus.idle);
      expect(c.read(lyricsProvider).plain, isEmpty);
    });
  });

  group('LyricsStyleController', () {
    test('умолчания — как на ПК: поверх обложки, по словам, без эффекта', () {
      final c = _container(answer: () async => const LyricsResult.notFound());
      final style = c.read(lyricsStyleProvider);
      expect(style.mode, LyricsMode.overlay);
      expect(style.fill, LyricsFill.word);
      expect(style.fx, LyricsFx.none);
    });

    test('выбор сохраняется и читается обратно', () {
      final store = JsonStore.memory();
      final first = _container(
        answer: () async => const LyricsResult.notFound(),
        store: store,
      );
      first.read(lyricsStyleProvider.notifier).setMode(LyricsMode.replace);
      first.read(lyricsStyleProvider.notifier).setFill(LyricsFill.wipe);
      first.read(lyricsStyleProvider.notifier).setFx(LyricsFx.glow);

      final second = _container(
        answer: () async => const LyricsResult.notFound(),
        store: store,
      );
      final style = second.read(lyricsStyleProvider);
      expect(style.mode, LyricsMode.replace);
      expect(style.fill, LyricsFill.wipe);
      expect(style.fx, LyricsFx.glow);
    });

    test('незнакомое значение в файле заменяется умолчанием', () {
      final store = JsonStore.memory({
        'lyricsStyle': {'mode': 'nonsense', 'fill': 'word', 'fx': 'none'},
      });
      final c = _container(
        answer: () async => const LyricsResult.notFound(),
        store: store,
      );
      expect(c.read(lyricsStyleProvider).mode, LyricsMode.overlay);
    });
  });

  group('LyricsLayout', () {
    test('поверх обложки — по центру, вместо обложки — по левому краю', () {
      expect(LyricsLayout.overlay.align, TextAlign.center);
      expect(LyricsLayout.replace.align, TextAlign.left);
    });

    test('на всю ширину экрана кегль крупнее, чем в квадрате обложки', () {
      expect(
        LyricsLayout.replace.fontSize,
        greaterThan(LyricsLayout.overlay.fontSize),
      );
      expect(
        LyricsLayout.replace.activeFontSize,
        greaterThan(LyricsLayout.replace.fontSize),
      );
    });
  });

  group('LyricsView', () {
    /// Строки рисует художник, а не `Text`, — искать их можно только в дереве
    /// семантики (её `_Line` навешивает как раз ради этого).
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required String synced,
      required Duration position,
    }) async {
      final c = ProviderContainer(
        overrides: [
          jsonStoreProvider.overrideWithValue(JsonStore.memory()),
          lyricsFetcherProvider.overrideWithValue(
            ({required artist, required title, durationSec}) async =>
                LyricsResult(found: true, synced: synced),
          ),
          playheadProvider.overrideWith(
            (ref) => Stream.value((
              position: position,
              total: const Duration(minutes: 3),
            )),
          ),
          playingProvider.overrideWith((ref) => Stream.value(false)),
        ],
      );
      addTearDown(c.dispose);
      await c.read(lyricsProvider.notifier).ensureFor(_track);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildBloomTheme(BloomThemes.dark),
            home: const Scaffold(body: LyricsView()),
          ),
        ),
      );
      await tester.pump();
      return c;
    }

    testWidgets('строки видны в дереве семантики', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        synced: '[00:10.00]line one\n[00:20.00]line two',
        position: const Duration(seconds: 12),
      );
      expect(find.bySemanticsLabel('line one'), findsOneWidget);
      expect(find.bySemanticsLabel('line two'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('активна строка, чьё время уже наступило', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        synced: '[00:10.00]line one\n[00:20.00]line two\n[00:30.00]line three',
        position: const Duration(seconds: 21),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('line two')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('line one')),
        isSemantics(isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('до первой строки не активна ни одна', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        synced: '[00:10.00]line one\n[00:20.00]line two',
        position: Duration.zero,
      );
      for (final label in ['line one', 'line two']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isSelected: false),
        );
      }
      handle.dispose();
    });
  });
}
