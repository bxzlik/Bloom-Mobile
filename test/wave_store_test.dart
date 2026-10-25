/// Память волны: дизлайки, пометки «уже показывали», курсоры станций и сеанс.
/// Хранилище — в памяти, файловая система не нужна.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/wave/wave_store.dart';
import 'package:bloom/features/wave/wave_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Song',
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
);

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
  test('дизлайк переживает перезапуск вместе с самим треком', () {
    final store = JsonStore.memory();
    _container(
      store,
    ).read(waveStoreProvider.notifier).toggleDislike(_track('sc:1'));

    // Новый контейнер — то же, что новый запуск приложения.
    final state = _container(store).read(waveStoreProvider);
    expect(state.isDisliked('sc:1'), isTrue);
    // Список дизлайков надо чем-то показывать: одного id мало.
    expect(state.dislikes.single.name, 'Song');
  });

  test('список дизлайков — новые сверху', () async {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);
    wave.toggleDislike(_track('sc:1'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    wave.toggleDislike(_track('sc:2'));
    expect(c.read(waveStoreProvider).dislikes.map((t) => t.id), [
      'sc:2',
      'sc:1',
    ]);
  });

  test('смена площадки трека уносит дизлайк с собой', () {
    final c = _container(JsonStore.memory());
    c.read(waveStoreProvider.notifier).toggleDislike(_track('sc:1'));
    c.read(libraryProvider.notifier).replaceTrack('sc:1', _track('ytm:a'));

    final state = c.read(waveStoreProvider);
    expect(state.isDisliked('sc:1'), isFalse);
    expect(state.isDisliked('ytm:a'), isTrue);
  });

  test('«очистить» снимает все дизлайки', () {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);
    wave
      ..toggleDislike(_track('sc:1'))
      ..toggleDislike(_track('sc:2'))
      ..clearDislikes();
    expect(c.read(waveStoreProvider).dislikes, isEmpty);
  });

  test('повторный дизлайк снимает метку', () {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);
    final track = _track('sc:1');

    expect(wave.toggleDislike(track), isTrue);
    expect(wave.toggleDislike(track), isFalse);
    expect(c.read(waveStoreProvider).isDisliked('sc:1'), isFalse);
  });

  test('показанное волной не возвращается в выдачу', () {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);

    expect(wave.shownIds(), isEmpty);
    wave.markShown(['sc:1', 'sc:2']);
    expect(wave.shownIds(), {'sc:1', 'sc:2'});
    // Срок задаётся вызывающим: за нулевой срок «показанным» не считается.
    expect(wave.shownIds(withinDays: 0), isEmpty);
  });

  test('показанное раньше двух недель забывается при запуске', () {
    final store = JsonStore.memory();
    final db = testDb(store);
    final old = BloomDb.now() - (kShownTtlDays + 1) * 24 * 3600 * 1000;
    db.exec('INSERT INTO wave_shown (track_id, at) VALUES (?, ?)', [
      'sc:1',
      old,
    ]);
    _container(store).read(waveStoreProvider);
    expect(db.value('SELECT count(*) FROM wave_shown'), 0);
  });

  test('курсор станции двигается пачками и переживает перезапуск', () {
    final store = JsonStore.memory();
    final wave = _container(store).read(waveStoreProvider.notifier);

    expect(wave.cursorOf('42'), 0);
    wave.advanceCursor('42');
    expect(wave.cursorOf('42'), kStationStep);

    // Иначе каждая новая волна начинала бы с тех же двадцати треков.
    expect(
      _container(store).read(waveStoreProvider.notifier).cursorOf('42'),
      kStationStep,
    );
  });

  test('исчерпанная станция начинается сначала', () {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);
    wave
      ..advanceCursor('42')
      ..advanceCursor('42')
      ..resetCursor('42');
    expect(wave.cursorOf('42'), 0);
  });

  test('сеанс возвращается после перезапуска — иначе волна встанет', () {
    final store = JsonStore.memory();
    _container(store)
        .read(waveStoreProvider.notifier)
        .saveSession(
          WaveSession(
            mode: WaveMode.track,
            seeds: const ['sc:1'],
            startedAt: 5,
            playedIds: ['sc:1', 'sc:2'],
            artistBonus: {'artist': 3},
          ),
        );

    final restored = _container(
      store,
    ).read(waveStoreProvider.notifier).savedSession!;
    expect(restored.mode, WaveMode.track);
    expect(restored.seeds, ['sc:1']);
    expect(restored.playedIds, ['sc:1', 'sc:2']);
    expect(restored.artistBonus['artist'], 3);
  });

  test('конец волны стирает сеанс', () {
    final store = JsonStore.memory();
    final wave = _container(store).read(waveStoreProvider.notifier);
    wave.saveSession(
      WaveSession(mode: WaveMode.personal, seeds: const [], startedAt: 0),
    );
    wave.saveSession(null);
    expect(
      _container(store).read(waveStoreProvider.notifier).savedSession,
      isNull,
    );
  });

  test('выбран Яндекс, но входа нет — волна идёт своим движком', () {
    final c = _container(JsonStore.memory());
    c.read(waveStoreProvider.notifier).setSource(WaveEngineKind.yandex);

    // Выбор сохраняется — вернётся вход, вернётся и станция.
    expect(c.read(waveStoreProvider).source, WaveEngineKind.yandex);
    // А набирается волна пока по SoundCloud, вместо того чтобы отказать.
    expect(c.read(effectiveWaveSourceProvider), WaveEngineKind.soundcloud);
  });

  test('выбранная площадка запоминается', () {
    final store = JsonStore.memory();
    expect(
      _container(store).read(waveStoreProvider).source,
      WaveEngineKind.soundcloud,
    );
    _container(
      store,
    ).read(waveStoreProvider.notifier).setSource(WaveEngineKind.yandex);
    expect(
      _container(store).read(waveStoreProvider).source,
      WaveEngineKind.yandex,
    );
  });
}
