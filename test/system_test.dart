/// «Система» и «Аудио»: журнал работы, перенос плейлистов, сравнение версий и
/// сброс настроек.
///
/// Ни сеть, ни файловую систему не трогаем: журнал без `open()` живёт в памяти
/// (файла у него нет), проверка обновлений ходит через подменённый
/// [releaseFetchProvider], а хранилище — `JsonStore.memory`.
library;

import 'dart:convert';

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/log/bloom_log.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/player/play_button_store.dart';
import 'package:bloom/features/player/player_bg_store.dart';
import 'package:bloom/features/settings/about_store.dart';
import 'package:bloom/features/settings/data_transfer.dart';
import 'package:bloom/features/settings/reset.dart';
import 'package:bloom/features/settings/update_notes_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(
  JsonStore store, {
  ReleaseFetch? fetch,
  NotesFetch? notes,
}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      if (fetch != null) releaseFetchProvider.overrideWithValue(fetch),
      if (notes != null) notesFetchProvider.overrideWithValue(notes),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Манифест заметок из двух версий — в том же виде, в каком он лежит в
/// `update-notes/update-notes.json`.
const String _manifest = '''
{
  "1.0.0": {
    "title": { "ru": "Первый релиз", "en": "First release" },
    "date": "2026-08-20",
    "pages": [
      {
        "title": { "ru": "Начало", "en": "Start" },
        "body": { "ru": "- раз\\n- два", "en": "- one\\n- two" },
        "image": "start.png"
      }
    ]
  },
  "1.0.1": {
    "title": "Починки",
    "date": "2026-09-01",
    "pages": [{ "body": { "ru": "- поправили" } }]
  }
}
''';

Track _track(String id, {String name = 'Song'}) => Track(
  id: id,
  name: name,
  artist: 'Artist',
  duration: const Duration(seconds: 200),
  source: MusicSource.soundcloud,
);

