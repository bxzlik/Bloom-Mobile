/// Плеер: очередь треков, резолв стрима через провайдера площадки,
/// авто-переход.
///
/// Плеер о площадках не знает: берёт провайдера по префиксу id трека и просит
/// [MusicProvider.resolveStream]. Стрим резолвится в момент перехода, а не
/// заранее — у SoundCloud подписанный URL протухает, поэтому
/// `ConcatenatingAudioSource` тут не годится. У трека со скачанной копией
/// площадку не спрашиваем вовсе — играем файл с диска (см. `offline_store`).
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
import '../../core/store/stats_store.dart';
import '../offline/offline_store.dart';
import 'audio_handler.dart';
import 'notification_permission.dart';
import 'resume_store.dart';

enum PlayerRepeat { off, all, one }

/// Подменяется в `main()` на созданный через `AudioService.init` экземпляр.
final audioHandlerProvider = Provider<BloomAudioHandler>((ref) {
  throw StateError('audioHandlerProvider не переопределён в main()');
});

final audioPlayerProvider = Provider<AudioPlayer>(
  (ref) => ref.watch(audioHandlerProvider).player,
);

/// Головка воспроизведения: где стоим и сколько всего.
typedef Playhead = ({Duration position, Duration total});

/// Позиция и длительность одним потоком.
///
/// По отдельности они разъезжаются: на смене трека позиция тикает уже от
/// нового, а `player.duration`, прочитанная мимо стрима, ещё от старого — доля
/// прыгает. Плюс длительность приходит без тика позиции (пауза, загрузка), и
/// подписчик на одну только позицию про неё не узнаёт.
final playheadProvider = StreamProvider<Playhead>((ref) {
  final player = ref.watch(audioPlayerProvider);
  final out = StreamController<Playhead>();
  var position = player.position;
  var total = player.duration ?? Duration.zero;
  void emit() {
    if (!out.isClosed) out.add((position: position, total: total));
  }

  final subs = [
    player.positionStream.listen((p) {
      position = p;
      emit();
    }),
    player.durationStream.listen((d) {
      total = d ?? Duration.zero;
      emit();
    }),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    out.close();
  });
  emit(); // первое значение — сразу, до первого тика
  return out.stream;
});

/// Идёт ли звук. Отдельным потоком, потому что `playing` меняется и мимо нас —
/// кнопкой в шторке, гарнитурой, аудиофокусом.
final playingProvider = StreamProvider<bool>((ref) {
  final player = ref.watch(audioPlayerProvider);
  return player.playingStream;
});

class PlaybackState {
  final List<Track> queue;
  final int index;
  final bool loading;
  final String? error;
  final PlayerRepeat repeat;
  final bool shuffle;

  /// Откуда набрана очередь: id плейлиста/альбома площадки, id библиотечного
  /// списка (`all` / `fav` / `history` / `pl_…`). `null` — очередь ниоткуда:
  /// один трек из поиска, «Популярные» артиста.
  ///
  /// Нужен только карточкам: по нему плитка сета показывает эквалайзер, как
  /// строка трека — вместо длительности. Вычислить его из очереди нельзя: один
  /// и тот же состав легко лежит сразу в двух списках.
  final String? sourceId;

  const PlaybackState({
    this.queue = const [],
    this.index = -1,
    this.loading = false,
    this.error,
    this.repeat = PlayerRepeat.off,
    this.shuffle = false,
    this.sourceId,
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
    String? sourceId,
    bool clearSource = false,
  }) => PlaybackState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    repeat: repeat ?? this.repeat,
    shuffle: shuffle ?? this.shuffle,
    sourceId: clearSource ? null : (sourceId ?? this.sourceId),
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

/// Перемешанная копия [tracks]. Трек с номером [keep] встаёт первым и в тасовке
/// не участвует (`-1` — оставлять некого, мешаем всё), остальные — Фишер—Йетс.
///
/// Играющий трек обязан оказаться в начале: перемешивание не обрывает то, что
/// уже звучит, — оно меняет только то, что пойдёт дальше.
List<Track> shuffledQueue(List<Track> tracks, int keep, Random rnd) {
  final rest = [...tracks];
  final head = (keep >= 0 && keep < rest.length) ? rest.removeAt(keep) : null;
  for (var i = rest.length - 1; i > 0; i--) {
    final j = rnd.nextInt(i + 1);
    final tmp = rest[i];
    rest[i] = rest[j];
    rest[j] = tmp;
  }
  return head == null ? rest : [head, ...rest];
}

class PlaybackController extends Notifier<PlaybackState>
    implements PlaybackCommands {
  final _rnd = Random();

  /// Порядок очереди до перемешивания — чтобы вернуть его, когда перемешку
  /// выключат. `null` — очередь не перемешана (или её ставили заново).
  List<Track>? _origQueue;

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
    final subs = [
      handler.player.processingStateStream.listen((s) {
        if (s == ProcessingState.completed) _onCompleted();
      }),
      // Снимок сессии — на каждую смену play/pause: именно на паузе человек
      // чаще всего и уходит из приложения.
      handler.player.playingStream.listen((_) => _saveResume()),
    ];
    // Плюс по таймеру, пока играет: процесс убивают без предупреждения, и без
    // тика «Продолжить» вернуло бы на позицию последнего нажатия паузы.
    final ticker = Timer.periodic(_resumeEvery, (_) {
      if (handler.player.playing) _saveResume();
    });
    ref.onDispose(() {
      ticker.cancel();
      for (final s in subs) {
        s.cancel();
      }
      if (handler.commands == this) handler.commands = null;
    });
    return const PlaybackState();
  }

