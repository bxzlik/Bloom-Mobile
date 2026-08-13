/// Артисты трека в плеере: один — сразу на страницу, несколько — шторкой с
/// аватарками, и в ней ходить можно только к тем, кого площадка знает.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/detail/artists_sheet.dart';
import 'package:bloom/features/detail/ui/artist_screen.dart';
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/bloom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/core/l10n/l10n.dart';

Artist _artist(String name, {String? avatar, int? followers}) => Artist(
  id: 'sc_artist_$name',
  name: name,
  avatar: avatar,
  followers: followers,
  source: MusicSource.soundcloud,
);

Track _track(String artist) => Track(
  id: 'sc_1',
  name: 'Песня',
  artist: artist,
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
  artistId: 'sc_artist_uploader',
);

class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud(this.answers);

  /// Что отдавать на запрос имени. Имени нет в карте — площадка молчит.
  final Map<String, List<Artist>> answers;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 3}) async =>
      answers[query] ?? const [];
}

/// Экран с кнопкой, по которой открывается развилка артистов.
Future<void> _pump(
  WidgetTester tester,
  Track track,
  _FakeSoundCloud provider,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jsonStoreProvider.overrideWithValue(JsonStore.memory()),
        registryProvider.overrideWithValue(
          ProviderRegistry()..register(provider),
        ),
      ],
      child: MaterialApp(
        // Язык прибит гвоздями: иначе проверки текста зависели бы от локали
        // машины, на которой гоняют тесты.
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => openTrackArtist(context, ref, track),
              child: const Text('артист'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Ссылки на аватарки, которые сейчас на экране.
List<String?> _avatars(WidgetTester tester) => [
  for (final c in tester.widgetList<Cover>(find.byType(Cover)))
    if (c.circle) c.url,
];

/// Строка шторки нажимается?
bool _enabled(WidgetTester tester, String name) {
  final row = find.ancestor(
    of: find.text(name),
    matching: find.byType(InkWell),
  );
  return tester.widget<InkWell>(row.first).onTap != null;
}

void main() {
  testWidgets('несколько артистов — шторка с аватарками', (tester) async {
    final sc = _FakeSoundCloud({
      'Kanye West': [
        _artist('Kanye West', avatar: 'https://cdn/ye.jpg', followers: 1200),
      ],
      'Ty Dolla Sign': [_artist('Ty Dolla Sign', avatar: 'https://cdn/ty.jpg')],
    });
    await _pump(tester, _track('Kanye West & Ty Dolla Sign'), sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();

    // Оба имени стоят строками, а не одной ссылкой на залившего трек.
    expect(find.text('Kanye West'), findsOneWidget);
    expect(find.text('Ty Dolla Sign'), findsOneWidget);
    expect(
      _avatars(tester),
      containsAll(['https://cdn/ye.jpg', 'https://cdn/ty.jpg']),
    );
    expect(find.text('1.2K подписчиков'), findsOneWidget);
  });

  testWidgets('к незнакомому площадке артисту ходить некуда', (tester) async {
    final sc = _FakeSoundCloud({
      'Boards of Canada': [_artist('Boards of Canada')],
    });
    await _pump(tester, _track('Boards of Canada, Кто-то ещё'), sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();

    expect(find.text('Не нашли у площадки'), findsOneWidget);
    expect(_enabled(tester, 'Кто-то ещё'), isFalse);
    expect(_enabled(tester, 'Boards of Canada'), isTrue);
  });

  testWidgets('выбранный в шторке артист открывает свою страницу', (
    tester,
  ) async {
    final sc = _FakeSoundCloud({
      'Aphex Twin': [_artist('Aphex Twin')],
      'Squarepusher': [_artist('Squarepusher')],
    });
    await _pump(tester, _track('Aphex Twin vs. Squarepusher'), sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Squarepusher'));
    await tester.pumpAndSettle();

    expect(find.byType(ArtistScreen), findsOneWidget);
  });

  testWidgets('один артист без точного id — тапать нечего', (tester) async {
    final sc = _FakeSoundCloud(const {});
    final track = Track(
      id: 'sc_2',
      name: 'Песня',
      artist: 'Onda',
      duration: const Duration(minutes: 3),
      source: MusicSource.soundcloud,
    );
    await _pump(tester, track, sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();

    // Ни шторки, ни перехода: искать по имени там, где выбирать не из чего,
    // значит уводить наугад.
    expect(find.byType(SheetPanel), findsNothing);
    expect(find.byType(ArtistScreen), findsNothing);
  });
}
