/// Плеер: очередь треков, резолв стрима через провайдера площадки,
/// авто-переход.
///
/// Плеер о площадках не знает: берёт провайдера по префиксу id трека и просит
/// [MusicProvider.resolveStream]. Стрим резолвится в момент перехода, а не
/// заранее — у SoundCloud подписанный URL протухает, поэтому
/// `ConcatenatingAudioSource` тут не годится.
///
/// Фон/шторка (`audio_service`) — отдельный слой, его ещё нет.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';

enum PlayerRepeat { off, all, one }

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(player.dispose);
  return player;
});

class PlaybackState {
  final List<Track> queue;
  final int index;
  final bool loading;
  final String? error;
  final PlayerRepeat repeat;
  final bool shuffle;

  const PlaybackState({
    this.queue = const [],
    this.index = -1,
    this.loading = false,
    this.error,
    this.repeat = PlayerRepeat.off,
    this.shuffle = false,
  });

  Track? get track =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  PlaybackState copyWith({
    List<Track>? queue,
    int? index,
    bool? loading,
    String? error,
    bool clearError = false,
    PlayerRepeat? repeat,
    bool? shuffle,
  }) => PlaybackState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    repeat: repeat ?? this.repeat,
    shuffle: shuffle ?? this.shuffle,
  );
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);

class PlaybackController extends Notifier<PlaybackState> {
  final _rnd = Random();

  /// Счётчик запусков: ответ на устаревший резолв стрима не должен перебить
  /// трек, который пользователь успел выбрать позже.
  int _generation = 0;

  @override
  PlaybackState build() {
    final player = ref.read(audioPlayerProvider);
    final sub = player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
    ref.onDispose(sub.cancel);
    return const PlaybackState();
  }

  AudioPlayer get _player => ref.read(audioPlayerProvider);

  /// Поставить очередь и заиграть с [index].
  Future<void> playQueue(List<Track> tracks, int index) async {
    if (tracks.isEmpty) return;
    state = state.copyWith(queue: tracks, index: index, clearError: true);
    await _load(index);
  }

  /// Один трек — очередь из него же.
  Future<void> play(Track track) => playQueue([track], 0);

  Future<void> _load(int index) async {
    final track = state.queue[index];
    final gen = ++_generation;
    state = state.copyWith(index: index, loading: true, clearError: true);
    try {
      final provider = ref.read(registryProvider).forEntity(track.id);
      if (provider == null) throw StateError('нет провайдера для ${track.id}');
      final stream = await provider.resolveStream(track);
      if (stream == null) throw StateError('search.err.noStream');
      if (gen != _generation) return; // пользователь уже переключил трек
      await _player.setUrl(
        stream.url,
        headers: stream.headers.isEmpty ? null : stream.headers,
      );
      if (gen != _generation) return;
      state = state.copyWith(loading: false);
      // История пишется в момент, когда трек реально пошёл играть, а не когда
      // его выбрали: иначе перелистывание очереди засорит её всем подряд.
      ref.read(libraryProvider.notifier).pushHistory(track);
      // play() у just_audio завершается НЕ когда началось воспроизведение, а
      // когда трек доиграл (или его поставили на паузу). Ждать его нельзя:
      // `loading` тогда висит всю песню, а кнопка play остаётся спиннером.
      unawaited(_player.play());
    } catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void _onCompleted() {
    if (state.repeat == PlayerRepeat.one) {
      _player.seek(Duration.zero);
      unawaited(_player.play());
      return;
    }
    final isLast = state.index >= state.queue.length - 1;
    if (isLast && state.repeat == PlayerRepeat.off && !state.shuffle) {
      _player.seek(Duration.zero);
      _player.pause();
      return;
    }
    next();
  }

  Future<void> next() async {
    final q = state.queue;
    if (q.isEmpty) return;
    final int i;
    if (state.shuffle && q.length > 1) {
      var r = state.index;
      while (r == state.index) {
        r = _rnd.nextInt(q.length);
      }
      i = r;
    } else {
      i = (state.index + 1) % q.length;
    }
    await _load(i);
  }

  /// Назад: первые 3 секунды — к предыдущему треку, дальше — в начало текущего
  /// (привычное поведение транспорта).
  Future<void> prev() async {
    if (state.queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    final i = (state.index - 1 + state.queue.length) % state.queue.length;
    await _load(i);
  }

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      unawaited(_player.play()); // см. комментарий в _load
    }
  }

  Future<void> seek(Duration to) => _player.seek(to);

  void cycleRepeat() {
    const order = [PlayerRepeat.off, PlayerRepeat.all, PlayerRepeat.one];
    final nextMode = order[(order.indexOf(state.repeat) + 1) % order.length];
    state = state.copyWith(repeat: nextMode);
  }

  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);
}
