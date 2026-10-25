/// Подбор сидов волны: на чём именно она будет построена.
///
/// Проверяем списком, а не на слух: ошибка здесь тихая — волна играет, просто
/// не то и всегда одно и то же.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:bloom/features/wave/wave_seeds.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(
  String id, {
  MusicSource source = MusicSource.soundcloud,
  String artist = 'Artist',
}) => Track(
  id: id,
  name: id,
  artist: artist,
  duration: const Duration(seconds: 100),
  source: source,
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
  // Прослушивания — событиями журнала: последнее в указанный день.
  final events = [
    for (final e in plays.entries)
      for (var i = e.value - 1; i >= 0; i--)
        PlayEvent(
          (playedDaysAgo.containsKey(e.key)
                  ? _daysAgo(playedDaysAgo[e.key]!)
                  : now) -
              i,
          e.key,
        ),
  ]..sort((a, b) => a.ts.compareTo(b.ts));
  final recent = [for (final e in plays.entries) e.key];
  return WaveLibrary(
    lib: LibraryState(
      tracks: {for (final t in tracks) t.id: t},
      // Свежие сверху: и место в списке, и время добавления.
      libIds: [for (final t in tracks) t.id],
      inLib: {for (var i = 0; i < tracks.length; i++) tracks[i].id: now - i},
      favIds: favs.toList(),
      favs: {for (final id in favs) id: now - favs.toList().indexOf(id)},
    ),
    disliked: disliked,
    stats: PlayStats.build(PlayLog(events: events)),
    recent: recent,
    extras: extras,
  );
}

