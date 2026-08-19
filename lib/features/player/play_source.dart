/// Источник очереди: откуда набрано то, что играет, — раздел библиотеки,
/// альбом или плейлист площадки, страница артиста, выдача поиска, витрина
/// главной, одиночный трек.
///
/// Порт десктопного `PlaySource` (`features/player/model/queueStore.ts`): там
/// он рисуется пилюлей в шапке очереди (`#qpSourcePill`), у нас — пилюлей в
/// шапке полноэкранного плеера ([SourcePill]).
///
/// Отличие от десктопа: у разделов библиотеки храним ТОЛЬКО id, а подпись и
/// картинку пилюля берёт из библиотеки на месте. Плейлист можно переименовать
/// и сменить ему обложку прямо во время воспроизведения — снимок имени в
/// очереди после этого врал бы. У сетов площадок наоборот: снимок обязателен,
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
    switch (json['kind']) {
      case 'lib':
        final id = json['id'];
        return id is String ? LibSource(id) : null;
      case 'set':
        final set = Playlist.fromJson(json['set']);
        return set == null ? null : SetSource(set);
      case 'artist':
        final artist = Artist.fromJson(json['artist']);
        return artist == null ? null : ArtistSource(artist);
      case 'wave':
        final label = json['label'];
        if (label is! String) return null;
        return WaveSource(
          label: label,
          mode:
              WaveMode.values
                  .where((m) => m.name == json['mode'])
                  .firstOrNull ??
              WaveMode.personal,
        );
      case 'plain':
        final id = json['id'];
        final label = json['label'];
        if (id is! String || label is! String) return null;
        return PlainSource(
          id: id,
          label: label,
          icon: PlainSourceIcon.values.firstWhere(
            (i) => i.name == json['icon'],
            orElse: () => PlainSourceIcon.note,
          ),
          cover: json['cover'] as String?,
        );
      default:
        return null;
    }
  }
}

/// Раздел библиотеки: `all` / `fav` / `history` либо пользовательский плейлист
/// (`pl_…`). Открывается маршрутом `/library/list/:id`.
final class LibSource extends PlaySource {
  const LibSource(this.listId);

  final String listId;

  @override
  String get id => listId;

  @override
  Map<String, dynamic> toJson() => {'kind': 'lib', 'id': listId};
}

/// Альбом или плейлист площадки — тот самый [Playlist], которым открывали
/// страницу: по нему пилюля и вернёт на неё.
final class SetSource extends PlaySource {
  const SetSource(this.set);

  final Playlist set;

  @override
  String get id => set.id;

  @override
  Map<String, dynamic> toJson() => {'kind': 'set', 'set': set.toJson()};
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
    'artist': artist.toJson(),
  };
}

/// Волна: очередь набирает не список, а подбор — свой движок по SoundCloud
/// либо станция Яндекса. Своей страницы у неё нет, поэтому [id] ни с какой
/// плиткой не совпадает; [mode] нужен, чтобы после перезапуска подхватить
/// сеанс тем же способом, каким он начинался.
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
    'label': label,
    'mode': mode.name,
  };
}

/// Значок источника, у которого своей картинки нет.
enum PlainSourceIcon { search, clock, chart, note }

/// Источник без своей страницы: выдача поиска, витрина главной, «Недавно
/// слушали», одиночный трек. Подпись приходит уже переведённой — переводить её
/// некому: пилюля рисуется через сутки после того, как трек поставили.
final class PlainSource extends PlaySource {
  const PlainSource({
    required this.id,
    required this.label,
    required this.icon,
    this.cover,
  });

  /// Выдача поиска. [label] — «Поиск: запрос».
  PlainSource.search(String query, String label)
    : this(id: 'search:$query', label: label, icon: PlainSourceIcon.search);

  /// Одиночный трек, запущенный вне списка (топ профиля, меню трека).
  PlainSource.single(Track track)
    : this(
        id: 'single:${track.id}',
        label: track.name,
        icon: PlainSourceIcon.note,
        cover: track.cover,
      );

  @override
  final String id;

  final String label;
  final PlainSourceIcon icon;

  /// Своя картинка, если есть (обложка одиночного трека).
  final String? cover;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'plain',
    'id': id,
    'label': label,
    'icon': icon.name,
    if (cover != null) 'cover': cover,
  };
}
