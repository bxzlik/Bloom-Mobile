/// Статистика прослушиваний и «История» поверх журнала: склейка со старой
/// историей, скрытие строк, треки из снимков, переезд при смене площадки.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/history_store.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const int _min = 60000;

Track _track(
  String id, {
  String name = 'Song',
  MusicSource source = MusicSource.soundcloud,
}) => Track(
  id: id,
  name: name,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: source,
);

/// Контейнер с управляемыми часами: [clock] двигается руками.
class _Env {
  _Env([Map<String, dynamic>? seed]) {
    c = ProviderContainer(
      overrides: [
        jsonStoreProvider.overrideWithValue(store = JsonStore.memory(seed)),
        playLogStoreProvider.overrideWithValue(JsonStore.memory()),
        playLogClockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(clock),
        ),
      ],
    );
    addTearDown(c.dispose);
  }

  late final ProviderContainer c;
  late final JsonStore store;
  int clock = DateTime(2026, 9, 1).millisecondsSinceEpoch;

  void listen(Track track, {int after = _min}) {
    clock += after;
    c.read(playLogProvider.notifier).log(track);
  }

  PlayStats get stats => c.read(playStatsProvider);
  List<HistoryItem> get history => c.read(historyProvider);
}

void main() {
  group('журнал + старая история', () {
    test('старая история дополняет журнал, а не удваивает его', () {
      final at = DateTime(2026, 8, 25).millisecondsSinceEpoch;
      // 5 прослушиваний в истории; последние два из них уже попали и в журнал
      // (их писали в оба места), а одно случилось после — только в журнале.
      final log = PlayLog(
        events: [
          PlayEvent(at - 10 * _min, 'sc_1'),
          PlayEvent(at + 200, 'sc_1'), // то же прослушивание, что `at`
          PlayEvent(at + 60 * _min, 'sc_1'),
        ],
      );
      final stats = PlayStats.build(log, [HistoryEntry('sc_1', at, count: 5)]);

      expect(stats.playCount('sc_1'), 6);
      expect(stats.lastPlayedAt('sc_1'), at + 60 * _min);
    });

    test('трек, известный только старой истории, не теряется', () {
      final stats = PlayStats.build(const PlayLog(), const [
        HistoryEntry('sc_old', 1000, count: 40),
      ]);
      expect(stats.playCount('sc_old'), 40);
      expect(stats.allPlayed().single.plays, 40);
      expect(stats.historyRows().single.id, 'sc_old');
    });

    test('топ за окно не берёт то, что слушали раньше окна', () {
      final now = DateTime(2026, 9, 1);
      final day = 24 * 60 * _min;
      final base = now.millisecondsSinceEpoch;
      final stats = PlayStats.build(
        PlayLog(
          events: [
            for (var i = 0; i < 5; i++) PlayEvent(base - 200 * day + i, 'sc_a'),
            PlayEvent(base - 2 * day, 'sc_b'),
            PlayEvent(base - day, 'sc_b'),
          ],
        ),
        const [],
      );

      expect(stats.topPlayed(now: now).map((t) => t.id), ['sc_a', 'sc_b']);
      expect(stats.topPlayed(sinceDays: 90, now: now).map((t) => t.id), [
        'sc_b',
      ]);
    });
  });

  group('«История»', () {
    test('лимита в 200 больше нет', () {
      final env = _Env();
      for (var i = 0; i < 250; i++) {
        env.listen(_track('sc_$i'));
      }
      expect(env.history.length, 250);
      expect(env.history.first.track.id, 'sc_249'); // свежее сверху
    });

    test('прослушивание не кладёт трек в библиотеку, но строка есть', () {
      final env = _Env();
      env.listen(_track('sc_1', name: 'A'));

      expect(env.c.read(libraryProvider).allTracks, isEmpty);
      // Трек собран из снимка журнала — его есть чем показать и заиграть.
      final track = env.history.single.track;
      expect(track.name, 'A');
      expect(track.source, MusicSource.soundcloud);
    });

    test('спрятанная строка возвращается, если трек снова послушали', () {
      final env = _Env();
      env.listen(_track('sc_1'));
      env.listen(_track('sc_2'));

      env.c.read(historyHideProvider.notifier).hide(['sc_1']);
      expect(env.history.map((h) => h.row.id), ['sc_2']);
      // Статистику скрытие не трогает.
      expect(env.stats.playCount('sc_1'), 1);

      env.listen(_track('sc_1'));
      expect(env.history.map((h) => h.row.id), ['sc_1', 'sc_2']);
      // В строке — только видимая часть: одно прослушивание после скрытия.
      expect(env.history.first.row.count, 1);
      expect(env.stats.playCount('sc_1'), 2);
    });

    test('очистка списка прячет всё, но статистика остаётся', () {
      final env = _Env();
      env.listen(_track('sc_1'));
      env.listen(_track('sc_1'));

      env.clock += _min;
      env.c.read(historyHideProvider.notifier).clear();

      expect(env.history, isEmpty);
      expect(env.stats.playCount('sc_1'), 2);
    });

    test('отметки скрытия переживают перезапуск', () {
      final env = _Env();
      env.listen(_track('sc_1'));
      env.c.read(historyHideProvider.notifier).hide(['sc_1']);

      final again = ProviderContainer(
        overrides: [jsonStoreProvider.overrideWithValue(env.store)],
      );
      addTearDown(again.dispose);
      expect(again.read(historyHideProvider).byId.containsKey('sc_1'), isTrue);
    });

    test('«Отменить» возвращает отметки как были', () {
      final env = _Env();
      env.listen(_track('sc_1'));
      final hide = env.c.read(historyHideProvider.notifier);
      final was = env.c.read(historyHideProvider);

      hide.hide(['sc_1']);
      expect(env.history, isEmpty);
      hide.restore(was);
      expect(env.history.single.row.id, 'sc_1');
    });

    test('своего файла без записи в библиотеке строкой не поднять', () {
      final env = _Env();
      env.listen(_track('lf_1', source: MusicSource.local));
      env.listen(_track('sc_1'));

      // Снимок у `lf_1` есть, но ни ссылки, ни пути в нём нет.
      expect(env.history.map((h) => h.row.id), ['sc_1']);
      expect(env.stats.playCount('lf_1'), 1);
    });

    test('трек из библиотеки берётся целиком, а не из снимка', () {
      final env = _Env();
      final full = Track(
        id: 'sc_1',
        name: 'Полный',
        artist: 'Artist',
        duration: const Duration(seconds: 100),
        source: MusicSource.soundcloud,
        sourceData: const {'transcodings': []},
      );
      env.c.read(libraryProvider.notifier).addToLibrary([full]);
      env.listen(full);

      expect(env.history.single.track.sourceData, isNotNull);
    });

    test('наслушанное — длина трека на число прослушиваний', () {
      final env = _Env();
      env.listen(_track('sc_1'));
      env.listen(_track('sc_1'));
      env.listen(_track('sc_2'));

      final totals = historyTotals(env.history);
      expect(totals.tracks, 2);
      expect(totals.listened, const Duration(seconds: 300));
    });
  });

  group('переход и смена площадки', () {
    test('снимки для старой истории берутся из библиотеки один раз', () {
      final env = _Env({
        'history': [
          {'id': 'sc_1', 'at': 1, 'n': 3},
          {'id': 'sc_gone', 'at': 2, 'n': 1},
        ],
      });
      env.c.read(libraryProvider.notifier).addToLibrary([
        _track('sc_1', name: 'Старый'),
      ]);

      void adopt() => adoptLegacySnapshots(
        legacy: env.c.read(legacyHistoryProvider),
        lib: env.c.read(libraryProvider),
        log: env.c.read(playLogProvider.notifier),
      );
      adopt();

      final meta = env.c.read(playLogProvider).meta;
      expect(meta['sc_1']?.name, 'Старый');
      // Трека нет нигде — снимок взять неоткуда, придумывать его нельзя.
      expect(meta.containsKey('sc_gone'), isFalse);

      // Уже лежащий снимок повторный вызов не переписывает.
      env.c.read(libraryProvider.notifier).deleteTrack('sc_1');
      adopt();
      expect(env.c.read(playLogProvider).meta['sc_1']?.name, 'Старый');
      // И строка живёт после ухода трека из хранилища.
      expect(env.history.map((h) => h.row.id), ['sc_1']);
    });

    test('смена площадки переносит прослушивания и отметки', () {
      final env = _Env({
        'history': [
          {'id': 'sc_1', 'at': 1, 'n': 4},
        ],
      });
      env.listen(_track('sc_1', name: 'Ночь'));
      env.c.read(historyHideProvider.notifier).hide(['sc_1']);

      env.c.read(playLogProvider.notifier).renameTrack('sc_1', 'ytm_1');
      env.c.read(legacyHistoryProvider.notifier).renameTrack('sc_1', 'ytm_1');
      env.c.read(historyHideProvider.notifier).renameTrack('sc_1', 'ytm_1');

      expect(env.stats.playCount('sc_1'), 0);
      expect(env.stats.playCount('ytm_1'), 5);
      expect(env.stats.meta['ytm_1']?.name, 'Ночь');
      expect(env.c.read(historyHideProvider).byId.keys, ['ytm_1']);
    });
  });
}
