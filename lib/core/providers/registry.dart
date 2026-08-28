/// Реестр музыкальных провайдеров — порт
/// `src/features/providers/model/registry.ts`.
///
/// Площадка регистрируется один раз при старте, UI спрашивает у реестра.
/// Уровнем ниже лежит резолв стрима (`MusicProvider.resolveStream`): там «как
/// достать звук», здесь — «как искать и отдавать сущности».
library;

import 'dart:async';

import '../entities/entities.dart';
import 'music_provider.dart';

/// Сентинел «все источники» для переключателя площадки.
const String kAllProviders = 'all';

class ProviderRegistry {
  final List<MusicProvider> _providers = [];

  /// Зарегистрировать (или заменить по id).
  void register(MusicProvider p) {
    final i = _providers.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      _providers[i] = p;
    } else {
      _providers.add(p);
    }
  }

  /// Включённые провайдеры, в порядке регистрации.
  List<MusicProvider> get enabled =>
      _providers.where((p) => p.isEnabled).toList();

  /// Все зарегистрированные, включая выключённые — для переключателя площадки,
  /// где они показываются всегда, даже ненастроенные.
  List<MusicProvider> get all => List.unmodifiable(_providers);

  MusicProvider? byId(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Кого опрашивать: конкретную площадку либо все включённые.
  ///
  /// Явно выбранную площадку уважаем, даже если она «выключена» — переключатель
  /// показывает все, и провайдер сам вернёт результат или ошибку. Не нашли
  /// вовсе (протухший id из настроек) — фолбэк на включённые.
  List<MusicProvider> _pick(String? providerId) {
    final onlyId = (providerId != null && providerId != kAllProviders)
        ? providerId
        : null;
    final enabledNow = enabled;
    if (onlyId == null) return enabledNow;
    final picked = all.where((p) => p.id == onlyId).toList();
    return picked.isEmpty ? enabledNow : picked;
  }

  /// Искать по всем включённым площадкам параллельно и слить выдачу.
  /// Упавший провайдер просто не вносит вклад.
  ///
  /// Пер-провайдерный таймаут: одна медленная площадка (SoundCloud во время
  /// скрейпа client_id) не должна держать всю выдачу. По таймауту вклад пустой,
  /// как при ошибке. При поиске по одному источнику ждать нечего — даём больше.
  Future<SearchResults> searchAll(
    String query, {
    String? providerId,
    SearchSort sort = SearchSort.relevance,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return SearchResults.empty;

    final providers = _pick(providerId);
    final onlyOne = providers.length == 1;
    final timeout = Duration(seconds: onlyOne ? 30 : 12);

    final responses = await Future.wait(
      providers.map(
        (p) => p
            .search(q, sort: sort)
            .timeout(timeout)
            .then<SearchResults?>((v) => v, onError: (_) => null),
      ),
    );

    final artists = <Artist>[];
    final playlists = <Playlist>[];
    final albums = <Playlist>[];
    final tracks = <Track>[];
    var hasMore = false;
    for (final r in responses) {
      if (r == null) continue;
      artists.addAll(r.artists);
      playlists.addAll(r.playlists);
      albums.addAll(r.albums);
      tracks.addAll(r.tracks);
      if (r.tracksHasMore) hasMore = true;
    }
    return SearchResults(
      artists: artists,
      playlists: playlists,
      albums: albums,
      tracks: tracks,
      tracksHasMore: hasMore,
    );
  }

  /// Догрузить ещё треки по всем (или выбранной) площадкам.
  Future<TrackPage> loadMoreTracksAll(
    String query,
    int offset, {
    String? providerId,
    SearchSort sort = SearchSort.relevance,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const TrackPage();

    final responses = await Future.wait(
      _pick(providerId).map(
        (p) => p
            .loadMoreTracks(q, offset, sort: sort)
            .then<TrackPage?>((v) => v, onError: (_) => null),
      ),
    );

    final tracks = <Track>[];
    var hasMore = false;
    for (final r in responses) {
      if (r == null) continue;
      tracks.addAll(r.tracks);
      if (r.hasMore) hasMore = true;
    }
    return TrackPage(tracks: tracks, hasMore: hasMore);
  }

  /// Резолв вставленной ссылки: опрашиваем площадки, первый непустой ответ
  /// выигрывает.
  Future<({MusicProvider provider, ResolvedUrl resolved})?> resolveUrlAny(
    String url,
  ) async {
    for (final p in enabled) {
      try {
        final resolved = await p.resolveUrl(url);
        if (resolved != null) return (provider: p, resolved: resolved);
      } catch (_) {
        // пробуем следующую площадку
      }
    }
    return null;
  }

  /// Площадка сущности по префиксу её сквозного id.
  MusicProvider? forEntity(String entityId) =>
      byId(MusicSource.fromId(entityId).id);
}
