/// Импорт по ссылке из шторки «+»: куда попадают треки и что считается
/// «добавлено».
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/library/import_url.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  sourceData: const {'transcodings': []},
);

/// Площадка, у которой по ссылке лежит либо плейлист, либо одиночный трек.
class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud({this.sets = const {}, this.singles = const {}});

  /// Ссылка → состав плейлиста.
  final Map<String, List<Track>> sets;

  /// Ссылки, за которыми стоит один трек, — импортировать такое нельзя.
  final Map<String, Track> singles;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  /// id коллекции — последняя часть пути: `https://sc/one?x` → `sc:set:one`,
  /// так две разные ссылки ведут к одной коллекции.
  static String _idOf(String url) =>
      'sc:set:${Uri.parse(url).pathSegments.last}';

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    final single = singles[url];
    if (single != null) return ResolvedTrack(single);
    final bare = url.split('?').first;
    if (!sets.containsKey(bare)) return null;
    return ResolvedSet(
      Playlist(
        id: _idOf(bare),
        title: 'Сет',
        ownerName: 'Владелец',
        sourceUrl: bare,
        source: MusicSource.soundcloud,
      ),
    );
  }

  @override
  Future<SetContent?> getPlaylist(String id) async => SetContent(
    playlist: Playlist(id: id, title: 'Сет', source: MusicSource.soundcloud),
    tracks: [
      for (final e in sets.entries)
        if (_idOf(e.key) == id) ...e.value,
    ],
  );
}

({ProviderContainer container, ProviderRegistry registry}) _setup(
  _FakeSoundCloud provider,
) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(BloomDb.memory()),
    ],
  );
  addTearDown(c.dispose);
  return (container: c, registry: ProviderRegistry()..register(provider));
}

Future<ImportResult> _import(
  ({ProviderContainer container, ProviderRegistry registry}) env,
  String url,
  ImportTarget target,
) => importUrlInto(
  env.registry,
  env.container.read(libraryProvider.notifier),
  () => env.container.read(libraryProvider),
  url,
  target,
);

void main() {
  test('цель «Создать» делает плейлист с источником и всеми треками', () async {
    final env = _setup(
      _FakeSoundCloud(
        sets: {
          'https://sc/one': [_track('sc:1'), _track('sc:2')],
        },
      ),
    );

    final result = await _import(
      env,
      'https://sc/one',
      const ImportTarget.create(),
    );

    expect(result.added, 2);
    final playlist = env.container.read(libraryProvider).playlists.single;
    expect(playlist.id, result.createdId);
    expect(playlist.trackIds, ['sc:1', 'sc:2']);
    // Источник запомнен — иначе плейлист нечем было бы обновлять. Вид — как
    // на ПК: обновление идёт по id коллекции у её площадки.
    final source = playlist.sources.single;
    expect(source.toJson(), {
      'url': 'https://sc/one',
      'title': 'Сет',
      'owner': 'Владелец',
      'provider': 'sc',
      'id': 'sc:set:one',
      'kind': 'playlist',
      'cover': '',
    });
    expect(PlSourceRef.fromJson(source.toJson())?.toJson(), source.toJson());
  });

  test('источник без id или площадки не читается', () {
    expect(PlSourceRef.fromJson({'url': 'https://sc/one'}), isNull);
    expect(PlSourceRef.fromJson({'id': 'sc:set:1'}), isNull);
    expect(
      PlSourceRef.fromJson({'id': 'sc:set:1', 'provider': 'sc'})?.kind,
      'playlist',
    );
  });

  test('цель «Все треки» не создаёт плейлист и не считает дубли', () async {
    final env = _setup(
      _FakeSoundCloud(
        sets: {
          'https://sc/one': [_track('sc:1'), _track('sc:2')],
        },
      ),
    );
    env.container.read(libraryProvider.notifier).addToLibrary([_track('sc:1')]);

    final result = await _import(
      env,
      'https://sc/one',
      const ImportTarget(ImportTargetKind.library),
    );

    expect(result.added, 1);
    expect(result.total, 2);
    expect(result.createdId, isNull);
    expect(env.container.read(libraryProvider).playlists, isEmpty);
    expect(env.container.read(libraryProvider).inLib.length, 2);
  });

  test('цель «Любимые» лайкает только ещё не залайканное', () async {
    final env = _setup(
      _FakeSoundCloud(
        sets: {
          'https://sc/one': [_track('sc:1'), _track('sc:2')],
        },
      ),
    );
    env.container.read(libraryProvider.notifier).toggleFav(_track('sc:1'));

    final result = await _import(
      env,
      'https://sc/one',
      const ImportTarget(ImportTargetKind.favorites),
    );

    expect(result.added, 1);
    expect(env.container.read(libraryProvider).favs.length, 2);
  });

  test('импорт в существующий плейлист привязывает источник', () async {
    final env = _setup(
      _FakeSoundCloud(
        sets: {
          'https://sc/one': [_track('sc:1'), _track('sc:2')],
        },
      ),
    );
    final target = env.container
        .read(libraryProvider.notifier)
        .createPlaylist('Мой', tracks: [_track('sc:1')]);

    final result = await _import(
      env,
      'https://sc/one',
      ImportTarget(ImportTargetKind.playlist, playlistId: target.id),
    );

    expect(result.added, 1);
    final playlist = env.container.read(libraryProvider).playlists.single;
    expect(playlist.trackIds.toSet(), {'sc:1', 'sc:2'});
    // Импортированная коллекция становится источником и у существующего
    // плейлиста: обновление только подмешивает новые треки наверх, добавленное
    // руками остаётся на месте.
    expect(playlist.sources.map((s) => s.id), ['sc:set:one']);

    // Другая ссылка на ту же коллекцию второй привязкой не становится.
    await _import(
      env,
      'https://sc/one?utm=share',
      ImportTarget(ImportTargetKind.playlist, playlistId: target.id),
    );
    expect(
      env.container.read(libraryProvider).playlists.single.sources.length,
      1,
    );
  });

  test('ссылка на одиночный трек отклоняется', () async {
    final env = _setup(
      _FakeSoundCloud(singles: {'https://sc/track': _track('sc:1')}),
    );

    expect(
      () => _import(env, 'https://sc/track', const ImportTarget.create()),
      throwsA(isA<ImportException>()),
    );
  });

  test('неизвестная ссылка отклоняется', () async {
    final env = _setup(_FakeSoundCloud());
    expect(
      () => _import(env, 'https://example.com/x', const ImportTarget.create()),
      throwsA(isA<ImportException>()),
    );
  });
}
