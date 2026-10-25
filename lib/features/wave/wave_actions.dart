/// Запуск волны из интерфейса: одна точка, где [WaveStartResult] превращается
/// в тост.
///
/// Контроллер про тосты не знает намеренно (см. шапку `wave_controller`), а
/// экранов, откуда волну заводят, четыре — и текст неудачи у них общий.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'wave_controller.dart';
import 'wave_store.dart';

/// Есть ли у площадки трека радио. Пункт «Волна по треку» есть только у
/// таких: у остальных он открывал бы меню ради отказа.
bool canStartWaveFrom(WidgetRef ref, Track track) =>
    ref.read(waveProvider.notifier).seedOf(track) != null;

/// Можно ли строить волну по артисту: станция артиста у Яндекса, у остальных —
/// радио хотя бы одного из его загруженных треков.
bool canStartWaveFromArtist(
  WidgetRef ref,
  Artist artist,
  List<Track> knownTracks,
) {
  if (artist.source == MusicSource.yandex) return true;
  final wave = ref.read(waveProvider.notifier);
  return knownTracks.any((t) => wave.seedOf(t) != null);
}

/// «Моя волна».
Future<void> startPersonalWave(BuildContext context, WidgetRef ref) =>
    _run(context, ref, (wave) => wave.startPersonal());

/// Волна по треку. [seedFirst] — начать с него самого.
Future<void> startWaveFromTrack(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  bool seedFirst = false,
}) => _run(
  context,
  ref,
  (wave) => wave.startByTrack(track, seedFirst: seedFirst),
);

/// «Похожие на очередь». Без списка берётся то, что играет сейчас.
Future<void> startWaveFromQueue(
  BuildContext context,
  WidgetRef ref, [
  List<Track>? tracks,
]) => _run(context, ref, (wave) => wave.startByQueue(tracks));

/// Волна по артисту. [seedTracks] — то, что уже загрузила его страница.
Future<void> startWaveFromArtist(
  BuildContext context,
  WidgetRef ref,
  Artist artist, {
  List<Track> seedTracks = const [],
}) => _run(
  context,
  ref,
  (wave) => wave.startByArtist(artist, seedTracks: seedTracks),
);

/// Остановить волну — очередь доигрывает, но больше не догружается.
void stopWave(BuildContext context, WidgetRef ref) {
  ref.read(waveProvider.notifier).stop();
  showToast(context, context.l.waveToastStopped);
}

/// Поставить/снять дизлайк. Дизлайкнутый играющий трек волна тут же
/// пролистывает — см. [WaveController.toggleDislike].
void toggleWaveDislike(BuildContext context, WidgetRef ref, Track track) {
  final l10n = context.l;
  final messenger = ScaffoldMessenger.of(context);
  final on = ref.read(waveProvider.notifier).toggleDislike(track);
  messenger.toast(on ? l10n.waveToastDisliked : l10n.waveToastUndisliked);
}

bool isWaveDisliked(WidgetRef ref, String trackId) =>
    ref.watch(waveStoreProvider).isDisliked(trackId);

/// Общий ход: подбор идёт сетью, поэтому мессенджер и переводы берём ДО
/// ожидания — экран, с которого волну завели, к этому моменту уже закрыт
/// (шторка действий, меню артиста).
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<WaveStartResult> Function(WaveController) start,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;
  final result = await start(ref.read(waveProvider.notifier));
  if (result == WaveStartResult.ok || result == WaveStartResult.busy) return;
  messenger.toast(waveResultMessage(l10n, result), kind: ToastKind.warn);
}

/// Текст неудачного запуска.
String waveResultMessage(AppLocalizations l10n, WaveStartResult result) =>
    switch (result) {
      WaveStartResult.ok || WaveStartResult.busy => '',
      WaveStartResult.notEnoughData => l10n.waveToastNotEnough,
      WaveStartResult.noSeed => l10n.waveToastNoSeed,
      WaveStartResult.queueEmpty => l10n.waveToastQueueEmpty,
      WaveStartResult.noSeedsInQueue => l10n.waveToastNoSeedsInQueue,
      WaveStartResult.artistNoSeeds => l10n.waveToastArtistNoSeeds,
      WaveStartResult.noSimilar => l10n.waveToastNoSimilar,
      WaveStartResult.ymNoAuth => l10n.waveToastYmNoAuth,
    };
