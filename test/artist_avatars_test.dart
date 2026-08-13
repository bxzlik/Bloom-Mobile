/// Кеш аватаров исполнителей: точное совпадение имени, промахи тоже
/// запоминаются, свежий кеш сеть не дёргает.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/profile/artist_avatars.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Artist _artist(String name, String? avatar) => Artist(
  id: 'sc_$name',
  name: name,
  avatar: avatar,
  source: MusicSource.soundcloud,
);

class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud(this.answers);

  /// Что отдавать на запрос имени.
  final Map<String, List<Artist>> answers;

  final List<String> queries = [];

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 3}) async {
    queries.add(query);
    final found = answers[query];
    if (found == null) throw StateError('нет сети');
    return found;
  }
}

ProviderContainer _container(
  _FakeSoundCloud provider, [
  Map<String, dynamic>? seed,
]) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory(seed)),
      registryProvider.overrideWithValue(
        ProviderRegistry()..register(provider),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('берётся точное совпадение имени, а не первый из выдачи', () async {
    final sc = _FakeSoundCloud({
      'Onda': [
        _artist('Onda Fan Page', 'https://cdn/fan.jpg'),
        _artist('onda', 'https://cdn/real.jpg'),
      ],
    });
    final c = _container(sc);

    await c.read(artistAvatarsProvider.notifier).ensure(['Onda']);

    expect(c.read(artistAvatarsProvider)['onda'], 'https://cdn/real.jpg');
  });

  test('свежий кеш второй раз в сеть не идёт', () async {
    final sc = _FakeSoundCloud({
      'Artist': [_artist('Artist', 'https://cdn/a.jpg')],
    });
    final c = _container(sc);

    await c.read(artistAvatarsProvider.notifier).ensure(['Artist']);
    await c.read(artistAvatarsProvider.notifier).ensure(['Artist']);

    expect(sc.queries, ['Artist']);
  });

  test('промах запоминается — по нему тоже не долбимся повторно', () async {
    // Провайдер падает на любой запрос: сети нет.
    final sc = _FakeSoundCloud(const {});
    final c = _container(sc);

    await c.read(artistAvatarsProvider.notifier).ensure(['Кто-то']);
    await c.read(artistAvatarsProvider.notifier).ensure(['Кто-то']);

    expect(sc.queries, ['Кто-то']);
    // Пустая запись наружу не показывается — в UI останется обложка трека.
    expect(c.read(artistAvatarsProvider), isEmpty);
  });

  test('протухшая запись перезапрашивается, живая — нет', () async {
    final old = DateTime.now()
        .subtract(const Duration(days: 31))
        .millisecondsSinceEpoch;
    final fresh = DateTime.now().millisecondsSinceEpoch;
    final sc = _FakeSoundCloud({
      'Stale': [_artist('Stale', 'https://cdn/new.jpg')],
      'Fresh': [_artist('Fresh', 'https://cdn/nope.jpg')],
    });
    final c = _container(sc, {
      'artistAvatars': {
        'stale': {'url': 'https://cdn/old.jpg', 't': old},
        'fresh': {'url': 'https://cdn/keep.jpg', 't': fresh},
      },
    });

    // Кеш поднялся из файла ещё до всякой сети.
    expect(c.read(artistAvatarsProvider)['fresh'], 'https://cdn/keep.jpg');

    await c.read(artistAvatarsProvider.notifier).ensure(['Stale', 'Fresh']);

    expect(sc.queries, ['Stale']);
    expect(c.read(artistAvatarsProvider)['stale'], 'https://cdn/new.jpg');
  });
}
