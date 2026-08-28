/// Недавнее в поиске: запросы и открытые карточки — порт десктопных
/// `bloom_recent_searches` и `bloom_recent_items`
/// (`features/search/model/store.ts`).
///
/// Запросы хранятся строками, а не `{q, ts}` как на ПК: время там нужно ровно
/// для того, чтобы в выпадающем списке смешать запросы с открытыми карточками
/// по свежести. У нас это два отдельных блока, каждый в своём порядке, и метка
/// времени осталась бы мёртвым полем.
///
/// Открытые лежат ЦЕЛЫМИ сущностями, а не десктопным снимком
/// `{kind, providerId, id, title, cover}`: `Track`/`Artist`/`Playlist` и так
/// умеют в JSON, и по такой записи страница открывается ровно тем же вызовом,
/// что из выдачи, — с обложкой, владельцем и `sourceData` для стрима, без
/// повторного запроса к площадке.
///
/// Это ИСТОРИЯ, а не настройка: в `kSettingsKeys` ключи не входят (на ПК они
/// тоже вне `SETTINGS_KEYS`), сброс настроек их не трогает — стирает только
/// полный сброс.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Сколько запросов помним — как `RS_MAX` на десктопе.
const int kRecentSearchMax = 8;

/// Сколько открытых карточек помним — как `RI_MAX` на десктопе.
const int kRecentItemMax = 12;

const String _key = 'recentSearches';
const String _itemsKey = 'recentItems';

final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

class RecentSearchesController extends Notifier<List<String>> {
  @override
  List<String> build() =>
      ref.read(jsonStoreProvider).readList(_key).whereType<String>().toList();

  void _save() => ref.read(jsonStoreProvider).write(_key, state);

  /// Запомнить запрос: наверх, без дублей, не длиннее [kRecentSearchMax].
  ///
  /// Повтор ищем без учёта регистра, но в списке остаётся ПОСЛЕДНЕЕ написание —
  /// так же, как на ПК: пользователь только что набрал именно его.
  void push(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final lower = q.toLowerCase();
    state = [
      q,
      ...state.where((x) => x.toLowerCase() != lower),
    ].take(kRecentSearchMax).toList();
    _save();
  }

  void remove(String query) {
    final next = state.where((x) => x != query).toList();
    if (next.length == state.length) return;
    state = next;
    _save();
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
    _save();
  }
}

/// Открытая из выдачи карточка. Треки сюда попадают тоже — на десктопе у
/// `RecentItem` для этого есть `kind: 'track'`, — но открытием считается
/// запуск: страницы у трека нет.
sealed class RecentItem {
  const RecentItem();

  /// Ключ дедупа. Тип в нём обязателен: id альбома и его заглавного трека у
  /// Яндекса различаются только префиксом сущности, а на SoundCloud плейлист и
  /// трек нумеруются каждый со своего счётчика и вполне могут совпасть.
  String get key;

  Map<String, dynamic> toJson();

  static RecentItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final data = json['data'];
    switch (json['kind']) {
      case 'track':
        final track = Track.fromJson(data);
        return track == null ? null : RecentTrack(track);
      case 'artist':
        final artist = Artist.fromJson(data);
        return artist == null ? null : RecentArtist(artist);
      case 'set':
        final set = Playlist.fromJson(data);
        return set == null ? null : RecentSet(set);
      default:
        return null;
    }
  }
}

final class RecentTrack extends RecentItem {
  const RecentTrack(this.track);

  final Track track;

  @override
  String get key => 'track:${track.id}';

  @override
  Map<String, dynamic> toJson() => {'kind': 'track', 'data': track.toJson()};
}

final class RecentArtist extends RecentItem {
  const RecentArtist(this.artist);

  final Artist artist;

  @override
  String get key => 'artist:${artist.id}';

  @override
  Map<String, dynamic> toJson() => {'kind': 'artist', 'data': artist.toJson()};
}

/// Альбом или плейлист — как и везде, одной сущностью с флагом
/// [Playlist.isAlbum].
final class RecentSet extends RecentItem {
  const RecentSet(this.set);

  final Playlist set;

  @override
  String get key => 'set:${set.id}';

  @override
  Map<String, dynamic> toJson() => {'kind': 'set', 'data': set.toJson()};
}

final recentItemsProvider =
    NotifierProvider<RecentItemsController, List<RecentItem>>(
      RecentItemsController.new,
    );

class RecentItemsController extends Notifier<List<RecentItem>> {
  @override
  List<RecentItem> build() => ref
      .read(jsonStoreProvider)
      .readList(_itemsKey)
      .map(RecentItem.fromJson)
      .nonNulls
      .toList();

  void _save() => ref.read(jsonStoreProvider).write(_itemsKey, [
    for (final item in state) item.toJson(),
  ]);

  /// Запомнить открытое: наверх, без дублей, не длиннее [kRecentItemMax].
  ///
  /// Свежая запись затирает прежнюю целиком: у карточки из выдачи полей
  /// обычно больше, чем у той же сущности, попавшей в список неделю назад.
  void push(RecentItem item) {
    state = [
      item,
      ...state.where((x) => x.key != item.key),
    ].take(kRecentItemMax).toList();
    _save();
  }

  void remove(RecentItem item) {
    final next = state.where((x) => x.key != item.key).toList();
    if (next.length == state.length) return;
    state = next;
    _save();
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
    _save();
  }
}