  /// Как часто обновляем позицию в снимке сессии. Реже — заметный откат назад
  /// после убийства процесса, чаще — лишняя запись файла на ровном месте.
  static const Duration _resumeEvery = Duration(seconds: 10);

  /// Записать снимок «Продолжить». Пустая очередь снимок не трогает: остановка
  /// не должна стирать то, что человек слушал.
  void _saveResume() {
    final track = state.track;
    if (track == null) return;
    ref
        .read(resumeProvider.notifier)
        .save(
          ResumeData.capture(
            queue: state.queue,
            index: state.index,
            position: _player.position,
            paused: !_player.playing,
            sourceId: state.sourceId,
          ),
        );
  }

  BloomAudioHandler get _handler => ref.read(audioHandlerProvider);
  AudioPlayer get _player => _handler.player;

  /// Поставить очередь и заиграть с [index]. [sourceId] — список, из которого
  /// она набрана (см. [PlaybackState.sourceId]); не передали — считаем, что
  /// очередь ниоткуда, и старый источник сбрасываем.
  ///
  /// При включённой перемешке новая очередь сразу ставится перемешанной:
  /// порядок очереди у нас и есть порядок воспроизведения, иначе флаг перемешки
  /// висел бы, а треки шли подряд.
  Future<void> playQueue(List<Track> tracks, int index, {String? sourceId}) {
    if (state.shuffle && tracks.length > 1) {
      return _start(
        shuffledQueue(tracks, index, _rnd),
        0,
        sourceId: sourceId,
        orig: tracks,
      );
    }
    return _start(tracks, index, sourceId: sourceId, orig: null);
  }

  /// «Перемешать» с карточки списка: включает перемешку и начинает со
  /// случайного трека, а не с первого. Порт `playShuffledFromSource`.
  Future<void> playQueueShuffled(List<Track> tracks, {String? sourceId}) {
    if (tracks.isEmpty) return Future.value();
    state = state.copyWith(shuffle: true);
    return _start(
      shuffledQueue(tracks, -1, _rnd),
      0,
      sourceId: sourceId,
      orig: tracks,
    );
  }

  Future<void> _start(
    List<Track> tracks,
    int index, {
    required String? sourceId,
    required List<Track>? orig,
    Duration? startAt,
  }) async {
    if (tracks.isEmpty) return;
    _origQueue = orig;
    state = state.copyWith(
      queue: tracks,
      index: index,
      clearError: true,
      sourceId: sourceId,
      clearSource: sourceId == null,
    );
    _handler.setQueue(tracks);
    await _load(index, startAt: startAt);
  }

  /// Один трек — очередь из него же.
  Future<void> play(Track track) => playQueue([track], 0);

  /// Продолжить прошлую сессию — очередь из снимка, с той же позиции
  /// (карточка «Продолжить» на главной). Порт `restoreResumeQueue`.
  Future<void> resumeSession(ResumeData data) => _start(
    data.queue,
    data.index,
    sourceId: data.sourceId,
    orig: null,
    // Первые пару секунд перематывать некуда — начинаем с начала трека.
    startAt: data.position > const Duration(seconds: 2) ? data.position : null,
  );

