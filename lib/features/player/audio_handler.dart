/// Мост между плеером и системой: шторка уведомлений, экран блокировки,
/// кнопки гарнитуры, фоновое воспроизведение.
///
/// Хендлер намеренно ГЛУПЫЙ: он владеет [AudioPlayer] и транслирует его
/// состояние наружу, но сам ничего не решает. Любая команда извне (кнопка в
/// шторке, щелчок на наушниках, Bluetooth руля) уходит в [PlaybackCommands] —
/// то есть в `PlaybackController`, который один знает про очередь, shuffle,
/// repeat и резолв стрима. Иначе логика перехода расползлась бы по двум местам
/// и «дальше» из шторки играло бы не то, что «дальше» в приложении.
///
/// Владелец [AudioPlayer] теперь здесь, а не в `audioPlayerProvider`: плеер
/// должен пережить закрытие UI (свернули приложение — Flutter-движок могут
/// прибить, а сервис остаётся).
library;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/entities/entities.dart';

/// Что хендлер умеет попросить у плеера. Реализует `PlaybackController`.
abstract class PlaybackCommands {
  Future<void> commandPlay();
  Future<void> commandPause();
  Future<void> commandNext();
  Future<void> commandPrev();
  Future<void> commandStop();
  Future<void> commandSkipTo(int index);
}

class BloomAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  /// Проставляется контроллером при старте. До этого момента (первые кадры)
  /// команд извне быть не может — играть ещё нечего.
  PlaybackCommands? commands;

  /// Мы резолвим ссылку на стрим ПЕРЕД `setUrl`, и всё это время just_audio
  /// сидит в `idle`. Без этого флага шторка на секунду показывала бы
  /// остановленный плеер посреди перехода на следующий трек.
  bool _resolving = false;

  BloomAudioHandler() {
    player.playbackEventStream.listen(
      _broadcast,
      onError: (Object e, StackTrace st) => _broadcast(player.playbackEvent),
    );
    // playing меняется без playbackEvent — иначе кнопка в шторке залипает.
    player.playingStream.listen((_) => _broadcast(player.playbackEvent));
  }

  static const _stateMap = {
    ProcessingState.idle: AudioProcessingState.idle,
    ProcessingState.loading: AudioProcessingState.loading,
    ProcessingState.buffering: AudioProcessingState.buffering,
    ProcessingState.ready: AudioProcessingState.ready,
    ProcessingState.completed: AudioProcessingState.completed,
  };

  void _broadcast(PlaybackEvent event) {
    final playing = player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        // Три кнопки в свёрнутой шторке — как на десктопе.
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _resolving
            ? AudioProcessingState.loading
            : _stateMap[player.processingState]!,
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  /// Контроллер сообщает, что ушёл резолвить ссылку (или закончил).
  void setResolving(bool value) {
    if (_resolving == value) return;
    _resolving = value;
    _broadcast(player.playbackEvent);
  }

  /// Что показывать в шторке и на экране блокировки.
  void setTrack(Track? track, {int? queueIndex}) {
    if (track == null) {
      mediaItem.add(null);
      return;
    }
    mediaItem.add(_toMediaItem(track));
    if (queueIndex != null) {
      playbackState.add(playbackState.value.copyWith(queueIndex: queueIndex));
    }
  }

  /// Очередь целиком — её видят Android Auto и «список» в шторке.
  void setQueue(List<Track> tracks) {
    queue.add(tracks.map(_toMediaItem).toList());
  }

  MediaItem _toMediaItem(Track track) => MediaItem(
    id: track.id,
    title: track.name,
    artist: track.artist,
    album: track.album,
    // Ноль у площадки значит «не знаю»: отдав его, мы получили бы в шторке
    // намертво пустую полосу прогресса.
    duration: track.duration > Duration.zero ? track.duration : null,
    artUri: _artUri(track.cover),
  );

  Uri? _artUri(String? cover) {
    if (cover == null || cover.isEmpty) return null;
    if (cover.startsWith('http')) return Uri.tryParse(cover);
    return Uri.file(cover);
  }

  // Всё, что ниже, приходит СНАРУЖИ: шторка, экран блокировки, гарнитура.
  // Фолбэк на голый player — на случай команды до того, как контроллер
  // подключился.

  @override
  Future<void> play() =>
      commands?.commandPlay() ?? player.play();

  @override
  Future<void> pause() =>
      commands?.commandPause() ?? player.pause();

  @override
  Future<void> skipToNext() async => commands?.commandNext();

  @override
  Future<void> skipToPrevious() async => commands?.commandPrev();

  @override
  Future<void> skipToQueueItem(int index) async =>
      commands?.commandSkipTo(index);

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await commands?.commandStop();
    await player.stop();
    await super.stop();
  }

  /// Смахнули приложение из недавних — глушим звук и убираем шторку, иначе
  /// остаётся играющее уведомление от закрытого приложения.
  @override
  Future<void> onTaskRemoved() => stop();
}
