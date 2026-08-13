/// Перетянуть треки плейлиста из его источника — порт десктопного
/// `refreshPlaylistSilent`.
///
/// Сам импорт живёт в поиске (ссылка в поле поиска, как на десктопе); здесь
/// только повторный резолв уже сохранённой ссылки. Поэтому разбираем ровно те
/// же виды: коллекцию (плейлист/альбом) и аккаунт — у «Лайков <ник>» источником
/// записана ссылка на профиль.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';

/// Обновить состав плейлиста из [UserPlaylist.sourceUrl].
///
/// Возвращает, сколько треков прибавилось; `null` — источник не ответил или
/// ссылка больше не разбирается. Пустой ответ считаем ошибкой, а не «плейлист
/// опустел»: затирать состав тем, что площадка не отдала, нельзя.
Future<int?> refreshPlaylistFromSource(
  ProviderRegistry registry,
  LibraryController library,
  UserPlaylist playlist,
) async {
  final url = playlist.sourceUrl;
  if (url == null) return null;
  try {
    final found = await registry.resolveUrlAny(url);
    if (found == null) return null;
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
    if (tracks == null || tracks.isEmpty) return null;
    final had = playlist.trackIds.toSet();
    library.replacePlaylistTracks(playlist.id, tracks);
    return tracks.where((t) => !had.contains(t.id)).length;
  } catch (_) {
    // Один недоступный плейлист не должен прерывать остальные.
    return null;
  }
}

/// «Обновить треки» одного плейлиста — кнопка в его шапке (порт пункта
/// `refreshPlaylist` из десктопного `PlMenu`). Итог показывает тост.
///
/// Мессенджер, а не `BuildContext`: из шторки пункт вызывается уже после её
/// закрытия, и искать предка по её контексту поздно.
Future<void> refreshOnePlaylist(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  UserPlaylist playlist,
) async {
  final toast = messenger.busyToast(l.rpBusy(playlist.name));
  final added = await refreshPlaylistFromSource(
    ref.read(registryProvider),
    ref.read(libraryProvider.notifier),
    playlist,
  );
  if (added == null) {
    toast.finish(l.rpNoAnswer, kind: ToastKind.warn);
    return;
  }
  toast.finish(
    added == 0 ? l.paNoNewTracks : l.rpNewTracks(added),
    kind: added == 0 ? ToastKind.info : ToastKind.success,
  );
}