void main() {
  group('scIdOf', () {
    test('числовой id SoundCloud, у остальных площадок — ничего', () {
      expect(scIdOf(_track('sc:123')), '123');
      expect(scIdOf(_track('ym:5', source: MusicSource.yandex)), isNull);
      expect(scIdOf(_track('ytm:abc', source: MusicSource.ytmusic)), isNull);
      expect(scIdOf(null), isNull);
    });
  });

  group('pickQueueSeeds', () {
    test('короткая очередь идёт в сиды целиком', () {
      final tracks = [for (var i = 0; i < 5; i++) _track('sc:$i')];
      final view = _library(tracks);
      expect(pickQueueSeeds([for (final t in tracks) t.id], view), [
        for (final t in tracks) t.id,
      ]);
    });

    test('длинная режется до десяти и берётся равномерно по позициям', () {
      final tracks = [for (var i = 0; i < 20; i++) _track('sc:$i')];
      final view = _library(tracks);
      final seeds = pickQueueSeeds([for (final t in tracks) t.id], view);

      expect(seeds.length, 10);
      // Равномерно — значит с шагом два, а не первые десять подряд.
      expect(seeds, [for (var i = 0; i < 20; i += 2) 'sc:$i']);
    });

    test('дизлайкнутые и чужие площадки отсеиваются ДО расчёта позиций', () {
      final tracks = [
        _track('sc:1'),
        _track('ym:2', source: MusicSource.yandex),
        _track('sc:3'),
        _track('sc:4'),
      ];
      final view = _library(tracks, disliked: {'sc:4'});
      expect(pickQueueSeeds([for (final t in tracks) t.id], view), [
        'sc:1',
        'sc:3',
      ]);
    });

    test('дубли в очереди сидом становятся один раз', () {
      final view = _library([_track('sc:1'), _track('sc:2')]);
      expect(pickQueueSeeds(['sc:1', 'sc:2', 'sc:1'], view), ['sc:1', 'sc:2']);
    });

    test('сидов не набралось — пусто, а не список ни о чём', () {
      final view = _library([_track('ym:1', source: MusicSource.yandex)]);
      expect(pickQueueSeeds(['ym:1'], view), isEmpty);
      expect(pickQueueSeeds(const [], view), isEmpty);
    });

    test('трек из поиска годится в сиды, хотя в библиотеке его нет', () {
      final outside = _track('sc:99');
      final view = _library(const [], extras: [outside]);
      expect(pickQueueSeeds(['sc:99'], view), ['sc:99']);
    });
  });

  group('pickPersonalSeeds', () {
    test('берёт слушаемое и лайкнутое, не больше пяти сидов', () {
      final tracks = [for (var i = 0; i < 12; i++) _track('sc:$i')];
      final view = _library(
        tracks,
        plays: {'sc:0': 10, 'sc:1': 8, 'sc:2': 5},
        favs: {'sc:7', 'sc:8'},
      );
      final seeds = pickPersonalSeeds(view, 0);

      expect(seeds.length, lessThanOrEqualTo(5));
      expect(seeds, containsAll(['sc:0', 'sc:1']));
      expect(seeds, containsAll(['sc:7', 'sc:8']));
    });

    test('третий сид — следующий из топа, а не случайный «по жанру»', () {
      final tracks = [for (var i = 0; i < 6; i++) _track('sc:$i')];
      final view = _library(
        tracks,
        plays: {'sc:0': 10, 'sc:1': 8, 'sc:2': 6, 'sc:3': 4},
      );
      // Лайков нет: два из топа плюс следующий за ними — и больше ничего.
      expect(pickPersonalSeeds(view, 0), ['sc:0', 'sc:1', 'sc:2']);
    });

    test('следующий из топа уже взят — третьим идёт следующий лайк', () {
      final tracks = [for (var i = 0; i < 6; i++) _track('sc:$i')];
      final view = _library(
        tracks,
        // В топе всего два трека: «следующий» по кругу — снова первый.
        plays: {'sc:0': 10, 'sc:1': 8},
        favs: {'sc:3', 'sc:4', 'sc:5'},
      );
      final seeds = pickPersonalSeeds(view, 0);
      expect(seeds, containsAll(['sc:0', 'sc:1', 'sc:3', 'sc:4', 'sc:5']));
      expect(seeds.length, 5);
    });

    test('ротация сдвигает выбор — вторая волна начинается не с того же', () {
      final tracks = [for (var i = 0; i < 8; i++) _track('sc:$i')];
      final view = _library(
        tracks,
        plays: {'sc:0': 10, 'sc:1': 8, 'sc:2': 6, 'sc:3': 4},
      );
      expect(pickPersonalSeeds(view, 0), isNot(pickPersonalSeeds(view, 1)));
    });

    test('пустая библиотека — сидов нет (интерфейс скажет «послушай ещё»)', () {
      expect(pickPersonalSeeds(_library(const []), 0), isEmpty);
    });

    test('слушать ещё нечего — берём свежее из библиотеки', () {
      final tracks = [for (var i = 0; i < 4; i++) _track('sc:$i')];
      final seeds = pickPersonalSeeds(_library(tracks), 0);
      // Порядок «Всех треков» — свежие сверху, они и становятся сидами.
      expect(seeds, ['sc:0', 'sc:1', 'sc:2']);
    });

    test('дизлайкнутое в сиды не идёт', () {
      final tracks = [_track('sc:1'), _track('sc:2')];
      final view = _library(
        tracks,
        plays: {'sc:1': 10, 'sc:2': 5},
        disliked: {'sc:1'},
      );
      expect(pickPersonalSeeds(view, 0), isNot(contains('sc:1')));
    });
  });

  group('pickFamiliarPool', () {
    test('исключённое и слушанное на днях в подмешивание не идут', () {
      final tracks = [for (var i = 0; i < 6; i++) _track('sc:$i')];
      final view = _library(
        tracks,
        plays: {'sc:2': 1},
        playedDaysAgo: {'sc:2': 1},
      );
      final pool = pickFamiliarPool(view, {'sc:0'});
      final ids = [for (final t in pool) t.id];

      expect(ids, isNot(contains('sc:0')));
      expect(ids, isNot(contains('sc:2')));
      expect(ids.length, 4);
    });

    test('слушанное давно вернуть можно', () {
      final tracks = [_track('sc:1')];
      final view = _library(
        tracks,
        plays: {'sc:1': 1},
        playedDaysAgo: {'sc:1': 30},
      );
      expect(pickFamiliarPool(view, const {}).single.id, 'sc:1');
    });
  });

  group('pickDisplaySeeds', () {
    test('витрина не повторяет треки и уважает лимит', () {
      final tracks = [for (var i = 0; i < 30; i++) _track('sc:$i')];
      final view = _library(
        tracks,
        plays: {'sc:0': 9, 'sc:1': 7},
        favs: {'sc:5'},
      );
      final faces = pickDisplaySeeds(view, 0, limit: 8);

      expect(faces.length, 8);
      expect(faces.toSet().length, 8);
      // Сверху — то, на чём волна и построится: слушаемое, потом лайки.
      expect(faces.take(3), containsAll(['sc:0', 'sc:1']));
    });
  });
}
