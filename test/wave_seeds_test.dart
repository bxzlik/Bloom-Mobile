/// Подбор сидов волны: на чём именно она будет построена.
///
/// Проверяем списком, а не на слух: ошибка здесь тихая — волна играет, просто
/// не то и всегда одно и то же.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/wave/wave_seeds.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(
  String id, {
  MusicSource source = MusicSource.soundcloud,
  String artist = 'Artist',
  List<String> genres = const [],
}) => Track(
  id: id,
  name: id,
  artist: artist,
  duration: const Duration(seconds: 100),
  source: source,
  genres: genres,
);

int _daysAgo(int days) =>
    DateTime.now().millisecondsSinceEpoch - days * 24 * 3600 * 1000;

/// Библиотека из перечисленных треков. [plays] — счётчик прослушиваний,
/// [favs] — что лайкнуто, [playedDaysAgo] — когда слушали.
WaveLibrary _library(
  List<Track> tracks, {
  Map<String, int> plays = const {},
  Set<String> favs = const {},
  Map<String, int> playedDaysAgo = const {},
  Set<String> disliked = const {},
  List<Track> extras = const [],
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return WaveLibrary(
    lib: LibraryState(
      tracks: {for (final t in tracks) t.id: t},
      // Свежие сверху: порядок раздела держится временем добавления.
      inLib: {for (var i = 0; i < tracks.length; i++) tracks[i].id: now - i},
      favs: {for (final id in favs) id: now - favs.toList().indexOf(id)},
      history: [
        for (final e in plays.entries)
          HistoryEntry(
            e.key,
            playedDaysAgo.containsKey(e.key)
                ? _daysAgo(playedDaysAgo[e.key]!)
                : now,
            count: e.value,
          ),
      ],
    ),
    disliked: disliked,
    extras: extras,
  );
}

void main() {
  group('scIdOf', () {
    test('числовой id SoundCloud, у остальных площадок — ничего', () {
      expect(scIdOf(_track('sc_123')), '123');
      expect(scIdOf(_track('ym_5', source: MusicSource.yandex)), isNull);
      expect(scIdOf(_track('ytm_abc', source: MusicSource.ytmusic)), isNull);
      expect(scIdOf(null), isNull);
    });
  });

  group('pickQueueSeeds', () {
    test('короткая очередь идёт в сиды целиком', () {
      final tracks = [for (var i = 0; i < 5; i++) _track('sc_$i')];
      final view = _library(tracks);
      expect(pickQueueSeeds([for (final t in tracks) t.id], view), [
        for (final t in tracks) t.id,
      ]);
    });

    test('длинная режется до десяти и берётся равномерно по позициям', () {
      final tracks = [for (var i = 0; i < 20; i++) _track('sc_$i')];
      final view = _library(tracks);
      final seeds = pickQueueSeeds([for (final t in tracks) t.id], view);

      expect(seeds.length, 10);
      // Равномерно — значит с шагом два, а не первые десять подряд.
      expect(seeds, [for (var i = 0; i < 20; i += 2) 'sc_$i']);
    });

    test('дизлайкнутые и чужие площадки отсеиваются ДО расчёта позиций', () {
      final tracks = [
        _track('sc_1'),
        _track('ym_2', source: MusicSource.yandex),
        _track('sc_3'),
        _track('sc_4'),
      ];
      final view = _library(tracks, disliked: {'sc_4'});
      expect(pickQueueSeeds([for (final t in tracks) t.id], view), [
        'sc_1',
        'sc_3',
      ]);
    });

    test('дубли в очереди сидом становятся один раз', () {
      final view = _library([_track('sc_1'), _track('sc_2')]);
      expect(pickQueueSeeds(['sc_1', 'sc_2', 'sc_1'], view), ['sc_1', 'sc_2']);
    });

    test('сидов не набралось — пусто, а не список ни о чём', () {
      final view = _library([_track('ym_1', source: MusicSource.yandex)]);
      expect(pickQueueSeeds(['ym_1'], view), isEmpty);
      expect(pickQueueSeeds(const [], view), isEmpty);
    });

    test('трек из поиска годится в сиды, хотя в библиотеке его нет', () {
      final outside = _track('sc_99');
      final view = _library(const [], extras: [outside]);
      expect(pickQueueSeeds(['sc_99'], view), ['sc_99']);
    });
  });

  group('pickPersonalSeeds', () {
    test('берёт слушаемое и лайкнутое, не больше пяти сидов', () {
      final tracks = [for (var i = 0; i < 12; i++) _track('sc_$i')];
      final view = _library(
        tracks,
        plays: {'sc_0': 10, 'sc_1': 8, 'sc_2': 5},
        favs: {'sc_7', 'sc_8'},
      );
      final seeds = pickPersonalSeeds(view, 0);

      expect(seeds.length, lessThanOrEqualTo(5));
      expect(seeds, containsAll(['sc_0', 'sc_1']));
      expect(seeds, containsAll(['sc_7', 'sc_8']));
    });

    test('ротация сдвигает выбор — вторая волна начинается не с того же', () {
      final tracks = [for (var i = 0; i < 8; i++) _track('sc_$i')];
      final view = _library(
        tracks,
        plays: {'sc_0': 10, 'sc_1': 8, 'sc_2': 6, 'sc_3': 4},
      );
      expect(pickPersonalSeeds(view, 0), isNot(pickPersonalSeeds(view, 1)));
    });

    test('пустая библиотека — сидов нет (интерфейс скажет «послушай ещё»)', () {
      expect(pickPersonalSeeds(_library(const []), 0), isEmpty);
    });

    test('слушать ещё нечего — берём свежее из библиотеки', () {
      final tracks = [for (var i = 0; i < 4; i++) _track('sc_$i')];
      final seeds = pickPersonalSeeds(_library(tracks), 0);
      // Порядок «Всех треков» — свежие сверху, они и становятся сидами.
      expect(seeds, ['sc_0', 'sc_1', 'sc_2']);
    });

    test('дизлайкнутое в сиды не идёт', () {
      final tracks = [_track('sc_1'), _track('sc_2')];
      final view = _library(
        tracks,
        plays: {'sc_1': 10, 'sc_2': 5},
        disliked: {'sc_1'},
      );
      expect(pickPersonalSeeds(view, 0), isNot(contains('sc_1')));
    });
  });

  group('pickFamiliarPool', () {
    test('исключённое и слушанное на днях в подмешивание не идут', () {
      final tracks = [for (var i = 0; i < 6; i++) _track('sc_$i')];
      final view = _library(
        tracks,
        plays: {'sc_2': 1},
        playedDaysAgo: {'sc_2': 1},
      );
      final pool = pickFamiliarPool(view, {'sc_0'});
      final ids = [for (final t in pool) t.id];

      expect(ids, isNot(contains('sc_0')));
      expect(ids, isNot(contains('sc_2')));
      expect(ids.length, 4);
    });

    test('слушанное давно вернуть можно', () {
      final tracks = [_track('sc_1')];
      final view = _library(
        tracks,
        plays: {'sc_1': 1},
        playedDaysAgo: {'sc_1': 30},
      );
      expect(pickFamiliarPool(view, const {}).single.id, 'sc_1');
    });
  });

  group('pickDisplaySeeds', () {
    test('витрина не повторяет треки и уважает лимит', () {
      final tracks = [for (var i = 0; i < 30; i++) _track('sc_$i')];
      final view = _library(
        tracks,
        plays: {'sc_0': 9, 'sc_1': 7},
        favs: {'sc_5'},
      );
      final faces = pickDisplaySeeds(view, 0, limit: 8);

      expect(faces.length, 8);
      expect(faces.toSet().length, 8);
      // Сверху — то, на чём волна и построится: слушаемое, потом лайки.
      expect(faces.take(3), containsAll(['sc_0', 'sc_1']));
    });
  });
}
