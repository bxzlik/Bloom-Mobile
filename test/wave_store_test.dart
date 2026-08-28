/// Память волны: дизлайки, пометки «уже показывали», курсоры станций и сеанс.
/// Хранилище — в памяти, файловая система не нужна.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/wave/wave_store.dart';
import 'package:bloom/features/wave/wave_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Song',
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
);

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('дизлайк переживает перезапуск вместе с самим треком', () {
    final store = JsonStore.memory();
    _container(
      store,
    ).read(waveStoreProvider.notifier).toggleDislike(_track('sc_1'));

    // Новый контейнер — то же, что новый запуск приложения.
    final state = _container(store).read(waveStoreProvider);
    expect(state.isDisliked('sc_1'), isTrue);
    // Список дизлайков надо чем-то показывать: одного id мало.
    expect(state.dislikes['sc_1']!.name, 'Song');
  });

  test('повторный дизлайк снимает метку', () {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);
    final track = _track('sc_1');

    expect(wave.toggleDislike(track), isTrue);
    expect(wave.toggleDislike(track), isFalse);
    expect(c.read(waveStoreProvider).isDisliked('sc_1'), isFalse);
  });

  test('показанное волной не возвращается в выдачу', () {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);

    expect(wave.wasShown('sc_1'), isFalse);
    wave.markShown(['sc_1', 'sc_2']);
    expect(wave.wasShown('sc_1'), isTrue);
    expect(wave.wasShown('sc_3'), isFalse);
    // Срок задаётся вызывающим: за сутки трек «показанным» ещё не считается.
    expect(wave.wasShown('sc_1', withinDays: 0), isFalse);
  });

  test('пометок не копится больше потолка', () {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);
    wave.markShown([for (var i = 0; i < kShownLimit + 50; i++) 'sc_$i']);

    // Свежие остаются, самые старые вытеснены — карта не растёт вечно.
    expect(wave.wasShown('sc_${kShownLimit + 49}'), isTrue);
    var kept = 0;
    for (var i = 0; i < kShownLimit + 50; i++) {
      if (wave.wasShown('sc_$i')) kept++;
    }
    expect(kept, kShownLimit);
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
            seeds: const ['sc_1'],
            startedAt: 5,
            playedIds: ['sc_1', 'sc_2'],
            artistBonus: {'artist': 3},
          ),
        );

    final restored = _container(
      store,
    ).read(waveStoreProvider.notifier).savedSession!;
    expect(restored.mode, WaveMode.track);
    expect(restored.seeds, ['sc_1']);
    expect(restored.playedIds, ['sc_1', 'sc_2']);
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
