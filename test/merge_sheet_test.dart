/// Merging through its sheet: the new playlist's picture, the toast's Undo, and
/// the deleted sources coming back with it.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/library/ui/merge_sheet.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:bloom/shared/ui/bloom_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/glyphs.dart';
import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  artist: 'Artist',
  duration: const Duration(seconds: 200),
  source: MusicSource.soundcloud,
);

class _Page {
  _Page(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  LibraryState get lib => container.read(libraryProvider);
  Iterable<String> get names => lib.playlists.map((p) => p.name);
}

Future<_Page> _open(
  WidgetTester tester, {
  String coverA = '',
  String coverB = '',
}) async {
  final store = JsonStore.memory();
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(container.dispose);
  final library = container.read(libraryProvider.notifier);
  final a = library.createPlaylist(
    'First',
    tracks: [_track('sc:1'), _track('sc:2')],
    cover: coverA,
  );
  library.createPlaylist('Second', tracks: [_track('sc:3')], cover: coverB);

  final router = GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
        path: '/library',
        builder: (_, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showMergeSheet(context, ref, a),
              child: const Text('open'),
            ),
          ),
        ),
        routes: [
          GoRoute(
            path: 'list/:id',
            builder: (_, state) =>
                Scaffold(body: Text('list ${state.pathParameters['id']}')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        routerConfig: router,
        builder: (_, child) => ToastHost(child: child!),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return _Page(container, router);
}

/// Picks the second list and merges. Not settling after: a toast with Undo would
/// live out its time meanwhile.
Future<void> _merge(WidgetTester tester, {bool deleteSources = false}) async {
  await tester.tap(find.text('Second'));
  await tester.pumpAndSettle();
  if (deleteSources) {
    await tester.tap(find.text('Удалить исходные'));
    await tester.pumpAndSettle();
  }
  await tester.tap(findGlyph(Bi.check));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  testWidgets('the toast says how many and undoes the new one', (tester) async {
    final page = await _open(tester);
    await _merge(tester);

    expect(page.names, contains('First +'));
    expect(page.router.state.uri.path, startsWith('/library/list/'));
    expect(find.text('Плейлист создан · 3 трека'), findsOneWidget);

    await tester.tap(find.text('Отменить'));
    await tester.pump();
    expect(page.names, unorderedEquals(['First', 'Second']));
    expect(page.router.state.uri.path, '/library');
    await tester.pumpAndSettle();
  });

  testWidgets('Undo brings the deleted sources back, tracks in place', (
    tester,
  ) async {
    final page = await _open(tester);
    await _merge(tester, deleteSources: true);
    expect(page.names, ['First +']);

    await tester.tap(find.text('Отменить'));
    await tester.pump();

    expect(page.names, unorderedEquals(['First', 'Second']));
    final first = page.lib.playlists.singleWhere((p) => p.name == 'First');
    expect(first.trackIds, ['sc:1', 'sc:2']);
    await tester.pumpAndSettle();
  });

  testWidgets('with no Undo the sources stay gone', (tester) async {
    final page = await _open(tester);
    await _merge(tester, deleteSources: true);

    await tester.pumpAndSettle(const Duration(seconds: 6));

    expect(page.names, ['First +']);
    expect(find.text('Отменить'), findsNothing);
  });

  group('the new one\'s picture', () {
    Future<String?> coverOfNew(
      WidgetTester tester, {
      String coverA = '',
      String coverB = '',
    }) async {
      final page = await _open(tester, coverA: coverA, coverB: coverB);
      await _merge(tester);
      final cover = page.lib.playlists
          .singleWhere((p) => p.name == 'First +')
          .cover;
      await tester.pumpAndSettle(const Duration(seconds: 6));
      // The sheet's banner tried to load the link; tests have no network.
      tester.takeException();
      return cover;
    }

    testWidgets('the source lends its own', (tester) async {
      expect(
        await coverOfNew(tester, coverA: 'https://a', coverB: 'https://b'),
        'https://a',
      );
    });

    testWidgets('else the next list with one', (tester) async {
      expect(await coverOfNew(tester, coverB: 'https://b'), 'https://b');
    });

    testWidgets('with none at all it stays a collage', (tester) async {
      expect(await coverOfNew(tester) ?? '', isEmpty);
    });
  });
}
