/// Волна — бесконечная очередь из треков, похожих на то, с чего она начата, из
/// радио самих площадок; порт `Wave` ПК.
///
/// «Моя волна» стартует с библиотеки (самое слушаемое и лайки), остальные — с
/// трека, артиста или очереди. Радио SoundCloud и YouTube Music идут через наш
/// отбор и порядок (`pickBatch`); станция Яндекса учится у слушателя сама,
/// поэтому её порядок сохраняется, а ей сообщают, что дослушали и что
/// пролистнули. Дизлайки — навсегда, в волне и вне её.
///
/// Тосты отсюда не показываются: методы возвращают [WaveStartResult], а текст
/// подбирает интерфейс. Контроллер живёт дольше любого экрана, и `BuildContext`
/// ему взять негде — та же причина, по которой подписи источника берутся через
/// `globalL10n`.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers/music_provider.dart';
import '../../core/store/history_store.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import '../../providers/soundcloud/sc_sources.dart';
import '../../providers/yandex/yandex.dart' show kWaveStation;
import '../../providers/yandex/ym_provider.dart' show ymNumericId;
import '../../shared/util/taste.dart';
import '../player/play_source.dart';
import '../player/player_controller.dart';
import 'wave_engine.dart';
import 'wave_seeds.dart';
import 'wave_store.dart';
import 'wave_types.dart';

/// Чем кончилась попытка запустить волну. Всё, кроме [ok] и [busy],
/// интерфейс показывает тостом.
enum WaveStartResult {
  ok,

  /// Волну уже запускают — второй тап по кнопке ничего не делает.
  busy,

  /// Слушали ещё слишком мало, сидов не набралось.
  notEnoughData,

  /// У трека нет радио, от которого оттолкнуться.
  noSeed,

  /// Очередь пуста — «похожие на очередь» строить не из чего.
  queueEmpty,

  /// В очереди нет треков с радио.
  noSeedsInQueue,

  /// У артиста не нашлось треков, годных в сиды.
  artistNoSeeds,

  /// Площадка не вернула похожих.
  noSimilar,

  /// Волна Яндекса, но в аккаунт не вошли.
  ymNoAuth,
}

class WaveRunState {
  const WaveRunState({this.starting = false, this.mode});

  /// Волна собирается прямо сейчас — кнопка запуска крутит вертушку.
  final bool starting;

  /// Режим идущей волны; `null` — волна не играет.
  final WaveMode? mode;

  bool get active => mode != null;
}

final waveProvider = NotifierProvider<WaveController, WaveRunState>(
  WaveController.new,
);

/// Станций, которые спрашивают разом.
const int _kParallel = 3;

class WaveController extends Notifier<WaveRunState> {
  final Random _rnd = Random();

  WaveRun? _run;

  /// Новая волна или её конец делают старые ответы сети чужими.
  int _gen = 0;
  bool _refilling = false;

  @override
  WaveRunState build() => const WaveRunState();

  PlaybackController get _playback => ref.read(playbackProvider.notifier);
  PlaybackState get _queue => ref.read(playbackProvider);
  WaveStore get _store => ref.read(waveStoreProvider.notifier);

  MusicProvider? _provider(String code) =>
      ref.read(registryProvider).byId(MusicSource.fromCode(code).id);

  /// Радио трека у его площадки — `Wave::seedOf` ПК.
  WaveSeed? seedOf(Track t) {
    final p = ref.read(registryProvider).byId(t.source.id);
    if (p == null || !p.isEnabled) return null;
    final station = p.trackStation(t);
    return station.isEmpty ? null : WaveSeed(t.source.code, station);
  }

  WaveLibrary _view({Iterable<Track> extras = const []}) => WaveLibrary(
    lib: ref.read(libraryProvider),
    disliked: ref.read(waveStoreProvider).dislikedIds,
    stats: ref.read(playStatsProvider),
    recent: [for (final row in ref.read(historyRowsProvider)) row.id],
    extras: extras,
    seedOf: seedOf,
  );

  /// В волне прямо сейчас: она идёт, и очередь — её.
  bool get _inWave => _run != null && _queue.source is WaveSource;

  // ── Запуск ──────────────────────────────────────────────────────────────

