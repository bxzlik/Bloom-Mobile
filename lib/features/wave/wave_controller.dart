/// Публичное API «Волны» — порт `src/wave/index.ts` вместе с сеансом
/// (`session.ts`) и фидбеком (`feedback.ts`).
///
/// Один вход на четыре режима и две площадки: [startPersonal], [startByTrack],
/// [startByQueue], [startByArtist] сами решают, чем набирать очередь — своим
/// движком по SoundCloud или станцией Яндекса, — и ставят её плееру.
///
/// Тосты отсюда не показываются: методы возвращают [WaveStartResult], а текст
/// подбирает интерфейс. Контроллер живёт дольше любого экрана, и `BuildContext`
/// ему взять негде — та же причина, по которой подписи источника берутся через
/// `globalL10n`.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/store/library_store.dart';
import '../../providers/yandex/models.dart' show YmException;
import '../../providers/yandex/ym_provider.dart' show ymNumericId;
import '../../providers/yandex/yandex.dart' as ym;
import '../player/play_source.dart';
import '../player/player_controller.dart';
import 'wave_engine.dart';
import 'wave_seeds.dart';
import 'wave_sources.dart';
import 'wave_store.dart';
import 'wave_types.dart';
import 'wave_yandex.dart';

/// Чем кончилась попытка запустить волну. Всё, кроме [ok], интерфейс
/// показывает тостом.
enum WaveStartResult {
  ok,

  /// Волну уже запускают — второй тап по кнопке ничего не делает.
  busy,

  /// Слушали ещё слишком мало, сидов не набралось.
  notEnoughData,

  /// Трека, от которого просили оттолкнуться, не нашлось.
  noSeed,

  /// У площадки этого трека своего подбора нет.
  notSupported,

  /// Очередь пуста — «похожие на очередь» строить не из чего.
  queueEmpty,

  /// В очереди нет треков SoundCloud.
  noScInQueue,

  /// У артиста не нашлось треков, годных в сиды.
  artistNoSeeds,

  /// Площадка не вернула похожих.
  noSimilar,

  /// Волна Яндекса, но в аккаунт не вошли.
  ymNoAuth,

  /// Станция ответила пустотой.
  ymEmpty,

  /// Станция не ответила (сеть, ошибка API).
  ymFailed,
}

class WaveRunState {
  const WaveRunState({this.starting = false, this.mode});

  /// Волна собирается прямо сейчас — кнопка запуска крутит вертушку.
  final bool starting;

  /// Режим идущего сеанса; `null` — волна не играет.
  final WaveMode? mode;

  bool get active => mode != null;

  WaveRunState copyWith({
    bool? starting,
    WaveMode? mode,
    bool clearMode = false,
  }) => WaveRunState(
    starting: starting ?? this.starting,
    mode: clearMode ? null : (mode ?? this.mode),
  );
}

final waveProvider = NotifierProvider<WaveController, WaveRunState>(
  WaveController.new,
);

class WaveController extends Notifier<WaveRunState> {
  final YandexRotor _rotor = YandexRotor();
  final Random _rnd = Random();

  /// Память сеанса своего движка; у станции Яндекса своя (внутри [_rotor]).
  WaveSession? _session;

  /// Гард от двойного запуска: два тапа по кнопке иначе заводят две волны, и
  /// обе пишут в одну очередь.
  bool _starting = false;
  bool _refilling = false;

  @override
  WaveRunState build() {
    // Сохранение трека в библиотеку — самое сильное «хочу ещё такого». Ловим
    // его здесь, а не в каждой кнопке: путей туда четыре (лайк, «В
    // библиотеку», плейлист, импорт), а сигнал у них один и тот же.
    ref.listen(libraryProvider, _noteSaved);
    return const WaveRunState();
  }

  /// Что из свежесохранённого пришло из ИДУЩЕЙ волны. Импорт чужого альбома
  /// на двести треков сигналом не считается — только то, что человек услышал
  /// в этой самой очереди и решил оставить.
  void _noteSaved(LibraryState? prev, LibraryState next) {
    if (prev == null || _session == null) return;
    if (identical(prev.inLib, next.inLib)) return;
    for (final track in _queue.queue) {
      if (next.inLib.containsKey(track.id) &&
          !prev.inLib.containsKey(track.id)) {
        onAddedToLibrary(track);
      }
    }
  }

  PlaybackController get _playback => ref.read(playbackProvider.notifier);
  PlaybackState get _queue => ref.read(playbackProvider);
  WaveStore get _store => ref.read(waveStoreProvider.notifier);

  WaveLibrary _view({Iterable<Track> extras = const []}) => WaveLibrary(
    lib: ref.read(libraryProvider),
    disliked: ref.read(waveStoreProvider).dislikes.keys.toSet(),
    extras: extras,
    random: _rnd,
  );

