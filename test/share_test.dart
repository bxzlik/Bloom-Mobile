/// «Поделиться»: ссылка, раскладка карточки и шторка.
///
/// Ссылку проверяем по параметрам, а не по строке целиком: их порядок для
/// страницы-посредника значения не имеет, а вот имена и значения — да (порт
/// `buildShareUrl` с ПК). Карточку — по геометрии дизайн-бокса: числа взяты с
/// десктопного `buildShareCard`, и разъехаться они не должны.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/shared/share/share_card.dart';
import 'package:bloom/shared/share/share_link.dart';
import 'package:bloom/shared/share/share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _cover = 'https://i1.sndcdn.com/artworks-abc-t300x300.jpg';

Track _track({String? cover = _cover, String? url}) => Track(
  id: 'sc_123456',
  name: 'Glory Box',
  artist: 'Portishead',
  duration: const Duration(minutes: 5),
  source: MusicSource.soundcloud,
  cover: cover,
  url: url ?? 'https://soundcloud.com/portishead/glory-box',
);

Map<String, String> _params(String url) => Uri.parse(url).queryParameters;

Future<void> _pumpCard(
  WidgetTester tester, {
  required String title,
  required String artist,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: ShareCard(title: title, artist: artist, cover: null, logo: null),
      ),
    ),
  );
}

void main() {
  group('ссылка', () {
    test('трек: sc-префикс снят, поля на местах', () {
      final target = ShareTarget.track(_track());
      expect(target.url, startsWith(kShareBase));

      final params = _params(target.url);
      expect(params['type'], 'track');
      // `sc_123456` → `123456`: страница-посредник ждёт сырой id площадки.
      expect(params['id'], '123456');
      expect(params['title'], 'Glory Box');
      expect(params['artist'], 'Portishead');
      expect(
        params['permalink'],
        'https://soundcloud.com/portishead/glory-box',
      );
      expect(params['cover'], _cover);
    });

    test('артист: имя уходит в name, подписи нет', () {
      final target = ShareTarget.artist(
        const Artist(
          id: 'sc_777',
          name: 'Portishead',
          source: MusicSource.soundcloud,
          avatar: _cover,
          permalink: 'https://soundcloud.com/portishead',
        ),
      );
      final params = _params(target.url);
      expect(params['type'], 'artist');
      expect(params['name'], 'Portishead');
      expect(params.containsKey('title'), isFalse);
      expect(params.containsKey('artist'), isFalse);
      expect(target.artist, '');
    });

    test('чужие префиксы не трогаем', () {
      final target = ShareTarget.artist(
        const Artist(
          id: 'ym_artist_42',
          name: 'Кино',
          source: MusicSource.yandex,
        ),
      );
      // Без префикса это перестанет быть артистом Яндекса.
      expect(_params(target.url)['id'], 'ym_artist_42');
    });

    test('альбом и плейлист различаются флагом', () {
      Playlist set({required bool isAlbum}) => Playlist(
        id: 'sc_55',
        title: 'Dummy',
        source: MusicSource.soundcloud,
        isAlbum: isAlbum,
        ownerName: 'Portishead',
      );
      expect(ShareTarget.set(set(isAlbum: true)).kind, ShareKind.album);
      expect(ShareTarget.set(set(isAlbum: false)).kind, ShareKind.playlist);
      expect(_params(ShareTarget.set(set(isAlbum: true)).url)['type'], 'album');
      expect(
        _params(ShareTarget.set(set(isAlbum: false)).url)['artist'],
        'Portishead',
      );
    });

    test('своя обложка в ссылку не идёт', () {
      // `local:` — файл в песочнице телефона, снаружи его никто не откроет.
      final target = ShareTarget.track(_track(cover: 'local:cover.jpg'));
      expect(_params(target.url).containsKey('cover'), isFalse);
      // В карточку она при этом попадает — там картинка своя, не по ссылке.
      expect(target.cover, 'local:cover.jpg');
    });

    test('пустых полей не боимся', () {
      final params = _params(buildShareUrl(kind: ShareKind.track));
      expect(params['id'], '');
      expect(params['title'], '');
      expect(params['permalink'], '');
    });
  });

  group('карточка', () {
    testWidgets('дизайн-бокс 380 и высота как на ПК', (tester) async {
      await _pumpCard(tester, title: 'Glory Box', artist: 'Portishead');
      final size = tester.getSize(find.byType(ShareCard));
      expect(size.width, kShareCardW);
      // 20 + 38 + 18 + 1 + 18 + 340 + 16 + 26.84 + 6 + 16.9 + 42
      expect(size.height, closeTo(542.7, 1));
      expect(find.text('Portishead'), findsOneWidget);
      expect(find.text('Bloom'), findsOneWidget);
    });

    testWidgets('без артиста карточка ровно на строку короче', (tester) async {
      await _pumpCard(tester, title: 'Glory Box', artist: 'Portishead');
      final withArtist = tester.getSize(find.byType(ShareCard)).height;

      await _pumpCard(tester, title: 'Glory Box', artist: '');
      final without = tester.getSize(find.byType(ShareCard)).height;

      // Строка артиста: 13 × 1.3. Нижний отступ на ПК одинаков в обоих случаях.
      expect(withArtist - without, closeTo(16.9, 0.5));
    });

    testWidgets('длинное название режется, а не ломает бокс', (tester) async {
      await _pumpCard(
        tester,
        title: 'Glory Box (Original Mix) — Live at the Roseland Ballroom, NYC',
        artist: 'Portishead',
      );
      expect(tester.getSize(find.byType(ShareCard)).width, kShareCardW);
      expect(tester.takeException(), isNull);
    });
  });

  group('шторка', () {
    testWidgets('заголовок по типу, обе кнопки на месте', (tester) async {
      await _pumpSheet(tester, ShareTarget.track(_track(cover: null)));
      expect(find.text('Поделиться треком'), findsOneWidget);
      expect(find.text('Поделиться'), findsOneWidget);
      expect(find.text('Скопировать ссылку'), findsOneWidget);
    });

    testWidgets('копирование кладёт в буфер ссылку Bloom', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final target = ShareTarget.track(_track(cover: null));
      await _pumpSheet(tester, target);
      await tester.tap(find.text('Скопировать ссылку'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final copy = calls.firstWhere((c) => c.method == 'Clipboard.setData');
      expect((copy.arguments as Map)['text'], target.url);
      // Шторка закрывается сразу, как модалка на ПК.
      expect(find.text('Поделиться треком'), findsNothing);
    });
  });
}

/// Хост со шторкой: она идёт через корневой навигатор и читает настройки
/// прозрачности, поэтому нужен и `MaterialApp`, и контейнер с хранилищем.
Future<void> _pumpSheet(WidgetTester tester, ShareTarget target) async {
  final container = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(JsonStore.memory())],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShareSheet(context, target),
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('открыть'));
  // `pumpAndSettle` здесь НЕЛЬЗЯ: пока обложка не долетела, на главной кнопке
  // крутится кружок, и «покоя» шторка не достигнет никогда.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