  /// «Моя волна» с площадки из настройки. Выбран Яндекс без входа — с
  /// SoundCloud (см. [effectiveWaveSourceProvider]).
  Future<WaveStartResult> startPersonal() async {
    final src = ref.read(effectiveWaveSourceProvider);
    if (src == MusicSource.yandex) {
      return _begin(WaveMode.personal, const [
        WaveSeed('ym', kWaveStation),
      ], native: true);
    }
    final seeds = personalSeeds(_view(), src.code, _store.takeRotation());
    if (seeds.isEmpty) return WaveStartResult.notEnoughData;
    return _begin(WaveMode.personal, seeds);
  }

  /// Волна по треку. Радио трека Яндекса — его собственное и учится; остальные
  /// идут через наш отбор.
  ///
  /// [seedFirst] — начать с самого трека, а дальше уйти в подобранное (тап по
  /// обложке в кольце на главной).
  Future<WaveStartResult> startByTrack(Track track, {bool seedFirst = false}) {
    final s = seedOf(track);
    if (s == null) return Future.value(WaveStartResult.noSeed);
    return _begin(
      WaveMode.track,
      [s],
      native: s.provider == MusicSource.yandex.code,
      about: 'track:${track.id}',
      first: seedFirst ? track : null,
    );
  }

  /// «Похожие на очередь»: очередь заменяется похожими на то, что в ней.
  Future<WaveStartResult> startByQueue([List<Track>? tracks]) {
    final source = (tracks == null || tracks.isEmpty) ? _queue.queue : tracks;
    if (source.isEmpty) return Future.value(WaveStartResult.queueEmpty);
    final seeds = queueSeeds(source, _view(extras: source));
    if (seeds.isEmpty) return Future.value(WaveStartResult.noSeedsInQueue);
    return _begin(WaveMode.queue, seeds);
  }

  /// Волна по артисту: станция артиста у Яндекса, у остальных — сиды из того,
  /// что уже загрузила его страница ([seedTracks]: популярные и все).
  Future<WaveStartResult> startByArtist(
    Artist artist, {
    List<Track> seedTracks = const [],
  }) {
    final about = 'artist:${artistKey(artist.name)}';
    if (artist.source == MusicSource.yandex) {
      final id = ymNumericId(artist.id);
      if (id.isEmpty) return Future.value(WaveStartResult.artistNoSeeds);
      if (!(_provider('ym')?.isEnabled ?? false)) {
        return Future.value(WaveStartResult.ymNoAuth);
      }
      return _begin(
        WaveMode.artist,
        [WaveSeed('ym', 'artist:$id')],
        native: true,
        about: about,
      );
    }
    final seeds = queueSeeds(seedTracks, _view(extras: seedTracks));
    if (seeds.isEmpty) return Future.value(WaveStartResult.artistNoSeeds);
    return _begin(WaveMode.artist, seeds, about: about);
  }

  /// [replace] — пачка становится очередью; иначе дописывается в её конец
  /// («Авто похожие»), пока [isValid] — пока ждали сеть, могли поставить
  /// другое.
  Future<WaveStartResult> _begin(
    WaveMode mode,
    List<WaveSeed> seeds, {
    bool native = false,
    bool replace = true,
    String about = '',
    Track? first,
    bool Function()? isValid,
  }) async {
    if (state.starting) return WaveStartResult.busy;
    final gen = ++_gen;
    final run = WaveRun(mode: mode, seeds: seeds, about: about, native: native);
    _run = run;
    _refilling = false;
    if (replace) state = WaveRunState(starting: true, mode: state.mode);
    // Новая волна не должна собраться из тех же ответов, что прошлая.
    resetWaveSourceCache();
    try {
      final pages = await _gather(seeds);
      if (gen != _gen) return WaveStartResult.busy;
      if (!replace && !(isValid?.call() ?? true)) {
        _end();
        return WaveStartResult.noSimilar;
      }
      final batch = pickBatch(pages, _pick(run));
      if (batch.isEmpty) {
        _end();
        return WaveStartResult.noSimilar;
      }
      _markShown(batch);
      final source = WaveSource(label: waveLabel(mode), mode: mode);
      if (replace) {
        state = WaveRunState(starting: true, mode: mode);
        _save();
        await _playback.playWave([
          ?first,
          for (final t in batch)
            if (t.id != first?.id) t,
        ], source);
      } else if (!_playback.continueAsWave(batch, source)) {
        _end();
        return WaveStartResult.noSimilar;
      } else {
        state = WaveRunState(mode: mode);
        _save();
      }
      if (native) {
        _provider(
          seeds.first.provider,
        )?.stationFeedback(seeds.first.station, 'radioStarted');
      }
      return WaveStartResult.ok;
    } finally {
      if (replace && gen == _gen) {
        state = WaveRunState(mode: _run == null ? null : state.mode);
      }
    }
  }