  // ── Запуск ──────────────────────────────────────────────────────────────

  /// «Моя волна»: сиды из библиотеки (SoundCloud) либо станция
  /// `user:onyourwave` (Яндекс).
  Future<WaveStartResult> startPersonal() async {
    // Именно действующая площадка, а не выбранная: без входа в Яндекс волна
    // не отказывает, а идёт своим движком (см. [effectiveWaveSourceProvider]).
    if (ref.read(effectiveWaveSourceProvider) == WaveEngineKind.yandex) {
      return _startRotor(YandexRotor.personalStation, WaveMode.personal);
    }
    final view = _view();
    final seeds = pickPersonalSeeds(view, _store.rotation);
    if (seeds.isEmpty) return WaveStartResult.notEnoughData;
    _store.bumpRotation();
    return _startEngine(WaveMode.personal, seeds, view);
  }

  /// Волна по треку. У Яндекса это нативная станция `track:<id>`, у остальных
  /// — свой подбор, и он умеет только SoundCloud.
  ///
  /// [seedFirst] — начать с самого трека, а дальше уйти в подобранное (тап по
  /// обложке в кольце на главной). По умолчанию волна сразу играет похожее,
  /// как пункт «Волна по треку» в меню трека на десктопе.
  Future<WaveStartResult> startByTrack(
    Track track, {
    bool seedFirst = false,
  }) async {
    if (track.source == MusicSource.yandex) {
      final id = ymNumericId(track.id);
      if (id.isEmpty) return WaveStartResult.noSeed;
      return _startRotor(
        YandexRotor.trackStation(id),
        WaveMode.track,
        first: seedFirst ? track : null,
      );
    }
    if (scIdOf(track) == null) return WaveStartResult.notSupported;
    return _startEngine(
      WaveMode.track,
      pickTrackSeeds(track.id),
      _view(extras: [track]),
      first: seedFirst ? track : null,
    );
  }

  /// «Похожие на очередь»: сиды из того, что играет сейчас. Библиотеку сюда не
  /// подмешиваем — очередь человек собрал сам, и волна должна её продолжить, а
  /// не разбавить знакомым.
  Future<WaveStartResult> startByQueue([List<Track>? tracks]) async {
    final source = (tracks == null || tracks.isEmpty) ? _queue.queue : tracks;
    if (source.isEmpty) return WaveStartResult.queueEmpty;
    final view = _view(extras: source);
    final seeds = pickQueueSeeds([for (final t in source) t.id], view);
    if (seeds.isEmpty) return WaveStartResult.noScInQueue;
    return _startEngine(WaveMode.queue, seeds, view);
  }

  /// Волна по артисту: нативная станция у Яндекса, сиды из его треков у
  /// SoundCloud. [seedTracks] — то, что уже загрузила страница артиста
  /// (популярные и все).
  Future<WaveStartResult> startByArtist(
    Artist artist, {
    List<Track> seedTracks = const [],
  }) async {
    if (artist.source == MusicSource.yandex) {
      final id = ymNumericId(artist.id);
      if (id.isEmpty) return WaveStartResult.artistNoSeeds;
      return _startRotor(YandexRotor.artistStation(id), WaveMode.artist);
    }
    if (seedTracks.isEmpty) return WaveStartResult.artistNoSeeds;
    final view = _view(extras: seedTracks);
    final seeds = pickQueueSeeds([for (final t in seedTracks) t.id], view);
    if (seeds.isEmpty) return WaveStartResult.artistNoSeeds;
    return _startEngine(WaveMode.artist, seeds, view);
  }