  Future<void> _load(int index, {Duration? startAt}) async {
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
      // Офлайн-копия выигрывает у сетевого стрима — как резолвер офлайна,
      // который на десктопе стоит первым в очереди. Заодно это единственный
      // способ заиграть без сети.
      final offlinePath = ref.read(offlineProvider.notifier).pathOf(track.id);
      if (offlinePath != null) {
        await _player.setFilePath(offlinePath, initialPosition: startAt);
      } else {
        final provider = ref.read(registryProvider).forEntity(track.id);
        if (provider == null) {
          throw StateError('нет провайдера для ${track.id}');
        }
        final stream = await provider.resolveStream(track);
        if (stream == null) throw StateError('search.err.noStream');
        if (gen != _generation) return; // пользователь уже переключил трек
        await _player.setUrl(
          stream.url,
          headers: stream.headers.isEmpty ? null : stream.headers,
          initialPosition: startAt,
        );
      }
      if (gen != _generation) return;
      state = state.copyWith(loading: false);
      _handler.setResolving(false);
      // История пишется в момент, когда трек реально пошёл играть, а не когда
      // его выбрали: иначе перелистывание очереди засорит её всем подряд.
      ref.read(libraryProvider.notifier).pushHistory(track);
      // Дневной журнал ведётся рядом с историей — как `loadPlay` на десктопе.
      ref.read(statsProvider.notifier).addPlay();
      // Снимок «Продолжить» — сразу на новом треке: подписка на playingStream
      // при переходе внутри очереди молчит (плеер и так играл), и до тика
      // таймера карточка звала бы обратно на прошлый трек.
      _saveResume();
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
    if (isLast && state.repeat == PlayerRepeat.off) {
      _player.seek(Duration.zero);
      _player.pause();
      return;
    }
    next();
  }

  /// Дальше по очереди. Про перемешку тут ничего не знают: она уже переставила
  /// саму очередь (см. [toggleShuffle]), и «следующий» всегда следующий.
  Future<void> next() async {
    final q = state.queue;
    if (q.isEmpty) return;
    await _load((state.index + 1) % q.length);
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

  /// Перемешка переставляет саму очередь, а не подсовывает случайный номер в
  /// [next] — иначе список в шторке очереди врал бы о том, что пойдёт дальше.
  /// Выключение возвращает запомненный порядок. Порт `cycleShuffle`
  /// (без «умного» шага — истории прослушиваний для весов у нас пока нет).
  void toggleShuffle() {
    final q = state.queue;
    if (state.shuffle) {
      final orig = _origQueue;
      _origQueue = null;
      if (orig == null) {
        state = state.copyWith(shuffle: false);
        return;
      }
      // Играющий трек ищем в исходном порядке по id: он остаётся тем же, меняется
      // только его номер.
      final current = state.track;
      final at = current == null
          ? -1
          : orig.indexWhere((t) => t.id == current.id);
      final index = at < 0 ? 0 : at;
      state = state.copyWith(queue: orig, index: index, shuffle: false);
      _handler
        ..setQueue(orig)
        ..setTrack(state.track, queueIndex: index);
      return;
    }
    if (q.length <= 1) {
      state = state.copyWith(shuffle: true);
      return;
    }
    _origQueue = [...q];
    final shuffled = shuffledQueue(q, state.index, _rnd);
    state = state.copyWith(queue: shuffled, index: 0, shuffle: true);
    _handler
      ..setQueue(shuffled)
      ..setTrack(state.track, queueIndex: 0);
  }

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
    // Порядок поменяли руками — снимок «до перемешки» устарел: выключение
    // перемешки должно вернуть то, что человек собрал последним, а не то, что
    // было до неё.
    if (_origQueue != null) _origQueue = q;
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
    final removed = q.removeAt(index);
    // Из снимка «до перемешки» смахнутый трек тоже убираем, иначе выключение
    // перемешки вернуло бы его в очередь.
    final orig = _origQueue;
    if (orig != null) {
      final at = orig.indexWhere((t) => t.id == removed.id);
      if (at >= 0) _origQueue = [...orig]..removeAt(at);
    }
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
    _origQueue = null;
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
    if (_player.processingState == ProcessingState.idle &&
        state.track != null) {
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
    _origQueue = null; // возвращать нечего: очереди больше нет
    // Очередь уходит, а режимы повтора и перемешивания — нет: это настройки
    // плеера, а не свойство конкретной очереди.
    state = PlaybackState(repeat: state.repeat, shuffle: state.shuffle);
    _handler
      ..setResolving(false)
      ..setQueue(const [])
      ..setTrack(null);
  }
}
