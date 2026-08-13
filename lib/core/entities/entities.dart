/// Общие сущности всех площадок — порт `src/entities/{track,artist,playlist}`
/// из десктопного Bloom.
///
/// Смысл: провайдер приводит свою выдачу К ЭТИМ типам, и весь UI (поиск,
/// страницы, плеер) о площадке ничего не знает. Добавить площадку = написать
/// провайдер, экраны не трогаем.
///
/// Отличия от десктопа, сделанные осознанно:
/// - `duration` здесь [Duration], а не строка «m:ss». На десктопе это поле
///   названо `dur` и хранит уже отформатированную строку — там же в
///   комментарии помечено как историческое. Форматируем при отрисовке.
/// - вместо плоских флагов `_sc`/`_ym`/`_ytm` и россыпи полей вроде `scMedia`
///   — [Track.source] и непрозрачный [Track.sourceData]: сырьё площадки,
///   которое нужно ей самой (у SoundCloud там `media.transcodings` для
///   резолва стрима).
library;

enum MusicSource {
  local('local', 'Локальные', ''),
  soundcloud('soundcloud', 'SoundCloud', 'sc_'),
  ytmusic('ytmusic', 'YouTube Music', 'ytm_'),
  yandex('yandex', 'Яндекс.Музыка', 'ym_');

  const MusicSource(this.id, this.label, this.prefix);

  /// Технический id источника. В UI не показывается.
  final String id;

  /// Человекочитаемая метка. Для площадок это бренд и перевода не требует;
  /// переводятся только «Локальные» и «Яндекс.Музыка» — см. `label10n` в
  /// `core/l10n/source_label.dart`, где нужен язык.
  final String label;

  /// Префикс сквозных id сущностей этой площадки.
  final String prefix;

  /// Площадка по ПРЕФИКСУ сквозного id — там, где источник не сохранён
  /// отдельным полем (порт `artistSourceFromId`).
  static MusicSource fromId(String id) {
    // Порядок важен: 'ytm_' проверяется до 'ym_', иначе не совпадёт ни разу.
    for (final s in [
      MusicSource.ytmusic,
      MusicSource.yandex,
      MusicSource.soundcloud,
    ]) {
      if (id.startsWith(s.prefix)) return s;
    }
    return MusicSource.local;
  }
}

class Track {
  /// Сквозной id с префиксом источника («sc_123»).
  final String id;

  /// Заголовок трека.
  final String name;

  /// Отображаемое имя артиста (может быть «Artist A, Artist B»).
  final String artist;
  final Duration duration;
  final String? cover;
  final MusicSource source;

  final String? album;
  final String? year;
  final String? publisher;
  final String? description;
  final bool explicit;
  final List<String> genres;

  /// Ссылка на трек у площадки (permalink).
  final String? url;

  /// Сквозной id артиста — чтобы открыть его страницу по клику на имя, минуя
  /// резолв по имени.
  final String? artistId;
  final String? artistAvatar;
  final bool artistVerified;

  /// Артист из `publisher_metadata` — иногда точнее имени аккаунта.
  final String? creditedArtist;

  /// Глобальное число прослушиваний у площадки.
  final int? playCount;

  /// Сырьё площадки для [MusicProvider.resolveStream] и скачивания.
  final Map<String, dynamic>? sourceData;

  const Track({
    required this.id,
    required this.name,
    required this.artist,
    required this.duration,
    required this.source,
    this.cover,
    this.album,
    this.year,
    this.publisher,
    this.description,
    this.explicit = false,
    this.genres = const [],
    this.url,
    this.artistId,
    this.artistAvatar,
    this.artistVerified = false,
    this.creditedArtist,
    this.playCount,
    this.sourceData,
  });