void main() {
  group('журнал работы', () {
    setUp(() => BloomLog.instance.clear());

    test('строка складывается и разбирается обратно', () {
      final entry = LogEntry(
        DateTime(2026, 8, 20, 14, 3, 11),
        LogLevel.error,
        'player',
        'нет провайдера',
      );
      final parsed = LogEntry.parse(entry.format());
      expect(parsed, isNotNull);
      expect(parsed!.level, LogLevel.error);
      expect(parsed.tag, 'player');
      expect(parsed.message, 'нет провайдера');
      expect(parsed.at, entry.at);
    });

    test('чужая строка пропускается, а не роняет разбор', () {
      expect(LogEntry.parse(''), isNull);
      expect(LogEntry.parse('какой-то мусор из другого файла'), isNull);
    });

    test('многострочное складывается в одну строку', () {
      logError('dart', 'ошибка', 'кадр 1\n  кадр 2\n  кадр 3');
      final line = BloomLog.instance.entries.single.format();
      expect(line.contains('\n'), isFalse);
      expect(line, contains('кадр 3'));
    });

    test('старые записи вытесняются, новые остаются', () {
      for (var i = 0; i < kLogMax + 20; i++) {
        logInfo('test', 'запись $i');
      }
      final entries = BloomLog.instance.entries;
      expect(entries.length, kLogMax);
      expect(entries.first.message, 'запись 20');
      expect(entries.last.message, 'запись ${kLogMax + 19}');
    });
  });

  group('перенос плейлистов', () {
    test('в файл уезжают только треки плейлистов', () async {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      lib.addToLibrary([_track('sc_1'), _track('sc_2')]);
      lib.createPlaylist('Вечер', tracks: [_track('sc_1')]);

      final bundle = await buildExportAllBundle(c.read(libraryProvider));
      expect(bundle, contains('"sc_1"'));
      // Трек лежит в библиотеке, но ни в одном плейлисте — файл переноса про
      // плейлисты, а не про всю библиотеку.
      expect(bundle, isNot(contains('"sc_2"')));
    });

    test('выгрузка одного плейлиста берёт только его', () async {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      final mine = lib.createPlaylist('Вечер', tracks: [_track('sc_1')]);
      lib.createPlaylist('Утро', tracks: [_track('sc_2')]);

      final bundle = await buildExportBundle(mine, c.read(libraryProvider));
      expect(bundle, contains('Вечер'));
      expect(bundle, contains('"sc_1"'));
      expect(bundle, isNot(contains('Утро')));
      expect(bundle, isNot(contains('"sc_2"')));
    });

    test('файл одного плейлиста читается обычным импортом', () async {
      final source = _container(JsonStore.memory());
      final mine = source
          .read(libraryProvider.notifier)
          .createPlaylist('Вечер', tracks: [_track('sc_1'), _track('sc_2')]);
      final file = await buildExportBundle(mine, source.read(libraryProvider));

      final c = _container(JsonStore.memory());
      final result = await importPlaylistBundle(
        file,
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );

      expect(result?.playlists, 1);
      expect(c.read(libraryProvider).playlists.single.trackIds, [
        'sc_1',
        'sc_2',
      ]);
    });

    test(
      'имя файла переживает символы, которых не терпит файловая система',
      () {
        expect(
          playlistFileName('AC/DC: лучшее?'),
          'AC_DC_ лучшее_.bloomplaylist',
        );
        // Безымянный плейлист не должен дать файл без имени.
        expect(playlistFileName('   '), 'bloom-playlist.bloomplaylist');
      },
    );

    test('импорт заводит плейлист заново и возвращает треки', () async {
      final source = _container(JsonStore.memory());
      final lib = source.read(libraryProvider.notifier);
      lib.createPlaylist('Вечер', tracks: [_track('sc_1'), _track('sc_2')]);
      final file = await buildExportAllBundle(source.read(libraryProvider));

      // id плейлиста — это время его создания, и «другой телефон» здесь тот же
      // самый: без паузы обе библиотеки заводят плейлист в одну миллисекунду и
      // получают ОДИН id — проверка ниже тогда падает на ровном месте.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final c = _container(JsonStore.memory());
      final result = await importPlaylistBundle(
        file,
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );

      expect(result?.playlists, 1);
      expect(result?.tracks, 2);
      final pl = c.read(libraryProvider).playlists.single;
      expect(pl.name, 'Вечер');
      expect(pl.trackIds, ['sc_1', 'sc_2']);
      // id новый: файл мог приехать с другого телефона, где такой уже занят.
      expect(pl.id, isNot(source.read(libraryProvider).playlists.single.id));
    });

    test('id плейлиста из файла не занимает место существующего', () async {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      final mine = lib.createPlaylist('Мой', tracks: [_track('sc_9')]);
      final file = await buildExportAllBundle(c.read(libraryProvider));

      await importPlaylistBundle(
        file,
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );
      final playlists = c.read(libraryProvider).playlists;
      expect(playlists.length, 2);
      expect(playlists.first.id, mine.id);
      expect(playlists.last.id, isNot(mine.id));
    });

    test('десктопные имена полей (trs) тоже читаются', () async {
      final c = _container(JsonStore.memory());
      c.read(libraryProvider.notifier).addToLibrary([_track('sc_1')]);
      final result = await importPlaylistBundle(
        '{"version":1,"playlists":[{"id":"p1","name":"С ПК","trs":["sc_1"]}]}',
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );
      expect(result?.playlists, 1);
      expect(c.read(libraryProvider).playlists.single.trackIds, ['sc_1']);
    });

    test('десктопный снимок трека едет целиком', () async {
      final c = _container(JsonStore.memory());
      // Так трек выглядит в файле с ПК: длительность строкой, транскодинги в
      // `scMedia`, глобальные прослушивания в `scPlaybackCount`, а `playCount`
      // занят СВОИМ счётчиком — его брать нельзя.
      final result = await importPlaylistBundle(
        '''
        {"version":1,
         "playlists":[{"id":"p1","name":"С ПК","trs":["sc_5","ym_7","ytm_v"]}],
         "tracks":[
           {"id":"sc_5","name":"Song","artist":"A","dur":"3:45","playCount":12,
            "scPlaybackCount":900,"scMedia":{"transcodings":[{"url":"u"}]}},
           {"id":"ym_7","name":"Пес","artist":"Б","dur":"1:02:03",
            "ymAvailable":false},
           {"id":"ytm_v","name":"Clip","artist":"C","dur":"мусор"}
         ]}
        ''',
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );

      expect(result?.tracks, 3);
      final tracks = c.read(libraryProvider).tracks;
      final sc = tracks['sc_5']!;
      expect(sc.source, MusicSource.soundcloud);
      expect(sc.duration, const Duration(minutes: 3, seconds: 45));
      expect(sc.playCount, 900);
      // Транскодинги переехали как есть — иначе трек с ПК нечем было бы играть.
      expect(sc.sourceData?['transcodings'], isNotEmpty);
      expect(
        tracks['ym_7']!.duration,
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(tracks['ym_7']!.sourceData, {'available': false});
      // YouTube Music играет по одному id, сырьё ему не нужно; нечитаемая
      // длительность — ноль, а не отказ от трека.
      expect(tracks['ytm_v']!.sourceData, isNull);
      expect(tracks['ytm_v']!.duration, Duration.zero);
    });

    test('локальный трек с ПК не импортируется — файла тут нет', () async {
      final c = _container(JsonStore.memory());
      final result = await importPlaylistBundle(
        '{"version":1,"playlists":[{"name":"С ПК","trs":["lf_abc"]}],'
        '"tracks":[{"id":"lf_abc","name":"Мой файл","artist":"","dur":"2:00"}]}',
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );
      expect(result?.playlists, 1);
      expect(result?.tracks, 0);
      expect(c.read(libraryProvider).playlists.single.trackIds, isEmpty);
    });

    test('свой снимок трека десктопным разбором не портится', () async {
      final source = _container(JsonStore.memory());
      source
          .read(libraryProvider.notifier)
          .createPlaylist('Вечер', tracks: [_track('sc_1')]);
      final file = await buildExportAllBundle(source.read(libraryProvider));

      final c = _container(JsonStore.memory());
      await importPlaylistBundle(
        file,
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );
      expect(c.read(libraryProvider).tracks['sc_1']!.name, 'Song');
    });

    test('в файле есть и десктопные поля — его откроет ПК', () async {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      lib.createPlaylist(
        'Вечер',
        tracks: [
          Track(
            id: 'sc_5',
            name: 'Song',
            artist: 'A',
            duration: const Duration(minutes: 3, seconds: 45),
            source: MusicSource.soundcloud,
            playCount: 900,
            sourceData: const {
              'transcodings': [
                {'url': 'u'},
              ],
            },
          ),
          Track(
            id: 'ytm_a_b',
            name: 'Clip',
            artist: 'C',
            duration: const Duration(hours: 1, minutes: 2, seconds: 3),
            source: MusicSource.ytmusic,
          ),
        ],
      );

      final bundle =
          jsonDecode(await buildExportAllBundle(c.read(libraryProvider)))
              as Map<String, dynamic>;
      // Состав плейлиста ПК берёт из `trs` — своего `trackIds` он не знает.
      expect((bundle['playlists'] as List).single['trs'], ['sc_5', 'ytm_a_b']);
      final tracks = {
        for (final raw in bundle['tracks'] as List)
          (raw as Map)['id']: raw.cast<String, dynamic>(),
      };
      final sc = tracks['sc_5']!;
      // Резолвер стрима на ПК выбирается по флагу, а не по префиксу id.
      expect(sc['_sc'], isTrue);
      expect(sc['scId'], 5);
      expect(sc['dur'], '3:45');
      expect(sc['scPlaybackCount'], 900);
      expect(sc['scMedia'], sc['sourceData']);
      final ytm = tracks['ytm_a_b']!;
      expect(ytm['_ytm'], isTrue);
      // Подчёркивание внутри videoId не должно разрезать id.
      expect(ytm['ytmVideoId'], 'a_b');
      expect(ytm['dur'], '1:02:03');
    });

    test('обложка-ссылка переживает круг, картинка не роняет импорт', () async {
      final c = _container(JsonStore.memory());
      c
          .read(libraryProvider.notifier)
          .createPlaylist(
            'Вечер',
            tracks: [_track('sc_1')],
            cover: 'https://cdn/pl.jpg',
          );
      final file = await buildExportAllBundle(c.read(libraryProvider));
      expect(file, contains('https://cdn/pl.jpg'));

      // Обложка с ПК приезжает картинкой внутри файла. Каталога `covers/` в
      // тестах нет, так что записать её некуда — импорт от этого не должен ни
      // упасть, ни потерять плейлист.
      final other = _container(JsonStore.memory());
      final result = await importPlaylistBundle(
        '{"version":1,"playlists":['
        '{"name":"Ссылкой","trs":[],"cover":"https://cdn/a.jpg"},'
        '{"name":"Картинкой","trs":[],"cover":"data:image/png;base64,iVBORw0="}'
        ']}',
        other.read(libraryProvider),
        other.read(libraryProvider.notifier),
      );

      expect(result?.playlists, 2);
      final playlists = other.read(libraryProvider).playlists;
      expect(playlists.first.cover, 'https://cdn/a.jpg');
      expect(playlists.last.cover, isNull);
    });

    test('битый файл — null, пустой список плейлистов — нули', () async {
      final c = _container(JsonStore.memory());
      expect(
        await importPlaylistBundle(
          'не json',
          c.read(libraryProvider),
          c.read(libraryProvider.notifier),
        ),
        isNull,
      );
      final empty = await importPlaylistBundle(
        '{"version":1,"playlists":[]}',
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );
      expect(empty?.playlists, 0);
    });

    test(
      'трека нет ни в файле, ни в библиотеке — id в плейлист не попадает',
      () async {
        final c = _container(JsonStore.memory());
        final result = await importPlaylistBundle(
          '{"version":1,"playlists":[{"name":"Пусто","trackIds":["sc_404"]}]}',
          c.read(libraryProvider),
          c.read(libraryProvider.notifier),
        );
        expect(result?.playlists, 1);
        expect(result?.tracks, 0);
        expect(c.read(libraryProvider).playlists.single.trackIds, isEmpty);
      },
    );
  });

  group('версии и обновления', () {
    test('сравнение по числовым частям', () {
      expect(compareVersions('1.2.3', '1.2.3'), 0);
      expect(compareVersions('1.3.0', '1.2.9'), 1);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.0', '1.10.0'), -1);
      expect(compareVersions('v2.0.0', '1.9.9'), 1);
      expect(compareVersions('1.2.3-beta', '1.2.3'), 0);
    });

    test('новее установленной — «доступна версия»', () async {
      final c = _container(
        JsonStore.memory(),
        fetch: (_) async =>
            '{"tag_name":"v1.4.0","html_url":"https://example/1.4.0"}',
      );
      final about = c.read(aboutProvider.notifier);
      // Версию платформа в тестах не отдаёт — подставляем сами через проверку
      // с известной установленной.
      about.state = const AboutState(version: '1.3.0');
      await about.check();
      expect(c.read(aboutProvider).phase, UpdatePhase.available);
      expect(c.read(aboutProvider).latest, '1.4.0');
      expect(c.read(aboutProvider).releaseUrl, 'https://example/1.4.0');
    });

    test('та же версия — «установлена последняя»', () async {
      final c = _container(
        JsonStore.memory(),
        fetch: (_) async => '{"tag_name":"v1.3.0"}',
      );
      final about = c.read(aboutProvider.notifier);
      about.state = const AboutState(version: '1.3.0');
      await about.check();
      expect(c.read(aboutProvider).phase, UpdatePhase.uptodate);
    });

    test('сеть отвалилась — ошибка, а не падение', () async {
      final c = _container(
        JsonStore.memory(),
        fetch: (_) async => throw Exception('нет сети'),
      );
      await c.read(aboutProvider.notifier).check();
      expect(c.read(aboutProvider).phase, UpdatePhase.error);
    });
  });

  group('заметки к версиям', () {
    test('заметка разбирается под язык, картинка достраивается', () async {
      final c = _container(JsonStore.memory(), notes: (_) async => _manifest);
      final ru = await c.read(updateNotesProvider).note('1.0.0', 'ru');
      expect(ru!.title, 'Первый релиз');
      expect(ru.date, '2026-08-20');
      expect(ru.pages.single.title, 'Начало');
      expect(ru.pages.single.body, '- раз\n- два');
      expect(
        ru.pages.single.image,
        'https://raw.githubusercontent.com/$kUpdateRepo/main/update-notes/assets/start.png',
      );

      final en = await c.read(updateNotesProvider).note('1.0.0', 'en');
      expect(en!.pages.single.body, '- one\n- two');
      // Заголовок строкой, а не парой — один на оба языка.
      final plain = await c.read(updateNotesProvider).note('1.0.1', 'en');
      expect(plain!.title, 'Починки');
      // Нужного языка нет — падаем на русский, а не на пустоту.
      expect(plain.pages.single.body, '- поправили');
    });

    test('версии из манифеста идут новыми сверху', () async {
      final c = _container(JsonStore.memory(), notes: (_) async => _manifest);
      final history = await c.read(updateNotesProvider).history('ru');
      expect([for (final h in history) h.version], ['1.0.1', '1.0.0']);
      expect(history.first.title, 'Починки');
    });

    test('чужой версии в манифесте нет — заметки тоже', () async {
      final c = _container(JsonStore.memory(), notes: (_) async => _manifest);
      expect(await c.read(updateNotesProvider).note('9.9.9', 'ru'), isNull);
    });

    test('«Что нового» молчит на первом запуске и после — тоже', () async {
      final store = JsonStore.memory();
      final c = _container(store, notes: (_) async => _manifest);
      final notes = c.read(updateNotesProvider);
      // Первый запуск: прошлой версии не записано — шторки нет, но отметка о
      // запуске появляется.
      expect(await notes.whatsNew('1.0.0', 'ru'), isNull);
      expect(notes.lastRun, '1.0.0');
      // Второй запуск той же версии — тоже тишина.
      expect(await notes.whatsNew('1.0.0', 'ru'), isNull);
    });

    test('после смены версии «Что нового» показывается один раз', () async {
      final store = JsonStore.memory();
      final c = _container(store, notes: (_) async => _manifest);
      final notes = c.read(updateNotesProvider);
      await notes.whatsNew('1.0.0', 'ru');
      final shown = await notes.whatsNew('1.0.1', 'ru');
      expect(shown, isNotNull);
      expect(shown!.version, '1.0.1');
      expect(await notes.whatsNew('1.0.1', 'ru'), isNull);
    });

    test('сеть отвалилась — берём кэш прошлой загрузки', () async {
      final store = JsonStore.memory();
      final first = _container(store, notes: (_) async => _manifest);
      await first.read(updateNotesProvider).history('ru');

      final offline = _container(
        store,
        notes: (_) async => throw Exception('нет сети'),
      );
      final history = await offline.read(updateNotesProvider).history('ru');
      expect([for (final h in history) h.version], ['1.0.1', '1.0.0']);
    });

    test('кэша нет и сети нет — ошибка, а не пустой список', () async {
      final c = _container(
        JsonStore.memory(),
        notes: (_) async => throw Exception('нет сети'),
      );
      expect(c.read(updateNotesProvider).history('ru'), throwsException);
    });
  });

  group('запуск и сброс', () {
    test('автовоспроизведение включает восстановление', () {
      final c = _container(JsonStore.memory());
      final settings = c.read(settingsProvider.notifier);
      settings.setAutoplay(true);
      expect(c.read(settingsProvider).restoreQueue, isTrue);
      expect(c.read(settingsProvider).autoplay, isTrue);
    });

    test('выключенное восстановление гасит автовоспроизведение', () {
      final c = _container(JsonStore.memory());
      final settings = c.read(settingsProvider.notifier);
      settings.setAutoplay(true);
      settings.setRestoreQueue(false);
      expect(c.read(settingsProvider).autoplay, isFalse);
      expect(c.read(settingsProvider).restoreQueue, isFalse);
    });

    test('оба флага переживают перезапуск', () {
      final store = JsonStore.memory();
      _container(store).read(settingsProvider.notifier).setAutoplay(true);
      final again = _container(store).read(settingsProvider);
      expect(again.autoplay, isTrue);
      expect(again.restoreQueue, isTrue);
    });

    test('сброс настроек чистит их ключи и не трогает библиотеку', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(settingsProvider.notifier).setAutoplay(true);
      c.read(libraryProvider.notifier).addToLibrary([_track('sc_1')]);

      store.removeAll(kSettingsKeys);

      expect(store.read('settings'), isNull);
      expect(store.read('tracks'), isNotNull);
      // Пересобранный стор читает уже пустое хранилище — ровно это и делает
      // `resetSettings` через `ref.invalidate`.
      final fresh = _container(store).read(settingsProvider);
      expect(fresh.autoplay, isFalse);
      expect(fresh.themeId, 'dark');
    });

    test('в список ключей настроек не попали данные пользователя', () {
      for (final key in [
        'tracks',
        'lib',
        'favs',
        'history',
        'playlists',
        'profile',
        'stats',
        'follows',
        'onboarded',
        'yandex',
        'lastfm',
      ]) {
        expect(kSettingsKeys, isNot(contains(key)), reason: key);
      }
    });

    test('сброс возвращает и вид плеера: кнопка, фон и обложка в нём', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(playButtonShapeProvider.notifier).set(PlayButtonShape.square);
      c.read(playerBgProvider.notifier).set(PlayerBg.cover);
      c.read(coverBgFxProvider.notifier).set(CoverBgFx.original);

      store.removeAll(kSettingsKeys);

      final fresh = _container(store);
      expect(fresh.read(playButtonShapeProvider), PlayButtonShape.circle);
      expect(fresh.read(playerBgProvider), PlayerBg.none);
      expect(fresh.read(coverBgFxProvider), CoverBgFx.blur);
    });
  });
}
