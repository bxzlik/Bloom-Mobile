/// Плеер: очередь треков, резолв стрима через провайдера площадки,
/// авто-переход.
///
/// Плеер о площадках не знает: берёт провайдера по префиксу id трека и просит
/// [MusicProvider.resolveStream]. Стрим резолвится в момент перехода, а не
/// заранее — у SoundCloud подписанный URL протухает, поэтому
/// `ConcatenatingAudioSource` тут не годится.
///
/// Фон, шторка и гарнитура — в [BloomAudioHandler]; он владеет [AudioPlayer] и
/// заворачивает команды извне обратно сюда (см. [PlaybackCommands]), чтобы
/// «дальше» из шторки и «дальше» в приложении были одним и тем же кодом.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import 'audio_handler.dart';
import 'notification_permission.dart';

enum PlayerRepeat { off, all, one }

/// Подменяется в `main()` на созданный через `AudioService.init` экземпляр.
final audioHandlerProvider = Provider<BloomAudioHandler>((ref) {
  throw StateError('audioHandlerProvider не переопределён в main()');
});

final audioPlayerProvider = Provider<AudioPlayer>(
  (ref) => ref.watch(audioHandlerProvider).player,
);

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

/// Куда переедет играющий трек ([current]), когда строку [from] переносят на
/// место [target] (оба — уже настоящие номера, без поправки списка).
///
/// Играющий остаётся ТЕМ ЖЕ треком, меняется только его номер: перетащили его
/// самого — он теперь на [target]; перетащили строку через него — он сдвинулся
/// на одну. Ошибка здесь тихая: играет то же, но «дальше» уводит не туда.
int indexAfterReorder(int current, int from, int target) {
  if (current == from) return target;
  if (from < current && target >= current) return current - 1;
  if (from > current && target <= current) return current + 1;
  return current;
}

class PlaybackController extends Notifier<PlaybackState>
    implements PlaybackCommands {
  final _rnd = Random();

  /// Счётчик запусков: ответ на устаревший резолв стрима не должен перебить
  /// трек, который пользователь успел выбрать позже.
  int _generation = 0;

  /// Разрешение на уведомления спрашиваем один раз за сеанс и только перед
  /// первым звуком — дёргать системный диалог на старте приложения незачем.
  bool _askedForNotifications = false;

  @override
  PlaybackState build() {
    final handler = ref.read(audioHandlerProvider);
    handler.commands = this;
    final sub = handler.player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
    ref.onDispose(() {
      sub.cancel();
      if (handler.commands == this) handler.commands = null;
    });
    return const PlaybackState();
  }

  BloomAudioHandler get _handler => ref.read(audioHandlerProvider);
  AudioPlayer get _player => _handler.player;

  /// Поставить очередь и заиграть с [index].
  Future<void> playQueue(List<Track> tracks, int index) async {
    if (tracks.isEmpty) return;
    state = state.copyWith(queue: tracks, index: index, clearError: true);
    _handler.setQueue(tracks);
    await _load(index);
  }

  /// Один трек — очередь из него же.
  Future<void> play(Track track) => playQueue([track], 0);

  Future<void> _load(int index) async {
    final track = state.queue[index];
    final gen = ++_generation;
    state = state.copyWith(index: index, loading: true, clearError: true);
    // Название в шторке ставим сразу, не дожидаясь ссылки на стрим.
    _handler
      ..setTrack(track, queueIndex: index)
      ..setResolving(true);
    if (!_askedForNotifications) {
      _askedForNotifications = true;
      unawaited(ensureNotificationPermission());
    }
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
      _handler.setResolving(false);
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
      _handler.setResolving(false);
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
      await commandPlay();
    }
  }

  Future<void> seek(Duration to) => _player.seek(to);

  void cycleRepeat() {
    const order = [PlayerRepeat.off, PlayerRepeat.all, PlayerRepeat.one];
    final nextMode = order[(order.indexOf(state.repeat) + 1) % order.length];
    state = state.copyWith(repeat: nextMode);
  }

  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);

  /// Перейти к треку очереди по номеру (экран очереди, список в шторке).
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    await _load(index);
  }

  /// Перетащить трек. Индексы — в семантике `ReorderableListView`: [to]
  /// считается ДО изъятия строки, поэтому при движении вниз он на единицу
  /// больше настоящего.
  void reorder(int from, int to) {
    final q = [...state.queue];
    if (from < 0 || from >= q.length) return;
    final target = (to > from ? to - 1 : to).clamp(0, q.length - 1);
    if (target == from) return;
    q.insert(target, q.removeAt(from));

    final index = indexAfterReorder(state.index, from, target);
    state = state.copyWith(queue: q, index: index);
    _handler
      ..setQueue(q)
      ..setTrack(state.track, queueIndex: index);
  }

  /// Убрать трек из очереди (смахивание строки). Порт `removeFromQueue`.
  Future<void> removeAt(int index) async {
    final q = [...state.queue];
    if (index < 0 || index >= q.length) return;
    if (q.length == 1) {
      // Последний — очередь пуста, плеер сбрасываем.
      await commandStop();
      await _player.stop();
      return;
    }
    final current = state.index;
    q.removeAt(index);
    if (index == current) {
      // Удалили играющий — играем тот, что встал на его место (или последний).
      final next = index.clamp(0, q.length - 1);
      state = state.copyWith(queue: q, index: next);
      _handler.setQueue(q);
      await _load(next);
      return;
    }
    final shifted = index < current ? current - 1 : current;
    state = state.copyWith(queue: q, index: shifted);
    _handler
      ..setQueue(q)
      ..setTrack(state.track, queueIndex: shifted);
  }

  /// Очистить очередь, оставив играющий трек. Воспроизведение не рвём.
  void clearExceptCurrent() {
    final track = state.track;
    if (track == null) return;
    state = state.copyWith(queue: [track], index: 0);
    _handler
      ..setQueue([track])
      ..setTrack(track, queueIndex: 0);
  }

  // --- PlaybackCommands: команды из шторки, с экрана блокировки, с гарнитуры

  @override
  Future<void> commandPlay() async {
    // После stop() (смахнули шторку) источник у just_audio уже отпущен —
    // «играть» должно перезапустить трек, а не молча ничего не сделать.
    if (_player.processingState == ProcessingState.idle && state.track != null) {
      await _load(state.index);
      return;
    }
    unawaited(_player.play()); // см. комментарий в _load
  }

  @override
  Future<void> commandPause() => _player.pause();

  @override
  Future<void> commandNext() => next();

  @override
  Future<void> commandPrev() => prev();

  @override
  Future<void> commandSkipTo(int index) => jumpTo(index);

  @override
  Future<void> commandStop() async {
    ++_generation; // отменяем резолв, который может быть в полёте
    // Очередь уходит, а режимы повтора и перемешивания — нет: это настройки
    // плеера, а не свойство конкретной очереди.
    state = PlaybackState(repeat: state.repeat, shuffle: state.shuffle);
    _handler
      ..setResolving(false)
      ..setQueue(const [])
      ..setTrack(null);
  }
}
