/// Маппинг `ScRaw*` → общие сущности и разбор сквозных id. Без сети.
///
/// Это новый шов между портом api-v2 и общим UI, поэтому здесь пришпилены
/// ровно те места, где такой слой обычно и врёт.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/providers/soundcloud/models.dart';
import 'package:bloom/providers/soundcloud/sc_provider.dart';
import 'package:bloom/providers/soundcloud/soundcloud.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('источник по префиксу id: ytm_ проверяется раньше ym_', () {
    expect(MusicSource.fromId('sc_123'), MusicSource.soundcloud);
    expect(MusicSource.fromId('sc_artist_123'), MusicSource.soundcloud);
    expect(MusicSource.fromId('ym_456'), MusicSource.yandex);
    // Ловушка: 'ytm_' начинается не с 'ym_', но при обратном порядке проверок
    // легко получить Яндекс вместо YouTube Music.
    expect(MusicSource.fromId('ytm_abc'), MusicSource.ytmusic);
    expect(MusicSource.fromId('local-file'), MusicSource.local);
  });

  test('числовой id вытаскивается из сквозного', () {
    expect(scNumericId(scTrackId(88335161)), 88335161);
    expect(scNumericId(scArtistId(42)), 42);
    expect(scNumericId(scSetId(7, isAlbum: true)), 7);
    // Мусор не роняет провайдер, а просто ничего не находит.
    expect(scNumericId('sc_artist_нечисло'), 0);
  });

  test('трек: длительность, пустые строки в null, сырьё для стрима', () {
    final raw = mapRawTrack({
      'id': 10,
      'title': 'Song',
      'duration': 185000,
      'genre': 'House',
      'label_name': '',
      'user': {'id': 5, 'username': 'Nick'},
      'media': {
        'transcodings': [
          {'url': 'https://x'},
        ],
      },
    });
    final track = trackFromSc(raw);

    expect(track.id, 'sc_10');
    expect(track.source, MusicSource.soundcloud);
    expect(track.duration, const Duration(milliseconds: 185000));
    // Пустые поля SC («», как у label_name) не должны утекать в UI строками.
    expect(track.publisher, isNull);
    expect(track.album, isNull);
    expect(track.genres, ['house']);
    expect(track.artistId, 'sc_artist_5');
    // Без media резолвить стрим будет нечем.
    expect(track.sourceData, isNotNull);
  });

  test('альбом: счётчик 0 у SC значит «неизвестно», а не ноль треков', () {
    final withCount = setFromSc(
      mapRawPlaylist({'id': 1, 'title': 'A', 'track_count': 14}),
      isAlbum: true,
    );
    expect(withCount.trackCount, 14);
    expect(withCount.isAlbum, isTrue);
    expect(withCount.id, 'sc_album_1');

    // У SC отсутствующий track_count приходит нулём; «0 треков» под альбомом
    // хуже, чем ничего.
    final noCount = setFromSc(
      mapRawPlaylist({'id': 2, 'title': 'B'}),
      isAlbum: false,
    );
    expect(noCount.trackCount, isNull);
    expect(noCount.duration, isNull);
    expect(noCount.id, 'sc_playlist_2');
  });

  test('артист: username в name, full_name в fullName', () {
    final artist = artistFromSc(
      mapRawArtist({
        'id': 3,
        'username': 'skrillex',
        'full_name': 'Sonny Moore',
        'followers_count': 6700572,
      }),
    );
    expect(artist.id, 'sc_artist_3');
    expect(artist.name, 'skrillex');
    expect(artist.fullName, 'Sonny Moore');
    expect(artist.followers, 6700572);
  });

  test('пустой ScPage не ломает маппинг', () {
    const page = ScPage<ScRawTrack>(items: [], hasMore: false);
    expect(page.items.map(trackFromSc).toList(), isEmpty);
  });
}
