/// «Сменить площадку» — заменить запись библиотеки версией того же трека с
/// другой площадки.
///
/// Порт десктопного `switchTrackPlatform` + `replaceLibTrack`: ищем на целевой
/// площадке по «название + артист», берём лучшее совпадение общего матчера и
/// переставляем на него ВСЕ ссылки — библиотеку, лайки, плейлисты, историю и
/// очередь. Плейлисты и порядок при этом не шевелятся: меняется только то, чем
/// трек играется.
///
/// Отличие от ПК одно и оно про офлайн: там скачанная копия остаётся висеть под
/// старым id — файл на диске есть, а трека с таким id уже нет, и убрать его
/// нечем. Мы такую копию удаляем: новую площадку человек при желании скачает
/// заново, а мусор, который не удалить, оставлять нельзя.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/source_label.dart';
import '../../core/log/bloom_log.dart';
import '../../core/providers/match.dart';
import '../../core/store/library_store.dart';
import '../../shared/ui/bloom_toast.dart';
import '../offline/offline_store.dart';
import '../player/player_controller.dart';

/// Куда трек можно переставить: все площадки, кроме локальной и его нынешней.
///
/// Выключённые (незалогиненный Яндекс) не прячем — их так же показывает
/// переключатель поиска, а провайдер сам ответит, что не может.
List<MusicSource> switchTargets(WidgetRef ref, Track track) => [
  for (final provider in ref.read(registryProvider).all)
    if (provider.source != MusicSource.local && provider.source != track.source)
      provider.source,
];

/// Можно ли вообще менять площадку у этого трека: у локального файла подмена
/// площадки означала бы подмену самого файла, а у трека из поиска менять нечего
/// — за ним нет записи библиотеки.
bool canSwitchPlatform(LibraryState lib, WidgetRef ref, Track track) =>
    track.source != MusicSource.local &&
    lib.tracks.containsKey(track.id) &&
    switchTargets(ref, track).isNotEmpty;

/// Найти трек на [target] и заменить им запись библиотеки.
Future<void> switchTrackPlatform(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
  Track track,
  MusicSource target,
) async {
  if (track.source == target) return;
  final provider = ref.read(registryProvider).byId(target.id);
  if (provider == null) {
    messenger.toast(l10n.spUnavailable, kind: ToastKind.warn);
    return;
  }

  // Поиск идёт секунды — говорим об этом сразу, иначе нажатие выглядит как
  // «ничего не произошло».
  messenger.toast(l10n.spSearching(target.label10n(l10n)));

  List<Track> found;
  try {
    final results = await provider.search(
      '${track.name} ${track.artist}'.trim(),
    );
    found = results.tracks;
  } catch (e) {
    logWarn('library', 'смена площадки: поиск на ${target.id} не удался: $e');
    messenger.toast(l10n.spFailed, kind: ToastKind.error);
    return;
  }

  // Своя же выдача может вернуть треки других площадок — берём только целевые.
  final best = rankMatches(
    [
      for (final t in found)
        if (t.source == target) t,
    ],
    track,
    limit: 1,
    min: kMinMatchScore,
  ).firstOrNull;
  if (best == null) {
    messenger.toast(
      l10n.spNotFound(target.label10n(l10n)),
      kind: ToastKind.warn,
    );
    return;
  }

  ref.read(libraryProvider.notifier).replaceTrack(track.id, best.track);
  ref.read(playbackProvider.notifier).replaceInQueue(track.id, best.track);
  // Скачанная копия осталась от прежней площадки: она играет не тот файл, что
  // теперь стоит за треком, и сослаться на неё уже некому.
  await ref.read(offlineProvider.notifier).remove(track.id);

  messenger.toast(l10n.spNow(target.label10n(l10n)), kind: ToastKind.success);
}
