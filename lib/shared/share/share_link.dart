/// Ссылка «Поделиться» и то, что уходит в карточку — порт десктопного
/// `shared/ui/shareStore.ts`.
///
/// Ссылка ведёт не на площадку, а на страницу-посредник Bloom: она получает всё
/// нужное параметрами (тип, id, название, артист, permalink, обложка) и уже сама
/// решает, куда отправить открывшего. Поэтому здесь нет ветвления по площадкам —
/// параметры у всех одни и те же, как на ПК.
///
/// Файл чистый (ни виджетов, ни каналов) — карточка и шторка живут в
/// `share_sheet.dart`.
library;

import '../../core/entities/entities.dart';

/// Что именно отдаём. Порт `ShareKind`.
enum ShareKind {
  track('track'),
  artist('artist'),
  album('album'),
  playlist('playlist');

  const ShareKind(this.param);

  /// Значение параметра `type` в ссылке.
  final String param;
}

const String kShareBase = 'https://bxzlik.github.io/bloom-link/share/';

/// Сырой id площадки из сквозного (`sc_123` → `123`) — порт `rawScId`.
/// Префиксы остальных площадок страница-посредник разбирает сама, и трогать их
/// нельзя: `ym_artist_5` без префикса перестанет быть артистом Яндекса.
String rawShareId(String id) =>
    id.startsWith('sc_') ? id.substring('sc_'.length) : id;

/// Обложка в ссылку идёт только сетевая: своя (`local:…`) за пределами телефона
/// не откроется. Та же проверка `startsWith('http')`, что на ПК.
String? _linkCover(String? cover) =>
    cover != null && cover.startsWith('http') ? cover : null;

/// Собрать ссылку. У артиста имя едет в `name`, у остальных — в `title`
/// с отдельным `artist`; на ПК ровно это же ветвление.
String buildShareUrl({
  required ShareKind kind,
  String? id,
  String? title,
  String? artist,
  String? permalink,
  String? cover,
}) {
  final params = <String, String>{
    'type': kind.param,
    'id': id ?? '',
    if (kind == ShareKind.artist)
      'name': title ?? ''
    else ...{
      'title': title ?? '',
      'artist': artist ?? '',
    },
    'permalink': permalink ?? '',
  };
  final linkCover = _linkCover(cover);
  if (linkCover != null) params['cover'] = linkCover;
  return '$kShareBase?${Uri(queryParameters: params).query}';
}

/// Ссылка на профиль — порт `onCopy` из десктопной `ProfileShareModal`.
///
/// Отдельной функцией, а не пятым значением [ShareKind]: у профиля нет ни id,
/// ни permalink, зато есть свои поля со статистикой — общий [buildShareUrl] к
/// ним не сводится.
///
/// [avatar] в ссылку попадает только сетевой, и на телефоне это значит «никогда»:
/// картинки профиля здесь всегда свои, файлом. Проверка всё равно стоит — ровно
/// та же, что на ПК, и ссылка не потащит наружу `local:`.
String buildProfileShareUrl({
  required String name,
  required int tracks,
  required int plays,
  required String time,
  String? favArtist,
  String? bio,
  String? avatar,
}) {
  final params = <String, String>{
    'type': 'profile',
    'name': name,
    'tracks': '$tracks',
    'plays': '$plays',
    'time': time,
  };
  if (favArtist != null && favArtist.isNotEmpty) params['artist'] = favArtist;
  final linkAvatar = _linkCover(avatar);
  if (linkAvatar != null) params['avatar'] = linkAvatar;
  if (bio != null && bio.isNotEmpty) params['bio'] = bio;
  return '$kShareBase?${Uri(queryParameters: params).query}';
}

/// Готовые данные карточки — порт `ShareData`.
class ShareTarget {
  const ShareTarget({
    required this.kind,
    required this.title,
    required this.artist,
    required this.cover,
    required this.url,
  });

  /// Трек. [Track.url] у нас — это и есть permalink площадки.
  factory ShareTarget.track(Track track) => ShareTarget(
    kind: ShareKind.track,
    title: track.name,
    artist: track.artist,
    cover: track.cover,
    url: buildShareUrl(
      kind: ShareKind.track,
      id: rawShareId(track.id),
      title: track.name,
      artist: track.artist,
      permalink: track.url,
      cover: track.cover,
    ),
  );

  /// Артист: подписи под именем на карточке нет — на ПК в `artist` уходит
  /// пустая строка.
  factory ShareTarget.artist(Artist artist) => ShareTarget(
    kind: ShareKind.artist,
    title: artist.name,
    artist: '',
    cover: artist.avatar,
    url: buildShareUrl(
      kind: ShareKind.artist,
      id: rawShareId(artist.id),
      title: artist.name,
      permalink: artist.permalink,
      cover: artist.avatar,
    ),
  );

  /// Альбом или плейлист площадки — различаются только флагом [Playlist.isAlbum],
  /// как и везде у нас. Подпись — владелец списка (`ownerName` на ПК).
  factory ShareTarget.set(Playlist set) {
    final kind = set.isAlbum ? ShareKind.album : ShareKind.playlist;
    final owner = set.ownerName ?? '';
    return ShareTarget(
      kind: kind,
      title: set.title,
      artist: owner,
      cover: set.cover,
      url: buildShareUrl(
        kind: kind,
        id: rawShareId(set.id),
        title: set.title,
        artist: owner,
        permalink: set.sourceUrl,
        cover: set.cover,
      ),
    );
  }

  final ShareKind kind;

  /// Название трека/альбома/плейлиста либо имя артиста.
  final String title;

  /// Подпись под названием; у артиста пустая.
  final String artist;
  final String? cover;

  /// Готовая ссылка — то, что уходит в буфер обмена.
  final String url;
}
