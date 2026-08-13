/// Разбор и маппинг Яндекс.Музыки без сети — сверка с поведением десктопного
/// `yandex.rs` (id числом и строкой, обложка `%%` → 400x400, год из первого
/// альбома, оба формата плейлиста, подпись прямой ссылки).
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/providers/yandex/models.dart';
import 'package:bloom/providers/yandex/ym_provider.dart';
import 'package:bloom/providers/yandex/yandex.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('разбор выдачи', () {
    test('трек: id числом, артисты через запятую, обложка, год из альбома', () {
      final t = parseTrack({
        'id': 42,
        'title': 'Песня',
        'artists': [
          {'id': 7, 'name': 'Первый'},
          {'id': 8, 'name': 'Второй'},
        ],
        'coverUri': 'avatars.yandex.net/get-music/1/%%',
        'durationMs': 185000,
        'albums': [
          {'year': 2019},
        ],
      })!;

      expect(t.id, '42');
      expect(t.artist, 'Первый, Второй');
      expect(t.artistId, '7');
      expect(t.cover, 'https://avatars.yandex.net/get-music/1/400x400');
      expect(t.duration, const Duration(milliseconds: 185000));
      expect(t.year, '2019');
      // Поля available нет — Яндекс молчит только про доступные.
      expect(t.available, isTrue);
    });

    test('трек: без артистов и id — дефолты площадки, id строкой', () {
      final t = parseTrack({'id': '99', 'available': false})!;
      expect(t.id, '99');
      expect(t.title, kYmUntitled);
      expect(t.artist, kYmUnknownArtist);
      expect(t.artistId, '');
      expect(t.cover, '');
      expect(t.year, '');
      expect(t.available, isFalse);

      // Совсем без id элемент не трек — такие строки выдачи пропускаются.
      expect(parseTrack({'title': 'x'}), isNull);
    });

    test('обложка берётся из coverUri, cover.uri или ogImage', () {
      expect(coverFrom({'coverUri': 'a/%%'}), 'https://a/400x400');
      expect(
        coverFrom({
          'cover': {'uri': 'b/%%'},
        }),
        'https://b/400x400',
      );
      expect(coverFrom({'ogImage': 'c/%%'}), 'https://c/400x400');
      expect(coverFrom({}), '');
    });

    test('альбом и артист: счётчик, год, похожие', () {
      final a = parseAlbum({
        'id': 5,
        'title': 'Альбом',
        'artists': [
          {'name': 'Кто-то'},
        ],
        'year': 2021,
        'trackCount': 14,
        'ogImage': 'x/%%',
      })!;
      expect(a.artist, 'Кто-то');
      expect(a.year, '2021');
      expect(a.trackCount, 14);
      expect(a.cover, 'https://x/400x400');

      final noArtists = parseAlbum({'id': 6})!;
      expect(noArtists.artist, kYmDash);
      expect(noArtists.trackCount, 0);
      expect(parseArtist({'name': 'Без id'}), isNull);
    });

    test('плейлист: владелец из login, потом uid', () {
      final byLogin = parsePlaylist({
        'kind': 1000,
        'owner': {'login': 'user', 'uid': 55},
        'title': 'Сборник',
      })!;
      expect(byLogin.kind, '1000');
      expect(byLogin.owner, 'user');

      final byUid = parsePlaylist({
        'kind': '3',
        'owner': {'uid': 55},
      })!;
      expect(byUid.owner, '55');
    });

    test('плейлист-страница: rich-tracks и плоские треки, имя владельца', () {
      final rich = playlistEntity({
        'title': 'Мой',
        'owner': {'name': 'Вася', 'login': 'vasya'},
        'tracks': [
          {
            'track': {'id': 1, 'title': 'A'},
          },
          {'id': 2, 'title': 'B'},
        ],
      });
      expect(rich.tracks.map((t) => t.id), ['1', '2']);
      // owner.name важнее login — это отображаемое имя.
      expect(rich.subtitle, 'Вася');

      // Старый формат: владелец плоским полем.
      final flat = playlistEntity({'ownerName': 'Петя', 'tracks': []});
      expect(flat.subtitle, 'Петя');
    });
  });

  group('сквозные id', () {
    test('плейлист: owner с тильдой разбирается по последней', () {
      final id = ymPlaylistId('user~name', '1003');
      expect(id, 'ym_pl_user~name~1003');
      final parsed = parseYmPlaylistId(id)!;
      expect(parsed.owner, 'user~name');
      expect(parsed.kind, '1003');
    });

    test('публичный плейлист и числовые id', () {
      final uuid = ymPlaylistUuidId('lk.abc-123');
      expect(parseYmPlaylistUuidId(uuid), 'lk.abc-123');
      expect(parseYmPlaylistUuidId('ym_pl_a~1'), isNull);

      expect(ymNumericId('ym_42'), '42');
      expect(ymNumericId(ymArtistId('7')), '7');
      expect(ymNumericId(ymAlbumId('9')), '9');
      // Не числовой хвост — id не разобрался, провайдер просто ничего не
      // найдёт вместо падения.
      expect(ymNumericId('ym_plu_abc'), '');
    });

    test('источник узнаётся по префиксу', () {
      expect(MusicSource.fromId(ymTrackId('1')), MusicSource.yandex);
      expect(MusicSource.fromId(ymPlaylistId('u', '2')), MusicSource.yandex);
    });
  });

  group('маппинг в сущности', () {
    test('трек несёт артиста, обложку и признак доступности', () {
      final t = trackFromYm(
        const YmRawTrack(
          id: '42',
          title: 'Песня',
          artist: 'Кто-то',
          artistId: '7',
          cover: 'https://c/400x400',
          duration: Duration(seconds: 100),
          year: '2019',
          available: false,
        ),
      );
      expect(t.id, 'ym_42');
      expect(t.artistId, 'ym_artist_7');
      expect(t.year, '2019');
      expect(t.source, MusicSource.yandex);
      expect(t.sourceData?['available'], isFalse);
      // Недоступный трек качать нечего — кнопка скачивания к нему не выйдет.
      expect(const YandexProvider().canDownload(t), isFalse);
    });

    test('альбом: нулевой счётчик становится «неизвестно»', () {
      final a = albumFromYm(
        const YmRawAlbum(
          id: '5',
          title: 'Альбом',
          artist: 'Кто-то',
          cover: '',
          year: '',
          trackCount: 0,
        ),
      );
      expect(a.id, 'ym_album_5');
      expect(a.trackCount, isNull);
      expect(a.cover, isNull);
      expect(a.year, isNull);
      expect(a.isAlbum, isTrue);
      expect(a.sourceUrl, 'https://music.yandex.ru/album/5');
    });
  });

  group('ссылки', () {
    test('трек внутри альбома важнее самого альбома', () {
      const url = 'https://music.yandex.ru/album/123/track/456';
      expect(reAlbumTrack.firstMatch(url)?.group(1), '456');
      // Порядок веток в resolve: сперва трек, иначе ссылка открыла бы альбом.
      expect(reAlbum.firstMatch(url)?.group(1), '123');
    });

    test('плейлисты обоих форматов', () {
      final old = reUserPlaylist.firstMatch(
        'https://music.yandex.ru/users/vasya/playlists/1003',
      )!;
      expect(old.group(1), 'vasya');
      expect(old.group(2), '1003');

      // Префиксный id («Мне нравится») передаётся целиком, без срезания.
      expect(
        rePublicPlaylist
            .firstMatch('https://music.yandex.ru/playlists/lk.5f0e-11')
            ?.group(1),
        'lk.5f0e-11',
      );
    });
  });

  group('прямая ссылка', () {
    test('подпись: md5(соль + path без слеша + s)', () {
      expect(
        signPath('/abc/def.mp3', 'xyz'),
        '018bd052f726715baee932ed27d907fc',
      );
    });

    test('теги XML достаются по первому вхождению', () {
      const xml =
          '<download-info><host>s1.ya.net</host><path>/a/b.mp3</path>'
          '<ts>62d</ts><s>sig</s></download-info>';
      expect(xmlTag(xml, 'host'), 's1.ya.net');
      expect(xmlTag(xml, 'path'), '/a/b.mp3');
      expect(xmlTag(xml, 'ts'), '62d');
      expect(xmlTag(xml, 's'), 'sig');
      expect(xmlTag(xml, 'nope'), isNull);
    });
  });

  test('без токена площадка выключена и в поиск не идёт', () {
    setToken(null);
    expect(const YandexProvider().isEnabled, isFalse);
    setToken('  ');
    expect(activeToken(), isNull, reason: 'пробелы — это не токен');
    setToken('abc');
    expect(const YandexProvider().isEnabled, isTrue);
    setToken(null);
  });
}