  /// Свой движок: собрать первую пачку и отдать её плееру.
  Future<WaveStartResult> _startEngine(
    WaveMode mode,
    List<String> seeds,
    WaveLibrary view, {
    Track? first,
  }) async {
    if (_starting) return WaveStartResult.busy;
    _starting = true;
    state = state.copyWith(starting: true);
    try {
      // Кэш чистим ДО сборки: иначе новая волна соберётся из тех же ответов,
      // что предыдущая, и человек услышит то же самое.
      resetWaveSourceCache();
      // Прошлый сеанс закрываем здесь же: дальше мы в любом случае либо
      // поставим новую очередь, либо ничего не найдём — и в обоих случаях
      // старая волна уже не идёт. Иначе после неудачного запуска состояние
      // продолжало бы уверять, что волна играет.
      _rotor.end();
      state = state.copyWith(clearMode: true);

      final session = WaveSession(
        mode: mode,
        seeds: seeds,
        startedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final engine = WaveEngine(
        view: view,
        store: _store,
        // Старую очередь фильтрам не показываем: она сейчас уедет целиком, и
        // отбраковка «уже в очереди» вырезала бы годных кандидатов.
        queueIds: const {},
        // А вот играющий прямо сейчас трек в свежей волне не нужен — иначе он
        // же и зазвучит третьим номером. Тот, с которого волну попросили
        // начать, встаёт в голову отдельно (см. [_handOff]).
        currentId: _queue.track?.id,
        random: _rnd,
      );
      final batch = await engine.buildBatch(
        mode: mode,
        seeds: seeds,
        session: session,
      );
      if (batch.isEmpty) return WaveStartResult.noSimilar;

      final tracks = tracksOf(batch);
      // Пометки «показано» ставим только гостям: у подмешанного знакомого своя
      // ротация, и вычёркивать его на две недели незачем.
      _store.markShown([
        for (final c in batch)
          if (!c.isLibrary) c.id,
      ]);

      _session = session;
      await _handOff(tracks, mode, first: first);
      return WaveStartResult.ok;
    } finally {
      _starting = false;
      state = state.copyWith(starting: false);
    }
  }

  /// Станция Яндекса: взять батч и отдать его плееру.
  Future<WaveStartResult> _startRotor(
    String station,
    WaveMode mode, {
    Track? first,
  }) async {
    if (_starting) return WaveStartResult.busy;
    if (ym.activeToken() == null) return WaveStartResult.ymNoAuth;
    _starting = true;
    state = state.copyWith(starting: true);
    try {
      // Свой сеанс закрываем: его догрузка и память подбора станции только
      // мешали бы. Как и в [_startEngine], гасим состояние сразу — неудачный
      // запуск не должен оставить «волна играет».
      _session = null;
      state = state.copyWith(clearMode: true);
      final tracks = await _rotor.start(station);
      if (tracks.isEmpty) return WaveStartResult.ymEmpty;
      await _handOff(tracks, mode, first: first);
      return WaveStartResult.ok;
    } on YmException {
      return WaveStartResult.ymFailed;
    } catch (_) {
      return WaveStartResult.ymFailed;
    } finally {
      _starting = false;
      state = state.copyWith(starting: false);
    }
  }

  /// Отдать собранное плееру. [first] — трек, который обязан зазвучать первым:
  /// подбор его в пачку обычно не кладёт, поэтому ставим в голову сами и, если
  /// он там уже был, не дублируем.
  Future<void> _handOff(
    List<Track> tracks,
    WaveMode mode, {
    Track? first,
  }) async {
    var queue = tracks;
    if (first != null) {
      queue = [
        first,
        for (final t in tracks)
          if (t.id != first.id) t,
      ];
    }
    state = state.copyWith(mode: mode);
    _store.saveSession(_session);
    // Фидбек «трек пошёл» отсюда не шлём: плеер сам позовёт [onTrackStart],
    // когда трек реально заиграет, — иначе станция услышала бы о нём дважды.
    await _playback.playWave(
      queue,
      WaveSource(label: waveLabel(mode), mode: mode),
    );
  }

  // ── Ход сеанса ──────────────────────────────────────────────────────────

  /// Плеер начал трек. Здесь и решается, идёт ли волна дальше: ушли на
  /// плейлист — сеанс тихо закрывается, иначе его догрузка била бы в сеть за
  /// треками, которые уже никому не нужны, а память подбора копила бы чужое.
  void onTrackStart(Track track) {
    if (!_isWaveQueue) {
      endSession();
      return;
    }
    final session = _session;
    if (session != null) {
      if (!session.playedIds.contains(track.id)) {
        session.playedIds.add(track.id);
        // Память сеанса не должна расти вечно: антиповторам хватает и двухсот
        // последних.
        if (session.playedIds.length > 200) session.playedIds.removeAt(0);
      }
      _store.saveSession(session);
    }
    if (_rotor.isRunning) _rotor.trackStarted(track);
    unawaited(_maybeRefill());
  }

  /// Плеер уходит с трека — единственный сигнал, по которому волна учится:
  /// дослушали или пролистнули.
  void onTrackEnd(Track track, Duration played, Duration total) {
    if (!_isWaveQueue) return;
    if (_rotor.isRunning) {
      _rotor.trackEnded(track, played, total);
      return;
    }
    final session = _session;
    if (session == null) return;
    final artist = normalizeArtist(track.artist);
    if (artist.isEmpty) return;
    switch (classifyCompletion(played, total)) {
      case WaveVerdict.skip:
        _bumpArtist(session, artist, -2);
      case WaveVerdict.finish:
        // Дослушал — основной положительный сигнал: сердечко у нас курирует
        // библиотеку, а не учит волну (ровно как на десктопе).
        _bumpArtist(session, artist, 3);
      case WaveVerdict.neutral:
        break;
    }
  }

  /// Сохранил трек в библиотеку — самый сильный «хочу ещё такого».
  void onAddedToLibrary(Track track) {
    final session = _session;
    if (session == null) return;
    final artist = normalizeArtist(track.artist);
    if (artist.isNotEmpty) _bumpArtist(session, artist, 5);
  }

  void _bumpArtist(WaveSession session, String artist, double delta) {
    session.artistBonus.update(artist, (v) => v + delta, ifAbsent: () => delta);
    _store.saveSession(session);
  }

  /// Догрузить очередь, если впереди осталось мало.
  Future<void> _maybeRefill() async {
    if (_refilling) return;
    final queue = _queue;
    final threshold = _rotor.isRunning
        ? kRotorRefillThreshold
        : kWaveRefillThreshold;
    if (queue.queue.length - 1 - queue.index > threshold) return;

    _refilling = true;
    try {
      final tracks = _rotor.isRunning
          ? await _rotor.refill()
          : await _refillEngine();
      // Пока ждали сеть, человек мог уйти из волны — в чужую очередь не пишем.
      if (tracks.isEmpty || !_isWaveQueue) return;
      _playback.appendToQueue(tracks);
    } finally {
      _refilling = false;
    }
  }

  Future<List<Track>> _refillEngine() async {
    final session = _session;
    if (session == null) return const [];
    final queue = _queue;
    final view = _view(extras: queue.queue);

    // Сиды догрузки — последнее, что человек НЕ пролистнул: волна идёт за тем,
    // что зашло, а не за тем, с чего начиналась.
    final recent = session.playedIds.reversed.take(6);
    final good = [
      for (final id in recent)
        if (!ref.read(waveStoreProvider).isDisliked(id)) id,
    ];
    final seeds = good.isEmpty ? session.seeds : good.take(3).toList();

    final engine = WaveEngine(
      view: view,
      store: _store,
      queueIds: {for (final t in queue.queue) t.id},
      currentId: queue.track?.id,
      random: _rnd,
    );
    final batch = await engine.buildBatch(
      mode: session.mode,
      seeds: seeds,
      session: session,
    );
    if (batch.isEmpty) return const [];
    _store.markShown([
      for (final c in batch)
        if (!c.isLibrary) c.id,
    ]);
    return tracksOf(batch);
  }

  // ── Дизлайк ─────────────────────────────────────────────────────────────

  /// Поставить/снять дизлайк. Возвращает новое состояние — интерфейсу нужно
  /// это для тоста.
  ///
  /// Дизлайкнутый прямо сейчас играющий трек не дослушивают: сразу уходим
  /// вперёд. Это единственное действие волны, которое работает и вне сеанса —
  /// метка живёт в библиотеке, а не в сеансе.
  bool toggleDislike(Track track) {
    final on = _store.toggleDislike(track);
    if (!on) return false;
    final current = _queue.track;
    if (current != null && current.id == track.id) {
      unawaited(_playback.next());
    }
    return true;
  }

  // ── Конец сеанса ────────────────────────────────────────────────────────

  /// Остановить волну явно (кнопка «Остановить»). Очередь остаётся играть —
  /// перестаёт только догружаться.
  void stop() => endSession();

  /// Тихо закрыть сеанс: человек ушёл слушать другое.
  void endSession() {
    if (_session == null && !_rotor.isRunning && !state.active) return;
    _session = null;
    _rotor.end();
    _store.saveSession(null);
    state = state.copyWith(clearMode: true);
  }

  /// Подхватить сеанс, восстановленный карточкой «Продолжить»: очередь вернул
  /// снимок, здесь возвращается память подбора.
  ///
  /// Станция Яндекса не восстанавливается — она каждый раз свежая, и её
  /// очередь после перезапуска доигрывает как обычный список.
  void adoptRestored(PlaySource? source) {
    if (source is! WaveSource) return;
    final saved = _store.savedSession;
    if (saved == null || saved.mode != source.mode) return;
    _session = saved;
    state = state.copyWith(mode: source.mode);
  }

  /// Играет ли сейчас именно волна.
  bool get _isWaveQueue => _queue.source is WaveSource;
}

/// Подпись источника для пилюли в плеере. Берётся один раз, при постановке
/// очереди: снимок сессии живёт дольше выбранного языка, и переводить её потом
/// уже некому.
String waveLabel(WaveMode mode) {
  final l = globalL10n;
  return switch (mode) {
    WaveMode.personal => l?.waveTitle ?? 'My Wave',
    WaveMode.track => l?.waveLabelTrack ?? 'Track wave',
    WaveMode.queue => l?.waveLabelQueue ?? 'Similar to queue',
    WaveMode.artist => l?.waveLabelArtist ?? 'Artist wave',
  };
}
