/// Состояние текста песни — порт десктопного `lyricsStore.ts`.
///
/// Отличие от ПК: там текст запрашивается на КАЖДУЮ смену трека (бридж
/// `useLyricsBridge`), потому что от результата зависит, показывать ли кнопку.
/// В мобилке так делать не стоит — это лишний поход в сеть на каждый трек у
/// человека с мобильным интернетом. Поэтому запрос идёт лениво: панель открыта
/// — тянем текст текущего трека и всех следующих; закрыта — не тянем ничего, а
/// кнопка стоит всегда (не нашли — честно пишем «Текст не найден»).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import 'lrc.dart';
import 'lyrics_api.dart';
import 'lyrics_cache.dart';

enum LyricsStatus {
  /// Ещё не спрашивали.
  idle,
  loading,

  /// Текст есть — синхронный ([LyricsState.lines]) или простой.
  ready,

  /// Спросили, не нашли.
  empty,
}

class LyricsState {
  const LyricsState({
    this.trackId,
    this.status = LyricsStatus.idle,
    this.lines = const [],
    this.plain = '',
    this.source = '',
  });

  /// Чей это текст — по нему решаем, надо ли идти в сеть на смене трека.
  final String? trackId;
  final LyricsStatus status;

  /// Синхронный текст. Пуст — синхронизации нет, показываем [plain].
  final List<LrcLine> lines;
  final String plain;

  /// Метка источника («LRCLIB»).
  final String source;

  bool get synced => lines.isNotEmpty;
}

/// Кеш. Подменяется в `main()` дисковым, в тестах остаётся в памяти.
final lyricsCacheProvider = Provider<LyricsCache>((ref) => LyricsCache());

/// Сетевой поход за текстом — точка подмены в тестах.
typedef LyricsFetcher =
    Future<LyricsResult> Function({
      required String artist,
      required String title,
      int? durationSec,
    });

final lyricsFetcherProvider = Provider<LyricsFetcher>(
  (ref) =>
      ({required artist, required title, durationSec}) =>
          fetchLyrics(artist: artist, title: title, durationSec: durationSec),
);

final lyricsProvider = NotifierProvider<LyricsController, LyricsState>(
  LyricsController.new,
);

class LyricsController extends Notifier<LyricsState> {
  @override
  LyricsState build() => const LyricsState();

  /// Монотонный счётчик запросов — ответ устаревшего отбрасываем. Трек
  /// переключают быстрее, чем отвечает сеть, и без него текст прошлой песни
  /// прилетал бы поверх нынешней.
  int _request = 0;

  /// Загрузить текст трека, если он ещё не загружен.
  ///
  /// [force] — переспросить даже то, что уже показано (кнопка «повторить»).
  Future<void> ensureFor(Track? track, {bool force = false}) async {
    if (track == null) {
      clear();
      return;
    }
    if (!force &&
        track.id == state.trackId &&
        state.status != LyricsStatus.idle) {
      return;
    }

    final id = ++_request;
    state = LyricsState(trackId: track.id, status: LyricsStatus.loading);

    final artist = track.artist.trim();
    final title = track.name.trim();
    final cache = ref.read(lyricsCacheProvider);

    var result = force ? null : await cache.read(artist, title);
    if (result == null) {
      result = await ref.read(lyricsFetcherProvider)(
        artist: artist,
        title: title,
        durationSec: track.duration.inSeconds > 0
            ? track.duration.inSeconds
            : null,
      );
      await cache.write(artist, title, result);
    }
    if (id != _request) return; // трек уже сменили

    if (!result.found) {
      state = LyricsState(trackId: track.id, status: LyricsStatus.empty);
      return;
    }
    final synced = result.synced.trim();
    state = LyricsState(
      trackId: track.id,
      status: LyricsStatus.ready,
      lines: synced.isEmpty ? const [] : parseLrc(result.synced),
      plain: result.plain.isNotEmpty ? result.plain : stripLrc(result.synced),
      source: result.source.startsWith('lrclib') ? 'LRCLIB' : result.source,
    );
  }

  /// Сбросить — трека больше нет.
  void clear() {
    _request++;
    state = const LyricsState();
  }
}

/// Открыта ли панель текста. Живёт отдельно от самого текста: её состояние
/// переживает смену трека, как `open` в десктопном сторе.
final lyricsOpenProvider = StateProvider<bool>((ref) => false);