  /// Станция каждого сида — оттуда, где она остановилась в прошлый раз (новая
  /// волна на тех же сидах слышит, что дальше), по несколько разом.
  Future<List<List<Track>>> _gather(List<WaveSeed> seeds) async {
    final pages = List<List<Track>>.filled(seeds.length, const []);
    final cursors = <WaveSeed, String>{};
    var next = 0;
    Future<void> worker() async {
      while (next < seeds.length) {
        final i = next++;
        final s = seeds[i];
        final p = _provider(s.provider);
        if (p == null) continue;
        final cursor = _store.cursorOf(s);
        var page = await p.station(s.station, cursor);
        // Курсор протух — тогда с начала.
        if (page.tracks.isEmpty && cursor.isNotEmpty) {
          page = await p.station(s.station, '');
        }
        cursors[s] = page.cursor;
        pages[i] = page.tracks;
      }
    }

    await Future.wait([
      for (var k = 0; k < min(_kParallel, seeds.length); k++) worker(),
    ]);
    _store.saveCursors(cursors);
    return pages;
  }

  WavePick _pick(WaveRun run) {
    final lib = ref.read(libraryProvider);
    final stats = ref.read(playStatsProvider);
    final queue = _queue;
    return WavePick(
      run: run,
      queue: queue.queue,
      currentId: queue.track?.id,
      library: lib.allTracks,
      inLibrary: lib.isInLib,
      isFav: lib.isFav,
      isDisliked: ref.read(waveStoreProvider).isDisliked,
      playedWithin: (id, days) => stats.recentlyPlayed(id, days),
      shown: _store.shownIds(),
      random: _rnd,
    );
  }

  /// «Показано» ставим только чужим: своё из библиотеки ходит долей «Моей
  /// волны», вычёркивать его на две недели незачем.
  void _markShown(List<Track> batch) {
    final lib = ref.read(libraryProvider);
    _store.markShown([
      for (final t in batch)
        if (!lib.isInLib(t.id)) t.id,
    ]);
  }

  void _save() => _store.saveRun(_run);

  // ── Ход волны ───────────────────────────────────────────────────────────

  /// Впереди мало треков: следующая пачка — от последних услышанных (за чем
  /// слушатель остаётся, туда волна и идёт) или от сидов, с которых начата.
  Future<void> _refill() async {
    final run = _run;
    if (run == null || !_inWave || state.starting || _refilling) return;
    final queue = _queue;
    final left = queue.queue.length - 1 - queue.index;
    if (left > (run.native ? kWaveRefillAtNative : kWaveRefillAt)) return;
    var seeds = run.seeds;
    if (!run.native) {
      final store = ref.read(waveStoreProvider);
      final recent = <WaveSeed>[];
      final heard = run.played.skip(max(0, run.played.length - 6)).toList();
      for (final id in heard.reversed) {
        if (recent.length >= 3) break;
        if (store.isDisliked(id)) continue;
        final t = queue.queue.where((t) => t.id == id).firstOrNull;
        final s = t == null ? null : seedOf(t);
        if (s != null) recent.add(s);
      }
      if (recent.isNotEmpty) seeds = recent;
    }
    _refilling = true;
    final gen = _gen;
    try {
      final pages = await _gather(seeds);
      if (gen != _gen || !_inWave) return;
      final batch = pickBatch(pages, _pick(run));
      if (batch.isEmpty) return;
      _markShown(batch);
      _playback.appendToQueue(batch);
      _save();
    } finally {
      if (gen == _gen) _refilling = false;
    }
  }

