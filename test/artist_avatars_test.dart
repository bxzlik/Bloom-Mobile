/// Кеш аватаров исполнителей: точное совпадение имени, промахи тоже
/// запоминаются, свежий кеш сеть не дёргает, а спрашивается артист у ТОЙ
/// площадки, где его слушали.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/profile/artist_avatars.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

Artist _artist(String name, String? avatar, [MusicSource? source]) => Artist(
  id: '${(source ?? MusicSource.soundcloud).prefix}$name',
  name: name,
  avatar: avatar,
  source: source ?? MusicSource.soundcloud,
);

class _FakeProvider extends MusicProvider {
  _FakeProvider(this.answers, [this.source = MusicSource.soundcloud]);

  /// Что отдавать на запрос имени.
  final Map<String, List<Artist>> answers;

  final List<String> queries = [];

  @override
  final MusicSource source;

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
  List<_FakeProvider> providers, [
  Map<String, dynamic>? seed,
]) {
  final registry = ProviderRegistry();
  for (final p in providers) {
    registry.register(p);
  }
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory(seed)),
      dbProvider.overrideWithValue(BloomDb.memory()),
      registryProvider.overrideWithValue(registry),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Ссылка на артиста SoundCloud — с неё начинались все прежние проверки.
ArtistRef _sc(String name) => (name: name, source: MusicSource.soundcloud);

String _key(String name, [MusicSource source = MusicSource.soundcloud]) =>
    artistAvatarKey(source, name);

void main() {
  test('берётся точное совпадение имени, а не первый из выдачи', () async {
    final sc = _FakeProvider({
      'Onda': [
        _artist('Onda Fan Page', 'https://cdn/fan.jpg'),
        _artist('onda', 'https://cdn/real.jpg'),
      ],
    });
    final c = _container([sc]);

    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Onda')]);

    expect(c.read(artistAvatarsProvider)[_key('onda')], 'https://cdn/real.jpg');
  });

  test('свежий кеш второй раз в сеть не идёт', () async {
    final sc = _FakeProvider({
      'Artist': [_artist('Artist', 'https://cdn/a.jpg')],
    });
    final c = _container([sc]);

    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Artist')]);
    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Artist')]);

    expect(sc.queries, ['Artist']);
  });

  test('промах запоминается — по нему тоже не долбимся повторно', () async {
    // Провайдер падает на любой запрос: сети нет.
    final sc = _FakeProvider(const {});
    final c = _container([sc]);

    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Кто-то')]);
    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Кто-то')]);

    expect(sc.queries, ['Кто-то']);
    // Пустая запись наружу не показывается — в UI останется обложка трека.
    expect(c.read(artistAvatarsProvider), isEmpty);
  });

  test('протухшая запись перезапрашивается, живая — нет', () async {
    final old = DateTime.now()
        .subtract(const Duration(days: 31))
        .millisecondsSinceEpoch;
    final fresh = DateTime.now().millisecondsSinceEpoch;
    final sc = _FakeProvider({
      'Stale': [_artist('Stale', 'https://cdn/new.jpg')],
      'Fresh': [_artist('Fresh', 'https://cdn/nope.jpg')],
    });
    final c = _container(
      [sc],
      {
        'artistAvatars': {
          _key('stale'): {'url': 'https://cdn/old.jpg', 't': old},
          _key('fresh'): {'url': 'https://cdn/keep.jpg', 't': fresh},
        },
      },
    );

    // Кеш поднялся из файла ещё до всякой сети.
    expect(
      c.read(artistAvatarsProvider)[_key('fresh')],
      'https://cdn/keep.jpg',
    );

    await c.read(artistAvatarsProvider.notifier).ensure([
      _sc('Stale'),
      _sc('Fresh'),
    ]);

    expect(sc.queries, ['Stale']);
    expect(c.read(artistAvatarsProvider)[_key('stale')], 'https://cdn/new.jpg');
  });

  test('артиста ищем у его площадки, а не у соседней', () async {
    final sc = _FakeProvider({
      'Тот же': [_artist('Тот же', 'https://cdn/sc.jpg')],
    });
    final ym = _FakeProvider({
      'Тот же': [_artist('Тот же', 'https://cdn/ym.jpg', MusicSource.yandex)],
    }, MusicSource.yandex);
    final c = _container([sc, ym]);

    await c.read(artistAvatarsProvider.notifier).ensure([
      (name: 'Тот же', source: MusicSource.yandex),
    ]);

    expect(sc.queries, isEmpty);
    expect(ym.queries, ['Тот же']);
    // Записи разных площадок не смешиваются: у SoundCloud её просто нет.
    final avatars = c.read(artistAvatarsProvider);
    expect(avatars[_key('тот же', MusicSource.yandex)], 'https://cdn/ym.jpg');
    expect(avatars[_key('тот же')], isNull);
  });

  test('локального артиста не спрашиваем ни у кого', () async {
    final sc = _FakeProvider({
      'Свой файл': [_artist('Свой файл', 'https://cdn/nope.jpg')],
    });
    final c = _container([sc]);

    await c.read(artistAvatarsProvider.notifier).ensure([
      (name: 'Свой файл', source: MusicSource.local),
    ]);

    expect(sc.queries, isEmpty);
    expect(c.read(artistAvatarsProvider), isEmpty);
  });

  test('записи старого кеша без площадки выбрасываются', () async {
    final fresh = DateTime.now().millisecondsSinceEpoch;
    final sc = _FakeProvider({
      'Artist': [_artist('Artist', 'https://cdn/new.jpg')],
    });
    final c = _container(
      [sc],
      {
        'artistAvatars': {
          'artist': {'url': 'https://cdn/old.jpg', 't': fresh},
        },
      },
    );

    // Чья это была аватарка, уже не сказать — в карту она не попадает.
    expect(c.read(artistAvatarsProvider), isEmpty);

    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Artist')]);

    expect(sc.queries, ['Artist']);
    expect(
      c.read(artistAvatarsProvider)[_key('artist')],
      'https://cdn/new.jpg',
    );
  });
}
