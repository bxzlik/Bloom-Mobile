/// «Система» и «Аудио»: журнал работы, перенос плейлистов, сравнение версий и
/// сброс настроек.
///
/// Ни сеть, ни файловую систему не трогаем: журнал без `open()` живёт в памяти
/// (файла у него нет), проверка обновлений ходит через подменённый
/// [releaseFetchProvider], а хранилище — `JsonStore.memory`.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/log/bloom_log.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/settings/about_store.dart';
import 'package:bloom/features/settings/data_transfer.dart';
import 'package:bloom/features/settings/reset.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(JsonStore store, {ReleaseFetch? fetch}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      if (fetch != null) releaseFetchProvider.overrideWithValue(fetch),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

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
    test('в файл уезжают только треки плейлистов', () {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      lib.addToLibrary([_track('sc_1'), _track('sc_2')]);
      lib.createPlaylist('Вечер', tracks: [_track('sc_1')]);

      final bundle = buildExportAllBundle(c.read(libraryProvider));
      expect(bundle, contains('"sc_1"'));
      // Трек лежит в библиотеке, но ни в одном плейлисте — файл переноса про
      // плейлисты, а не про всю библиотеку.
      expect(bundle, isNot(contains('"sc_2"')));
    });

    test('выгрузка одного плейлиста берёт только его', () {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      final mine = lib.createPlaylist('Вечер', tracks: [_track('sc_1')]);
      lib.createPlaylist('Утро', tracks: [_track('sc_2')]);

      final bundle = buildExportBundle(mine, c.read(libraryProvider));
      expect(bundle, contains('Вечер'));
      expect(bundle, contains('"sc_1"'));
      expect(bundle, isNot(contains('Утро')));
      expect(bundle, isNot(contains('"sc_2"')));
    });

    test('файл одного плейлиста читается обычным импортом', () {
      final source = _container(JsonStore.memory());
      final mine = source
          .read(libraryProvider.notifier)
          .createPlaylist('Вечер', tracks: [_track('sc_1'), _track('sc_2')]);
      final file = buildExportBundle(mine, source.read(libraryProvider));

      final c = _container(JsonStore.memory());
      final result = importPlaylistBundle(
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
      final file = buildExportAllBundle(source.read(libraryProvider));

      // id плейлиста — это время его создания, и «другой телефон» здесь тот же
      // самый: без паузы обе библиотеки заводят плейлист в одну миллисекунду и
      // получают ОДИН id — проверка ниже тогда падает на ровном месте.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final c = _container(JsonStore.memory());
      final result = importPlaylistBundle(
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

    test('id плейлиста из файла не занимает место существующего', () {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      final mine = lib.createPlaylist('Мой', tracks: [_track('sc_9')]);
      final file = buildExportAllBundle(c.read(libraryProvider));

      importPlaylistBundle(
        file,
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );
      final playlists = c.read(libraryProvider).playlists;
      expect(playlists.length, 2);
      expect(playlists.first.id, mine.id);
      expect(playlists.last.id, isNot(mine.id));
    });

    test('десктопные имена полей (trs) тоже читаются', () {
      final c = _container(JsonStore.memory());
      c.read(libraryProvider.notifier).addToLibrary([_track('sc_1')]);
      final result = importPlaylistBundle(
        '{"version":1,"playlists":[{"id":"p1","name":"С ПК","trs":["sc_1"]}]}',
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );
      expect(result?.playlists, 1);
      expect(c.read(libraryProvider).playlists.single.trackIds, ['sc_1']);
    });

    test('битый файл — null, пустой список плейлистов — нули', () {
      final c = _container(JsonStore.memory());
      expect(
        importPlaylistBundle(
          'не json',
          c.read(libraryProvider),
          c.read(libraryProvider.notifier),
        ),
        isNull,
      );
      final empty = importPlaylistBundle(
        '{"version":1,"playlists":[]}',
        c.read(libraryProvider),
        c.read(libraryProvider.notifier),
      );
      expect(empty?.playlists, 0);
    });

    test(
      'трека нет ни в файле, ни в библиотеке — id в плейлист не попадает',
      () {
        final c = _container(JsonStore.memory());
        final result = importPlaylistBundle(
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
  });
}
