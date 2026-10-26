/// Источник очереди: откуда набрано то, что играет, — раздел библиотеки,
/// альбом или плейлист площадки, страница артиста, выдача поиска, витрина
/// главной, одиночный трек.
///
/// В сессии лежит картой того же вида, что `Player.source` ПК:
/// `{kind, id, name, cover, …}` — `playlist` (свои списки, `lib`/`fav`),
/// `history`, `collection`, `artist`, `wave` (+ `mode`), `search`, `track` и
/// витрины. Неизвестный вид читается как [PlainSource] по `name`.
///
/// Отличие от ПК: у разделов библиотеки в памяти храним ТОЛЬКО id, а подпись и
/// картинку пилюля берёт из библиотеки на месте — плейлист могут переименовать
/// прямо во время воспроизведения. Имя и обложку в карту дописывает сессия при
/// записи (`session_store.dart`). У сетов площадок наоборот: снимок обязателен,
/// перечитать альбом SoundCloud без сети неоткуда.
library;

import '../../core/entities/entities.dart';
import '../wave/wave_types.dart';

sealed class PlaySource {
  const PlaySource();

  /// Ключ «играет ли ЭТОТ список» — по нему плитка сета и строка списка
  /// показывают эквалайзер (`SetEqualizer`). У всего, чему плитки нет (поиск,
  /// витрина, одиночный трек), он просто ни с чем не совпадает.
  String get id;

  Map<String, dynamic> toJson();

  static PlaySource? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    final id = json['id'] is String ? json['id'] as String : '';
    final name = json['name'] is String ? json['name'] as String : '';
    final cover = switch (json['cover']) {
      final String c when c.isNotEmpty => c,
      _ => null,
    };
    switch (kind) {
      case 'playlist':
        if (id.isEmpty) return null;
        return LibSource(id == 'lib' ? 'all' : id);
      case 'history':
        return const LibSource('history');
      case 'collection':
        if (id.isEmpty) return null;
        return SetSource(
          Playlist(
            id: id,
            title: name,
            cover: cover,
            source: MusicSource.fromId(id),
            isAlbum: json['album'] == true || id.contains(':album:'),
          ),
        );
      case 'artist':
        if (id.isEmpty) return null;
        return ArtistSource(
          Artist(
            id: id,
            name: name,
            source: MusicSource.fromId(id),
            avatar: cover,
          ),
        );
      case 'wave':
        return WaveSource(
          label: name,
          mode:
              WaveMode.values
                  .where((m) => m.name == json['mode'])
                  .firstOrNull ??
              WaveMode.personal,
        );
      case final String kind when kind.isNotEmpty:
        return PlainSource(
          id: id.isEmpty ? kind : id,
          label: name,
          cover: cover,
        );
      default:
        return null;
    }
  }
}

/// Раздел библиотеки: `all` / `fav` / `history` либо пользовательский плейлист.
/// Открывается маршрутом `/library/list/:id`. В карте ПК «Все треки» — `lib`.
final class LibSource extends PlaySource {
  const LibSource(this.listId);

  final String listId;

  @override
  String get id => listId;

  @override
  Map<String, dynamic> toJson() => switch (listId) {
    'all' => {'kind': 'playlist', 'id': 'lib', 'glyph': 'note'},
    'fav' => {'kind': 'playlist', 'id': 'fav', 'glyph': 'heart'},
    'history' => {'kind': 'history'},
    _ => {'kind': 'playlist', 'id': listId},
  };
}

/// Альбом или плейлист площадки — тот самый [Playlist], которым открывали
/// страницу: по нему пилюля и вернёт на неё.
final class SetSource extends PlaySource {
  const SetSource(this.set);

  final Playlist set;

  @override
  String get id => set.id;

  /// `album` — мобильный ключ (ПК его не пишет): страница альбома и плейлиста
  /// грузится разными запросами, а у SoundCloud по id их не различить.
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'collection',
    'id': set.id,
    'name': set.title,
    'cover': set.cover ?? '',
    if (set.isAlbum) 'album': true,
  };
}

/// Страница артиста: «Воспроизвести», карусель популярных, список треков.
final class ArtistSource extends PlaySource {
  const ArtistSource(this.artist);

  final Artist artist;

  @override
  String get id => artist.id;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'artist',
    'id': artist.id,
    'name': artist.name,
    'cover': artist.avatar ?? '',
    'round': true,
  };
}

/// Волна: очередь набирает не список, а подбор. Своей страницы у неё нет,
/// поэтому [id] ни с какой плиткой не совпадает; [mode] нужен, чтобы после
/// перезапуска подхватить сеанс тем же способом, каким он начинался.
///
/// Подпись приходит уже переведённой — переводить её потом некому: пилюлю
/// рисуют по снимку, снятому суткам раньше.
final class WaveSource extends PlaySource {
  const WaveSource({required this.label, required this.mode});

  final String label;
  final WaveMode mode;

  @override
  String get id => 'wave:${mode.name}';

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'wave',
    'mode': mode.name,
    'name': label,
    'glyph': 'wave',
  };
}

/// Значок источника, у которого своей картинки нет.
enum PlainSourceIcon { search, clock, chart, note }

/// Источник без своей страницы: выдача поиска, витрина главной, «Недавно
/// слушали», одиночный трек. Подпись приходит уже переведённой — переводить её
/// некому: пилюля рисуется через сутки после того, как трек поставили.
///
/// Вид (`kind` карты ПК) — начало [id] до двоеточия: `search:…`, `wrapped:…`,
/// `discover:…`, `forYou`; одиночный трек — `track`, как на ПК.
final class PlainSource extends PlaySource {
  const PlainSource({required this.id, required this.label, this.cover});

  /// Выдача поиска. [label] — «Поиск: запрос».
  PlainSource.search(String query, String label)
    : this(id: 'search:$query', label: label);

  /// Одиночный трек, запущенный вне списка (топ профиля, меню трека).
  PlainSource.single(Track track)
    : this(id: 'track:${track.id}', label: track.name, cover: track.cover);

  @override
  final String id;

  final String label;

  /// Своя картинка, если есть (обложка одиночного трека).
  final String? cover;

  String get kind => id.split(':').first;

  PlainSourceIcon get icon => switch (kind) {
    'search' => PlainSourceIcon.search,
    'recent' || 'history' => PlainSourceIcon.clock,
    'discover' || 'wrapped' || 'chart' => PlainSourceIcon.chart,
    _ => PlainSourceIcon.note,
  };

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'name': label,
    'cover': cover ?? '',
  };
}
