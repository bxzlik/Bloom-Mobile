/// Импорт по вставленной ссылке — порт десктопного `importFromUrl.ts`.
///
/// Разрешены только КОЛЛЕКЦИИ: плейлист, альбом и лайки профиля. Ссылка на
/// одиночный трек или артиста отклоняется — на ПК так же: импортировать «в
/// плейлист» одну песню незачем, для этого есть меню трека.
///
/// Импортированная коллекция становится источником «Обновить треки» — и у
/// созданного плейлиста, и у того, в который импортировали (привязок может быть
/// сколько угодно, с разных площадок). Затереть этим ничего нельзя: обновление
/// только подмешивает новые треки наверх (`refreshPlaylistFromSource`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../providers/soundcloud/sc_provider.dart' show scLikesOf;

/// Куда импортировать.
enum ImportTargetKind { create, library, favorites, playlist }

class ImportTarget {
  const ImportTarget(this.kind, {this.playlistId});

  const ImportTarget.create() : this(ImportTargetKind.create);

  final ImportTargetKind kind;

  /// id плейлиста для [ImportTargetKind.playlist].
  final String? playlistId;
}

/// Что нашлось по ссылке: коллекция как источник и её треки.
class ResolvedCollection {
  const ResolvedCollection({required this.source, required this.tracks});

  final PlSourceRef source;
  final List<Track> tracks;

  String get title => source.title;
  String? get cover => source.cover.isEmpty ? null : source.cover;
}

class ImportResult {
  const ImportResult({
    required this.title,
    required this.added,
    required this.total,
    this.createdId,
  });

  final String title;

  /// Сколько треков реально прибавилось (без дублей).
  final int added;

  /// Сколько треков было в источнике.
  final int total;

  /// id созданного плейлиста — только для [ImportTargetKind.create].
  final String? createdId;
}

/// Почему ссылка не импортировалась. Причина, а не готовая фраза: текст знает
/// только UI, где есть язык интерфейса (`describeImportFailure`).
enum ImportFailure { unrecognized, unsupported, noTracks, playlistGone }

/// Отдельный тип, чтобы не показывать в тосте сырой текст сетевой ошибки.
class ImportException implements Exception {
  const ImportException(this.reason);
  final ImportFailure reason;

  @override
  String toString() => 'ImportException(${reason.name})';
}

/// Причина отказа импорта — фразой.
String describeImportFailure(AppLocalizations l, ImportFailure reason) =>
    switch (reason) {
      ImportFailure.unrecognized => l.iuUnrecognized,
      ImportFailure.unsupported => l.iuOnlySupported,
      ImportFailure.noTracks => l.iuNoTracks,
      ImportFailure.playlistGone => l.iuPlaylistGone,
    };

/// Резолв ссылки в набор треков. Общая точка для импорта и «обновить треки».
Future<ResolvedCollection> resolveCollectionUrl(
  ProviderRegistry registry,
  String url,
) async {
  final found = await registry.resolveUrlAny(url.trim());
  if (found == null) {
    throw const ImportException(ImportFailure.unrecognized);
  }
  final link = url.trim();
  switch (found.resolved) {
    case ResolvedSet(playlist: final p):
      final content = p.isAlbum
          ? await found.provider.getAlbum(p.id)
          : await found.provider.getPlaylist(p.id);
      if (content == null) {
        throw const ImportException(ImportFailure.unrecognized);
      }
      // Название и обложку страница знает лучше, чем ссылка.
      final page = content.playlist;
      return ResolvedCollection(
        source: PlSourceRef.of(p).copyWith(
          url: link,
          title: page.title.isEmpty ? null : page.title,
          owner: page.ownerName,
          cover: page.cover,
        ),
        tracks: content.tracks,
      );
    case ResolvedProfile(:final profile):
      // Ссылка на аккаунт — его лайки, коллекцией `sc:likes:<id>`.
      return ResolvedCollection(
        source: PlSourceRef.of(
          scLikesOf(profile.artist, likesTitle(profile.artist.name)),
        ).copyWith(url: link),
        tracks: profile.likes,
      );
    case ResolvedTrack() || ResolvedArtist():
      throw const ImportException(ImportFailure.unsupported);
  }
}

/// «Лайки · имя» — название лайков аккаунта, на языке, что стоит сейчас.
String likesTitle(String name) =>
    globalL10n?.iuLikesTitle(name) ?? 'Likes · $name';

/// Треки привязанной коллекции — по её id у её площадки, как на ПК
/// (`Provider::collection`). `null` — площадки нет, она выключена или
/// коллекция не нашлась.
Future<List<Track>?> fetchSource(
  ProviderRegistry registry,
  PlSourceRef source,
) async {
  final p = registry.byId(MusicSource.fromCode(source.provider).id);
  if (p == null || !p.isEnabled) return null;
  final content = source.isAlbum
      ? await p.getAlbum(source.id)
      : await p.getPlaylist(source.id);
  return content?.tracks;
}

/// Импортировать ссылку в выбранную цель. Обёртка для UI.
Future<ImportResult> importFromUrl(
  WidgetRef ref,
  String url,
  ImportTarget target,
) => importUrlInto(
  ref.read(registryProvider),
  ref.read(libraryProvider.notifier),
  () => ref.read(libraryProvider),
  url,
  target,
);

/// То же самое без Riverpod-обвязки: реестр, контроллер и чтение состояния
/// приходят снаружи. Так импорт зовётся и из тестов.
Future<ImportResult> importUrlInto(
  ProviderRegistry registry,
  LibraryController library,
  LibraryState Function() read,
  String url,
  ImportTarget target,
) async {
  final source = await resolveCollectionUrl(registry, url);
  if (source.tracks.isEmpty) {
    throw const ImportException(ImportFailure.noTracks);
  }

  final tracks = source.tracks;

  switch (target.kind) {
    case ImportTargetKind.create:
      final playlist = library.createPlaylist(
        source.title,
        tracks: tracks,
        cover: source.cover,
        source: source.source,
      );
      return ImportResult(
        title: source.title,
        added: tracks.length,
        total: tracks.length,
        createdId: playlist.id,
      );

    case ImportTargetKind.library:
      return ImportResult(
        title: source.title,
        added: library.addToLibrary(tracks),
        total: tracks.length,
      );

    case ImportTargetKind.favorites:
      return ImportResult(
        title: source.title,
        added: library.addToFavorites(tracks),
        total: tracks.length,
      );

    case ImportTargetKind.playlist:
      final id = target.playlistId!;
      // Плейлист мог исчезнуть, пока тянулись треки: тогда добавлять некуда.
      final before = read().playlists.where((p) => p.id == id).firstOrNull;
      if (before == null) {
        throw const ImportException(ImportFailure.playlistGone);
      }
      final added = library.addTracksToPlaylist(id, tracks);
      // Коллекция становится ещё одним источником «Обновить треки» — если её
      // сюда ещё не привязывали.
      library.linkSource(id, source.source);
      return ImportResult(
        title: source.title,
        added: added,
        total: tracks.length,
        createdId: id,
      );
  }
}
