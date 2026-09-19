/// «Поделиться»: ссылка, раскладка карточки и шторка — и для сущностей
/// площадок, и для профиля.
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
import 'package:bloom/core/store/play_log.dart' show playLogStoreProvider;
import 'package:bloom/features/profile/profile_store.dart';
import 'package:bloom/features/settings/cover_accent.dart'
    show kShareToneFallback;
import 'package:bloom/features/profile/ui/profile_share_card.dart';
import 'package:bloom/features/profile/ui/profile_share_sheet.dart';
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
        child: ShareCard(
          title: title,
          artist: artist,
          cover: null,
          logo: null,
          tone: kShareToneFallback,
        ),
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
      // 20 + 38 + 18 + 18 + 340 + 20 + 27.72 + 7 + 16.9 + 42
      expect(size.height, closeTo(547.6, 1));
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

    testWidgets('длинное название: вторая строка и эллипсис', (tester) async {
      await _pumpCard(tester, title: 'Glory Box', artist: 'Portishead');
      final oneLine = tester.getSize(find.byType(ShareCard)).height;

      await _pumpCard(
        tester,
        title: 'Glory Box (Original Mix) — Live at the Roseland Ballroom, NYC',
        artist: 'Portishead',
      );
      final size = tester.getSize(find.byType(ShareCard));
      expect(size.width, kShareCardW);
      // Ровно одна лишняя строка (22 × 1.26): дальше название режется
      // эллипсисом, как на ПК, а не растит карточку до бесконечности.
      expect(size.height - oneLine, closeTo(27.72, 0.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('профиль: ссылка', () {
    test('поля на местах, тип profile', () {
      final params = _params(
        buildProfileShareUrl(
          name: 'bxzlik',
          tracks: 128,
          plays: 1240,
          time: '47ч 12м',
          favArtist: 'Portishead',
          bio: 'слушаю всё подряд',
        ),
      );
      expect(params['type'], 'profile');
      expect(params['name'], 'bxzlik');
      expect(params['tracks'], '128');
      expect(params['plays'], '1240');
      expect(params['time'], '47ч 12м');
      expect(params['artist'], 'Portishead');
      expect(params['bio'], 'слушаю всё подряд');
    });

    test('пустые артист и био выпадают, свой аватар не идёт', () {
      final params = _params(
        buildProfileShareUrl(
          name: 'bxzlik',
          tracks: 0,
          plays: 0,
          time: '0 мин',
          favArtist: null,
          bio: '',
          // На телефоне картинки профиля ВСЕГДА свои, файлом: снаружи такую
          // ссылку никто не откроет.
          avatar: 'local:ava.png',
        ),
      );
      expect(params.containsKey('artist'), isFalse);
      expect(params.containsKey('bio'), isFalse);
      expect(params.containsKey('avatar'), isFalse);
      // Нули и пустая статистика ссылку не ломают.
      expect(params['tracks'], '0');
    });
  });

  group('профиль: карточка', () {
    testWidgets('дизайн-бокс 380 и высота как на ПК', (tester) async {
      await _pumpProfileCard(tester);
      final size = tester.getSize(find.byType(ProfileShareCard));
      expect(size.width, kShareCardW);
      // 20 + 38 + 18 + 18 + 64 + 20 + 139 + 22
      expect(size.height, closeTo(339, 1));

      expect(find.text('Bloom'), findsOneWidget);
      expect(find.text('bxzlik'), findsOneWidget);
      // Подписи ячеек — капсом, как `stats.card.*` на ПК.
      expect(find.text('ТРЕКОВ'), findsOneWidget);
      expect(find.text('ЛЮБИМЫЙ ИСПОЛНИТЕЛЬ'), findsOneWidget);
      // Футера у карточки нет: ни строки с числом прослушиваний, ни белого
      // кружка со стрелкой — она кончается сеткой.
      expect(find.text('1 240 прослушиваний'), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('без аватара — буква ника на градиенте', (tester) async {
      await _pumpProfileCard(tester);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('длинное значение ужимается, но не мельче 13', (tester) async {
      await _pumpProfileCard(tester, favArtist: 'Godspeed You! Black Emperor');
      final value = tester.widget<Text>(
        find.text('Godspeed You! Black Emperor'),
      );
      expect(value.style?.fontSize, lessThan(24));
      expect(value.style?.fontSize, greaterThanOrEqualTo(13));
      // Ячейка от этого не растёт: высота карточки прежняя.
      expect(
        tester.getSize(find.byType(ProfileShareCard)).height,
        closeTo(339, 1),
      );
    });

    testWidgets('нет любимого артиста — прочерк', (tester) async {
      await _pumpProfileCard(tester, favArtist: null);
      expect(find.text('—'), findsOneWidget);
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

    testWidgets('профиль: свой заголовок и ссылка type=profile', (
      tester,
    ) async {
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

      await _pumpSheet(tester, null);
      expect(find.text('Поделиться профилем'), findsOneWidget);
      expect(find.text('Поделиться'), findsOneWidget);

      await tester.tap(find.text('Скопировать ссылку'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final copy = calls.firstWhere((c) => c.method == 'Clipboard.setData');
      final params = _params((copy.arguments as Map)['text'] as String);
      expect(params['type'], 'profile');
      // Ника никто не задавал — в ссылку уходит тот же дефолт, что видно на
      // карточке, а не пустая строка.
      expect(params['name'], 'Пользователь');
      expect(find.text('Поделиться профилем'), findsNothing);
    });
  });
}

/// Карточка профиля: локализация ей нужна вся (подписи ячеек, футер, дефолтный
/// ник), поэтому дом у неё `MaterialApp` с делегатами.
Future<void> _pumpProfileCard(
  WidgetTester tester, {
  String? favArtist = 'Portishead',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: ProfileShareCard(
          profile: const UserProfile(name: 'bxzlik', bio: 'слушаю всё подряд'),
          stats: ProfileCardStats(
            tracks: 128,
            plays: 1240,
            time: '47ч 12м',
            favArtist: favArtist,
          ),
          avatar: null,
          logo: null,
          tone: kShareToneFallback,
        ),
      ),
    ),
  );
}

/// Хост со шторкой: она идёт через корневой навигатор и читает настройки
/// прозрачности, поэтому нужен и `MaterialApp`, и контейнер с хранилищем.
///
/// `target == null` — шторка профиля: у неё цели нет, всё нужное она берёт из
/// провайдеров.
Future<void> _pumpSheet(WidgetTester tester, ShareTarget? target) async {
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      // Цифры карточки профиля считаются по журналу прослушиваний.
      playLogStoreProvider.overrideWithValue(JsonStore.memory()),
    ],
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
              onPressed: () => target == null
                  ? showProfileShareSheet(context)
                  : showShareSheet(context, target),
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
