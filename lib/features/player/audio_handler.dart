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

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/log/bloom_log.dart';

/// Что хендлер умеет попросить у плеера. Реализует `PlaybackController`.
abstract class PlaybackCommands {
  Future<void> commandPlay();
  Future<void> commandPause();
  Future<void> commandNext();
  Future<void> commandPrev();
  Future<void> commandStop();
  Future<void> commandSkipTo(int index);
  Future<void> commandToggleFav();
}

/// Имя своей кнопки «лайк» — с ним она возвращается в [BloomAudioHandler.customAction].
const _favAction = 'fav';

/// iOS: звёздочка на экране блокировки (`NowPlayingLike` в `AppDelegate.swift`).
/// Своих кнопок audio_service на iOS не показывает, поэтому лайк там идёт
/// мимо него, через системный `likeCommand`.
const _iosLike = MethodChannel('bloom/like');

class BloomAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  /// Проставляется контроллером при старте. До этого момента (первые кадры)
  /// команд извне быть не может — играть ещё нечего.
  PlaybackCommands? commands;

  /// Мы резолвим ссылку на стрим ПЕРЕД `setUrl`, и всё это время just_audio
  /// сидит в `idle`. Без этого флага шторка на секунду показывала бы
  /// остановленный плеер посреди перехода на следующий трек.
  bool _resolving = false;

  /// Играющий трек в любимых — сердечко в шторке залито.
  bool _fav = false;

  BloomAudioHandler() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _iosLike.setMethodCallHandler((call) async {
        if (call.method == 'toggle') await customAction(_favAction);
      });
    }
    player.playbackEventStream.listen(
      _broadcast,
      onError: (Object e, StackTrace st) {
        // Ошибка платформы — единственное место, где слышно про сбой самого
        // ExoPlayer: остальное приложение видит только «трек не заиграл». Без
        // записи в журнал «у него музыка лагает» так и осталось бы догадкой.
        logError('player', 'сбой воспроизведения', e);
        _broadcast(player.playbackEvent);
      },
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

  /// Что в шторку уехало последним — чтобы писать в журнал только изменения.
  String? _lastReported;

  void _broadcast(PlaybackEvent event) {
    // На время резолва плеер стоит на паузе намеренно (чтобы не доигрывал
    // прошлый трек), но для шторки переход — это по-прежнему «играет»: иначе
    // кнопка на каждой смене трека моргала бы в play и обратно.
    final playing = _resolving || player.playing;
    // Каждая смена состояния — в журнал, сразу на диск.
    //
    // Это последняя точка, которую видит Dart перед тем, как дело уходит
    // целиком в нативную сторону: на `playing=true` система переводит службу в
    // передний план и вешает шторку, и если процесс умирает там, никакой
    // ошибки в Dart не будет — будет тишина после этой строки.
    final report = '${player.processingState.name} · playing=$playing';
    if (report != _lastReported) {
      _lastReported = report;
      logInfo('player', 'плеер: $report', now: true);
    }
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          // Своё действие, а не кнопка уведомления: audio_service кладёт его в
          // custom actions сессии, и шторку из них собирает сама система. Это
          // Android 13+; на старых версиях кнопки не будет вовсе.
          MediaControl.custom(
            androidIcon: _fav
                ? 'drawable/ic_notif_heart_filled'
                : 'drawable/ic_notif_heart',
            label: _fav
                ? globalL10n?.taRemoveFromFavorites ?? 'Remove from likes'
                : globalL10n?.taAddToFavorites ?? 'Like',
            name: _favAction,
          ),
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

  /// Контроллер сообщает, в любимых ли играющий трек.
  void setFav(bool value) {
    if (_fav == value) return;
    _fav = value;
    _broadcast(player.playbackEvent);
    if (defaultTargetPlatform == TargetPlatform.iOS) unawaited(_syncIosLike());
  }

  Future<void> _syncIosLike() async {
    try {
      await _iosLike.invokeMethod<void>('set', {
        'active': _fav,
        'title': _fav
            ? globalL10n?.taRemoveFromFavorites ?? 'Remove from likes'
            : globalL10n?.taAddToFavorites ?? 'Like',
      });
    } on PlatformException {
      // Не ответил канал — звёздочка просто не обновится.
    } on MissingPluginException {
      // Тесты.
    }
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
  Future<void> play() => commands?.commandPlay() ?? player.play();

  @override
  Future<void> pause() => commands?.commandPause() ?? player.pause();

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
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == _favAction) return commands?.commandToggleFav();
    return super.customAction(name, extras);
  }

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