  /// Сериализация для локальной библиотеки. `sourceData` пишется как есть —
  /// без него сохранённый трек не заиграет: у SoundCloud там transcodings, из
  /// которых резолвится стрим.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'artist': artist,
    'durationMs': duration.inMilliseconds,
    'source': source.id,
    if (cover != null) 'cover': cover,
    if (album != null) 'album': album,
    if (year != null) 'year': year,
    if (publisher != null) 'publisher': publisher,
    if (description != null) 'description': description,
    if (explicit) 'explicit': true,
    if (genres.isNotEmpty) 'genres': genres,
    if (url != null) 'url': url,
    if (artistId != null) 'artistId': artistId,
    if (artistAvatar != null) 'artistAvatar': artistAvatar,
    if (artistVerified) 'artistVerified': true,
    if (creditedArtist != null) 'creditedArtist': creditedArtist,
    if (playCount != null) 'playCount': playCount,
    if (sourceData != null) 'sourceData': sourceData,
  };

  static Track? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return Track(
      id: id,
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      source: MusicSource.fromId(id),
      cover: json['cover'] as String?,
      album: json['album'] as String?,
      year: json['year'] as String?,
      publisher: json['publisher'] as String?,
      description: json['description'] as String?,
      explicit: json['explicit'] == true,
      genres:
          (json['genres'] as List?)?.whereType<String>().toList() ?? const [],
      url: json['url'] as String?,
      artistId: json['artistId'] as String?,
      artistAvatar: json['artistAvatar'] as String?,
      artistVerified: json['artistVerified'] == true,
      creditedArtist: json['creditedArtist'] as String?,
      playCount: (json['playCount'] as num?)?.toInt(),
      sourceData: (json['sourceData'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

class Artist {
  final String id;
  final String name;
  final String? avatar;
  final bool verified;
  final String? permalink;
  final MusicSource source;

  // Поля страницы артиста — заполняются провайдером в getArtist.
  final int? followers;

  /// Полное имя — подзаголовок профиля рядом с подписчиками.
  final String? fullName;
  final String? description;
  final String? website;
  final List<String> genres;

  /// Баннер для фона hero.
  final String? bannerUrl;

  const Artist({
    required this.id,
    required this.name,
    required this.source,
    this.avatar,
    this.verified = false,
    this.permalink,
    this.followers,
    this.fullName,
    this.description,
    this.website,
    this.genres = const [],
    this.bannerUrl,
  });

  Artist copyWith({
    int? followers,
    String? fullName,
    String? description,
    String? website,
    String? bannerUrl,
    String? avatar,
  }) => Artist(
    id: id,
    name: name,
    source: source,
    avatar: avatar ?? this.avatar,
    verified: verified,
    permalink: permalink,
    followers: followers ?? this.followers,
    fullName: fullName ?? this.fullName,
    description: description ?? this.description,
    website: website ?? this.website,
    genres: genres,
    bannerUrl: bannerUrl ?? this.bannerUrl,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (avatar != null) 'avatar': avatar,
    if (verified) 'verified': true,
    if (permalink != null) 'permalink': permalink,
    if (followers != null) 'followers': followers,
    if (fullName != null) 'fullName': fullName,
  };

  static Artist? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return Artist(
      id: id,
      name: json['name'] as String? ?? '',
      source: MusicSource.fromId(id),
      avatar: json['avatar'] as String?,
      verified: json['verified'] == true,
      permalink: json['permalink'] as String?,
      followers: (json['followers'] as num?)?.toInt(),
      fullName: json['fullName'] as String?,
    );
  }
}

/// Плейлист И альбом — одна сущность: рисуются одной карточкой, различаются
/// флагом [isAlbum].
class Playlist {
  final String id;
  final String title;
  final String? cover;

  /// Число треков. Именно nullable: у части площадок его нет вовсе, и «0» вместо
  /// «неизвестно» показывало «0 треков» у альбома с четырнадцатью.
  final int? trackCount;
  final String? ownerName;
  final String? ownerAvatar;

  /// Год выпуска (у альбомов; у плейлистов чаще пусто).
  final String? year;
  final MusicSource source;
  final bool isAlbum;

  /// Длительность целиком, если площадка её отдаёт.
  final Duration? duration;

  /// URL/permalink для повторной загрузки из источника.
  final String? sourceUrl;

  const Playlist({
    required this.id,
    required this.title,
    required this.source,
    this.cover,
    this.trackCount,
    this.ownerName,
    this.ownerAvatar,
    this.year,
    this.isAlbum = false,
    this.duration,
    this.sourceUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (cover != null) 'cover': cover,
    if (trackCount != null) 'trackCount': trackCount,
    if (ownerName != null) 'ownerName': ownerName,
    if (ownerAvatar != null) 'ownerAvatar': ownerAvatar,
    if (year != null) 'year': year,
    if (isAlbum) 'isAlbum': true,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
  };

  static Playlist? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return Playlist(
      id: id,
      title: json['title'] as String? ?? '',
      source: MusicSource.fromId(id),
      cover: json['cover'] as String?,
      trackCount: (json['trackCount'] as num?)?.toInt(),
      ownerName: json['ownerName'] as String?,
      ownerAvatar: json['ownerAvatar'] as String?,
      year: json['year'] as String?,
      isAlbum: json['isAlbum'] == true,
      sourceUrl: json['sourceUrl'] as String?,
    );
  }
}
