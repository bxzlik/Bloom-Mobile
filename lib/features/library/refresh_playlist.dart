/// Перетянуть треки плейлиста из его источников — порт десктопного
/// `refreshPlaylistSilent`.
///
/// Источников у плейлиста может быть несколько и с разных площадок
/// ([UserPlaylist.sources]): каждый резолвится общим путём импорта
/// (`resolveCollectionUrl`), поэтому разбираются ровно те же виды ссылок —
/// коллекция (плейлист/альбом) и аккаунт, у которого берутся лайки.
///
/// Состав НЕ заменяется: новые треки ложатся наверх плейлиста, всё, что в него
/// добавили руками, остаётся на месте. Иначе привязать чужую коллекцию к своему
/// плейлисту было бы нельзя — первое же обновление стёрло бы его.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'import_url.dart';

/// Обновить состав плейлиста из всех его [UserPlaylist.sources].
///
/// Возвращает, сколько треков прибавилось; `null` — обновлять неоткуда или НИ
/// ОДИН источник не ответил. Упавший источник не отменяет остальные: частичный
/// успех считаем успехом — привязанную коллекцию могли удалить на площадке.
Future<int?> refreshPlaylistFromSource(
  ProviderRegistry registry,
  LibraryController library,
  UserPlaylist playlist,
) async {
  if (playlist.sources.isEmpty) return null;

  // Источники тянем по очереди: их обычно единицы, а параллель зря душит
  // площадки.
  final fresh = <Track>[];
  for (final source in playlist.sources) {
    try {
      fresh.addAll((await resolveCollectionUrl(registry, source.url)).tracks);
    } catch (_) {
      // Один недоступный источник не должен прерывать остальные.
    }
  }
  // Пустой ответ считаем ошибкой, а не «в источниках ничего не осталось».
  if (fresh.isEmpty) return null;

  // Дубли и порядок разбирает сам стор: состав мог измениться, пока шла сеть.
  return library.addTracksToPlaylist(playlist.id, fresh);
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
