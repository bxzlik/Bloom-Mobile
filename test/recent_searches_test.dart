/// Недавнее в поиске: запросы и открытые карточки — порядок, дедуп, потолок и
/// чтение с диска, то же, что делают `bloom_recent_searches` и
/// `bloom_recent_items` на десктопе.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/search/recent_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

Track _track(String id) => Track(
  id: id,
  name: 'Nightcall',
  artist: 'Kavinsky',
  duration: const Duration(seconds: 258),
  source: MusicSource.soundcloud,
  cover: 'https://cdn/nightcall.jpg',
  sourceData: const {'transcodings': []},
);

void main() {
  test('новый запрос встаёт наверх', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentSearchesProvider.notifier);
    notifier.push('daft punk');
    notifier.push('radiohead');
    expect(c.read(recentSearchesProvider), ['radiohead', 'daft punk']);
  });

  test('повтор не двоится и поднимается, оставляя последнее написание', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentSearchesProvider.notifier);
    notifier.push('daft punk');
    notifier.push('radiohead');
    notifier.push('  Daft Punk  ');
    expect(c.read(recentSearchesProvider), ['Daft Punk', 'radiohead']);
  });

  test('пустой запрос не запоминается', () {
    final c = _container(JsonStore.memory());
    c.read(recentSearchesProvider.notifier).push('   ');
    expect(c.read(recentSearchesProvider), isEmpty);
  });

  test('дальше потолка список не растёт, лишнее уходит снизу', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentSearchesProvider.notifier);
    for (var i = 0; i <= kRecentSearchMax; i++) {
      notifier.push('q$i');
    }
    final state = c.read(recentSearchesProvider);
    expect(state, hasLength(kRecentSearchMax));
    expect(state.first, 'q$kRecentSearchMax');
    expect(state, isNot(contains('q0')));
  });

  test('удаление и очистка', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentSearchesProvider.notifier);
    notifier.push('a');
    notifier.push('b');
    notifier.remove('a');
    expect(c.read(recentSearchesProvider), ['b']);
    notifier.clear();
    expect(c.read(recentSearchesProvider), isEmpty);
  });

  test('список переживает перезапуск: пишется и читается из хранилища', () {
    final store = JsonStore.memory();
    _container(store).read(recentSearchesProvider.notifier).push('kavinsky');
    // Второй контейнер = новый запуск приложения с тем же файлом.
    expect(_container(store).read(recentSearchesProvider), ['kavinsky']);
  });

  test('чужое содержимое ключа не роняет чтение', () {
    final store = JsonStore.memory({
      'recentSearches': ['ok', 42, null],
    });
    expect(_container(store).read(recentSearchesProvider), ['ok']);
  });

  test('открытое: наверх, без дублей по типу и id', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentItemsProvider.notifier);
    notifier.push(RecentTrack(_track('sc_1')));
    notifier.push(
      RecentArtist(
        const Artist(id: 'sc_9', name: 'Kavinsky', source: MusicSource.local),
      ),
    );
    notifier.push(RecentTrack(_track('sc_1')));

    final state = c.read(recentItemsProvider);
    expect(state, hasLength(2));
    expect(state.first, isA<RecentTrack>());
  });

  test('трек и сет с одинаковым id — разные записи', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentItemsProvider.notifier);
    notifier.push(RecentTrack(_track('sc_1')));
    notifier.push(
      RecentSet(
        const Playlist(id: 'sc_1', title: 'Outrun', source: MusicSource.local),
      ),
    );
    expect(c.read(recentItemsProvider), hasLength(2));
  });

  test('дальше потолка список открытых не растёт', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentItemsProvider.notifier);
    for (var i = 0; i <= kRecentItemMax; i++) {
      notifier.push(RecentTrack(_track('sc_$i')));
    }
    expect(c.read(recentItemsProvider), hasLength(kRecentItemMax));
  });

  test('открытое переживает перезапуск целой сущностью', () {
    final store = JsonStore.memory();
    _container(store).read(recentItemsProvider.notifier)
      ..push(RecentTrack(_track('sc_1')))
      ..push(
        RecentSet(
          const Playlist(
            id: 'ym_5',
            title: 'Outrun',
            source: MusicSource.local,
            isAlbum: true,
            ownerName: 'Kavinsky',
          ),
        ),
      );

    final restored = _container(store).read(recentItemsProvider);
    expect(restored, hasLength(2));
    // Сет открывается той же сущностью, что пришла в выдаче, — и `sourceData`
    // трека тоже на месте, иначе стрим пришлось бы резолвить заново.
    expect(restored.first, isA<RecentSet>());
    final set = (restored.first as RecentSet).set;
    expect(set.isAlbum, isTrue);
    expect(set.ownerName, 'Kavinsky');
    expect(set.source, MusicSource.yandex); // источник восстановлен по id
    final track = (restored.last as RecentTrack).track;
    expect(track.sourceData, isNotNull);
    expect(track.cover, 'https://cdn/nightcall.jpg');
  });

  test('удаление и очистка открытых', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentItemsProvider.notifier);
    final track = RecentTrack(_track('sc_1'));
    notifier.push(track);
    notifier.push(RecentTrack(_track('sc_2')));
    // Удаляем по ключу, а не по ссылке: в списке лежит запись, восстановленная
    // с диска, — тем же объектом она уже не будет.
    notifier.remove(RecentTrack(_track('sc_1')));
    expect(c.read(recentItemsProvider), hasLength(1));
    notifier.clear();
    expect(c.read(recentItemsProvider), isEmpty);
  });

  test('битая запись открытого пропускается, остальные читаются', () {
    final store = JsonStore.memory({
      'recentItems': [
        {'kind': 'track', 'data': null},
        {'kind': 'таких нет', 'data': <String, dynamic>{}},
        {
          'kind': 'artist',
          'data': {'id': 'sc_9', 'name': 'Kavinsky'},
        },
      ],
    });
    final state = _container(store).read(recentItemsProvider);
    expect(state, hasLength(1));
    expect((state.single as RecentArtist).artist.name, 'Kavinsky');
  });
}
