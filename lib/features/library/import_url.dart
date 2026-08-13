/// Импорт по вставленной ссылке — порт десктопного `importFromUrl.ts`.
///
/// Разрешены только КОЛЛЕКЦИИ: плейлист, альбом и лайки профиля. Ссылка на
/// одиночный трек или артиста отклоняется — на ПК так же: импортировать «в
/// плейлист» одну песню незачем, для этого есть меню трека.
///
/// Источник (`sourceUrl`) привязывается только к СОЗДАННОМУ плейлисту. К
/// существующему — намеренно нет: обновление у нас заменяет состав целиком
/// (`refreshPlaylistFromSource`), и привязка стёрла бы всё, что в него добавили
/// руками. На ПК источников список и обновление подмешивает новое — там это
/// безопасно, у нас нет.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';

/// Куда импортировать.
enum ImportTargetKind { create, library, favorites, playlist }

class ImportTarget {
  const ImportTarget(this.kind, {this.playlistId});

  const ImportTarget.create() : this(ImportTargetKind.create);

  final ImportTargetKind kind;

  /// id плейлиста для [ImportTargetKind.playlist].
  final String? playlistId;
}

/// Что нашлось по ссылке.
class ResolvedCollection {
  const ResolvedCollection({
    required this.title,
    required this.tracks,
    this.cover,
    this.isAlbum = false,
  });

  final String title;
  final List<Track> tracks;
  final String? cover;
  final bool isAlbum;
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

/// Сообщение, которое видит пользователь. Отдельный тип, чтобы не показывать
/// в тосте сырой текст сетевой ошибки.
class ImportException implements Exception {
  const ImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Резолв ссылки в набор треков. Общая точка для импорта и «обновить треки».
Future<ResolvedCollection> resolveCollectionUrl(
  ProviderRegistry registry,
  String url,
) async {
  final found = await registry.resolveUrlAny(url.trim());
  if (found == null) {
    throw const ImportException('Не удалось распознать ссылку');
  }
  switch (found.resolved) {
    case ResolvedSet(playlist: final p):
      final content = p.isAlbum
          ? await found.provider.getAlbum(p.id)
          : await found.provider.getPlaylist(p.id);
      if (content == null) {
        throw const ImportException('Не удалось распознать ссылку');
      }
      return ResolvedCollection(
        title: content.playlist.title.isEmpty
            ? p.title
            : content.playlist.title,
        cover: content.playlist.cover ?? p.cover,
        tracks: content.tracks,
        isAlbum: p.isAlbum,
      );
    case ResolvedProfile(:final profile):
      // Ссылка на профиль — импортируем его лайки, как на ПК.
      return ResolvedCollection(
        title: 'Лайки · ${profile.artist.name}',
        cover: profile.artist.avatar,
        tracks: profile.likes,
      );
    case ResolvedTrack() || ResolvedArtist():
      throw const ImportException(
        'Можно вставить только плейлист, альбом или лайки',
      );
  }
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
    throw const ImportException('В этой ссылке нет треков');
  }

  final tracks = source.tracks;

  switch (target.kind) {
    case ImportTargetKind.create:
      final playlist = library.createPlaylist(
        source.title,
        tracks: tracks,
        cover: source.cover,
        sourceUrl: url.trim(),
        isAlbum: source.isAlbum,
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
      var added = 0;
      for (final track in tracks) {
        if (read().isFav(track.id)) continue;
        library.toggleFav(track);
        added++;
      }
      return ImportResult(
        title: source.title,
        added: added,
        total: tracks.length,
      );

    case ImportTargetKind.playlist:
      final id = target.playlistId!;
      // Плейлист мог исчезнуть, пока тянулись треки: тогда добавлять некуда.
      final before = read().playlists
          .where((p) => p.id == id)
          .map((p) => p.trackIds.toSet())
          .firstOrNull;
      if (before == null) {
        throw const ImportException('Плейлист больше не существует');
      }
      library.addTracksToPlaylist(id, tracks);
      return ImportResult(
        title: source.title,
        added: tracks.where((t) => !before.contains(t.id)).length,
        total: tracks.length,
        createdId: id,
      );
  }
}
