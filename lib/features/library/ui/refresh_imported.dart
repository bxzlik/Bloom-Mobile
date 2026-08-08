/// «Обновить импортированные» — перетянуть треки заново во все плейлисты,
/// у которых есть `sourceUrl`.
///
/// Сам импорт живёт в поиске (ссылка в поле поиска, как на десктопе); здесь
/// только повторный резолв уже сохранённой ссылки. Поэтому разбираем ровно те
/// же виды: коллекцию (плейлист/альбом) и аккаунт — у «Лайков <ник>» источником
/// записана ссылка на профиль.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/store/library_store.dart';

Future<void> refreshImported(BuildContext context, WidgetRef ref) async {
  final lib = ref.read(libraryProvider);
  final targets = lib.playlists.where((p) => p.sourceUrl != null).toList();
  final messenger = ScaffoldMessenger.of(context);

  if (targets.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Импортированных плейлистов нет')),
    );
    return;
  }

  messenger.showSnackBar(
    SnackBar(content: Text('Обновляю ${targets.length}…')),
  );

  final registry = ref.read(registryProvider);
  final controller = ref.read(libraryProvider.notifier);
  var updated = 0;
  for (final pl in targets) {
    try {
      final found = await registry.resolveUrlAny(pl.sourceUrl!);
      if (found == null) continue;
      final tracks = switch (found.resolved) {
        ResolvedSet(playlist: final p) =>
          (p.isAlbum
                  ? await found.provider.getAlbum(p.id)
                  : await found.provider.getPlaylist(p.id))
              ?.tracks,
        // Ссылка на аккаунт — плейлист собран из его лайков.
        ResolvedProfile(:final profile) => profile.likes,
        _ => null,
      };
      if (tracks == null || tracks.isEmpty) continue;
      controller.replacePlaylistTracks(pl.id, tracks);
      updated++;
    } catch (_) {
      // Один недоступный плейлист не должен прерывать остальные.
    }
  }

  messenger.showSnackBar(
    SnackBar(content: Text('Обновлено: $updated из ${targets.length}')),
  );
}
