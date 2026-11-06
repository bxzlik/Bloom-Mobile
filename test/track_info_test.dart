/// Track info: the platform's full record fills in after the row, the artists
/// open their pages, and a song's auto-generated YouTube description reads as
/// a release card.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/detail/ui/artist_screen.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/providers/ytmusic/ytmusic.dart' as ytm;
import 'package:bloom/shared/ui/track_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud(this.details);

  final TrackDetails? details;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<TrackDetails?> trackDetails(Track track, {String lang = 'en'}) async =>
      details;
}

class _SilentPlayback extends PlaybackController {
  @override
  PlaybackState build() => const PlaybackState();
}

const _track = Track(
  id: 'sc:1',
  name: 'Где нас нет',
  artist: 'Oxxxymiron',
  duration: Duration(minutes: 4, seconds: 26),
  source: MusicSource.soundcloud,
  artistId: 'sc:artist:7',
);

Future<void> _open(WidgetTester tester, TrackDetails? details) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jsonStoreProvider.overrideWithValue(JsonStore.memory()),
        dbProvider.overrideWithValue(BloomDb.memory()),
        registryProvider.overrideWithValue(
          ProviderRegistry()..register(_FakeSoundCloud(details)),
        ),
        playbackProvider.overrideWith(_SilentPlayback.new),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTrackInfoSheet(context, _track),
              child: const Text('инфо'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('инфо'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("the platform's record fills the rows in", (tester) async {
    await _open(
      tester,
      const TrackDetails(
        album: 'Горгород',
        released: '2015-11-13',
        label: 'ONErpm',
        authors: ['Мирон Фёдоров', 'Scady'],
        genres: ['hip-hop'],
      ),
    );

    expect(find.text('Горгород'), findsOneWidget);
    expect(find.text('13 ноября 2015'), findsOneWidget);
    expect(find.text('ONErpm'), findsOneWidget);
    expect(find.text('Мирон Фёдоров, Scady'), findsOneWidget);
    expect(find.text('hip-hop'), findsOneWidget);
    expect(find.text('4:26'), findsOneWidget);
  });

  testWidgets('nothing known says so in words', (tester) async {
    const bare = Track(
      id: 'sc:2',
      name: 'x',
      artist: 'y',
      duration: Duration.zero,
      source: MusicSource.soundcloud,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jsonStoreProvider.overrideWithValue(JsonStore.memory()),
          dbProvider.overrideWithValue(BloomDb.memory()),
          registryProvider.overrideWithValue(
            ProviderRegistry()..register(_FakeSoundCloud(null)),
          ),
          playbackProvider.overrideWith(_SilentPlayback.new),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildBloomTheme(BloomThemes.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTrackInfoSheet(context, bare),
                child: const Text('инфо'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('инфо'));
    await tester.pumpAndSettle();

    expect(
      find.text('Больше площадка об этом треке ничего не рассказала'),
      findsOneWidget,
    );
  });

  testWidgets('an artist opens their page here', (tester) async {
    await _open(tester, null);

    await tester.tap(find.text('Oxxxymiron').last);
    await tester.pumpAndSettle();

    expect(find.byType(ArtistScreen), findsOneWidget);
  });

  group('releaseCard', () {
    test('an auto-generated card gives label, album, date and writers', () {
      final card = ytm.releaseCard('''
Provided to YouTube by Daft Life Ltd./ADA France

One More Time (Radio Edit) · Daft Punk

One More Time

℗ 2001 Daft Life Limited

Producer, Synthesizer: Thomas Bangalter
Mastering Engineer: Nilesh Patel
Writer: Anthony Moore
Writer: Thomas Bangalter

Auto-generated by YouTube.''');
      expect(card.label, 'Daft Life Ltd./ADA France');
      expect(card.album, 'One More Time');
      expect(card.released, '2001');
      expect(card.authors, ['Anthony Moore', 'Thomas Bangalter']);
      expect(card.description, isEmpty);
    });

    test('a release date wins over the phonogram year', () {
      final card = ytm.releaseCard('''
Provided to YouTube by ONErpm

Где нас нет · Oxxxymiron · Miron Fyodorov

Горгород

℗ Oxxxymiron

Released on: 2015-11-13

Auto-generated by YouTube.''');
      expect(card.album, 'Горгород');
      expect(card.released, '2015-11-13');
      expect(card.authors, isEmpty);
    });

    test("an uploader's own text stays a description", () {
      final card = ytm.releaseCard('Official video\nhttps://example.com');
      expect(card.description, 'Official video\nhttps://example.com');
      expect(card.label, isEmpty);
    });
  });
}
