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

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    final single = singles[url];
    if (single != null) return ResolvedTrack(single);
    if (!sets.containsKey(url)) return null;
    return ResolvedSet(
      Playlist(id: url, title: 'Сет', source: MusicSource.soundcloud),
    );
  }

  @override
  Future<SetContent?> getPlaylist(String id) async => SetContent(
    playlist: Playlist(id: id, title: 'Сет', source: MusicSource.soundcloud),
    tracks: sets[id] ?? const [],
  );
}

({ProviderContainer container, ProviderRegistry registry}) _setup(
  _FakeSoundCloud provider,
) {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(JsonStore.memory())],
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
          'https://sc/one': [_track('sc_1'), _track('sc_2')],
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
    expect(playlist.trackIds, ['sc_1', 'sc_2']);
    // Источник запомнен — иначе плейлист нечем было бы обновлять.
    expect(playlist.sourceUrl, 'https://sc/one');
  });

  test('цель «Все треки» не создаёт плейлист и не считает дубли', () async {
    final env = _setup(
      _FakeSoundCloud(
        sets: {
          'https://sc/one': [_track('sc_1'), _track('sc_2')],
        },
      ),
    );
    env.container.read(libraryProvider.notifier).addToLibrary([_track('sc_1')]);

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
          'https://sc/one': [_track('sc_1'), _track('sc_2')],
        },
      ),
    );
    env.container.read(libraryProvider.notifier).toggleFav(_track('sc_1'));

    final result = await _import(
      env,
      'https://sc/one',
      const ImportTarget(ImportTargetKind.favorites),
    );

    expect(result.added, 1);
    expect(env.container.read(libraryProvider).favs.length, 2);
  });

  test('импорт в существующий плейлист не трогает его источник', () async {
    final env = _setup(
      _FakeSoundCloud(
        sets: {
          'https://sc/one': [_track('sc_1'), _track('sc_2')],
        },
      ),
    );
    final target = env.container
        .read(libraryProvider.notifier)
        .createPlaylist('Мой', tracks: [_track('sc_1')]);

    final result = await _import(
      env,
      'https://sc/one',
      ImportTarget(ImportTargetKind.playlist, playlistId: target.id),
    );

    expect(result.added, 1);
    final playlist = env.container.read(libraryProvider).playlists.single;
    expect(playlist.trackIds.toSet(), {'sc_1', 'sc_2'});
    // Привязка источника сделала бы «обновить» разрушительным: обновление
    // заменяет состав целиком и снесло бы добавленное руками.
    expect(playlist.sourceUrl, isNull);
  });

  test('ссылка на одиночный трек отклоняется', () async {
    final env = _setup(
      _FakeSoundCloud(singles: {'https://sc/track': _track('sc_1')}),
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