  /// Плеер начал трек. Ушли на другой список — волна тихо кончается, иначе её
  /// догрузка писала бы в чужую очередь.
  void onTrackStart(Track track) {
    if (_queue.source is! WaveSource) {
      endSession();
      return;
    }
    final run = _run;
    if (run == null) return;
    final s = run.seeds.first;
    if (run.native && track.source.code == s.provider) {
      _provider(
        s.provider,
      )?.stationFeedback(s.station, 'trackStarted', track: track);
    }
    unawaited(_refill());
  }

  /// Трек засчитан прослушанным: в волне он услышан, и пора проверить запас.
  void onCounted(Track track) {
    final run = _run;
    if (run == null || !_inWave) return;
    if (!run.played.contains(track.id)) run.played.add(track.id);
    if (run.played.length > 200) {
      run.played.removeRange(0, run.played.length - 200);
    }
    _save();
    unawaited(_refill());
  }

  /// Уходим с трека: дослушали (85 %) или пролистнули рано (до 20 с и 30 %) —
  /// волна учит артиста; станции Яндекса — говорим ей.
  void onTrackEnd(Track track, Duration played, Duration total) {
    final run = _run;
    if (run == null || !_inWave || total <= Duration.zero) return;
    if (run.native) {
      final s = run.seeds.first;
      if (track.source.code != s.provider) return;
      final ratio = played.inMilliseconds / total.inMilliseconds;
      _provider(s.provider)?.stationFeedback(
        s.station,
        ratio < 0.3 ? 'skip' : 'trackFinished',
        track: track,
        played: played.inMilliseconds / 1000,
      );
      return;
    }
    final step = completionStep(played, total);
    final artists = artistKeys(track);
    if (step == 0 || artists.isEmpty) return;
    for (final a in artists) {
      run.bonus[a] = (run.bonus[a] ?? 0) + step;
    }
    _save();
  }

  // ── Дизлайк ─────────────────────────────────────────────────────────────

  /// Поставить/снять дизлайк; возвращает, стоит ли он теперь. Играющий
  /// дизлайкнутый трек уходит — в очереди он остаётся зачёркнутым.
  bool toggleDislike(Track track) {
    final on = _store.toggleDislike(track);
    if (!on) return false;
    final queue = _queue;
    if (queue.track?.id == track.id) {
      if (queue.index < queue.queue.length - 1) {
        unawaited(_playback.next());
      } else if (_inWave) {
        unawaited(_refill());
      }
    }
    return true;
  }

  // ── Конец ───────────────────────────────────────────────────────────────

  /// Остановить волну явно (кнопка «Остановить»). Очередь доигрывает, но
  /// больше не догружается.
  void stop() => endSession();

  /// Волна кончилась; ответ, ещё идущий по сети, отбрасывается.
  void endSession() {
    if (_run == null && !state.active) return;
    _end();
  }

  void _end() {
    ++_gen;
    _run = null;
    _refilling = false;
    _store.saveRun(null);
    state = const WaveRunState();
  }

  // ── «Авто похожие» ──────────────────────────────────────────────────────

  /// Очередь доиграла (или вот-вот) — дописать в её хвост похожие на то, что в
  /// ней (кнопка «Похожие на очередь», наоборот, заменяет). Дальше хвост идёт
  /// волной «похожие на очередь». Тихо, без тостов: это фон, а не нажатая
  /// кнопка. [isValid] — пока ждали сеть, человек мог поставить другое.
  Future<bool> continueQueue({required bool Function() isValid}) async {
    if (state.starting) return false;
    final queue = _queue.queue;
    final seeds = queueSeeds(queue, _view(extras: queue));
    if (seeds.isEmpty) return false;
    final r = await _begin(
      WaveMode.queue,
      seeds,
      replace: false,
      isValid: isValid,
    );
    return r == WaveStartResult.ok;
  }

  /// Подхватить волну, которую вернула сессия: очередь вернул снимок, здесь
  /// возвращается память подбора. Сессия была не волной — сохранённая
  /// забывается.
  void adoptRestored(PlaySource? source) {
    final saved = _store.savedRun;
    if (source is! WaveSource) {
      if (saved != null) _store.saveRun(null);
      return;
    }
    if (saved == null) return;
    _run = saved;
    state = WaveRunState(mode: saved.mode);
  }
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
