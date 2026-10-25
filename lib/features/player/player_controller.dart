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
import '../../core/l10n/l10n.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/library_store.dart';
import '../../core/store/settings_store.dart';
import '../../shared/ui/bloom_toast.dart';
import '../lastfm/lastfm_store.dart';
import '../library/local_tracks.dart';
import '../notifications/notif_store.dart';
import '../offline/offline_store.dart';
import '../wave/wave_controller.dart';
import '../../core/store/play_log.dart';
import '../../core/store/play_stats.dart';
import 'audio_handler.dart';
import 'nightcore_ios.dart';
import 'notification_permission.dart';
import 'play_error.dart';
import 'play_source.dart';
import 'resume_store.dart';
import 'sleep_timer_store.dart';
import 'speed_store.dart';
import 'track_swap_dir.dart';

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

  /// «Умная» перемешка — подвид [shuffle], без него не бывает: [shuffle]
  /// по-прежнему отвечает на «перемешано ли вообще», этот флаг различает
  /// вариант (порт `smartShuffle` из `queueStore`).
  final bool smartShuffle;

  /// Откуда набрана очередь: раздел библиотеки, альбом площадки, страница
  /// артиста, выдача поиска (см. [PlaySource]). `null` — источника нет вовсе.
  ///
  /// Нужен двоим: пилюле в шапке плеера (что именно играет) и карточкам — по
  /// [sourceId] плитка сета показывает эквалайзер, как строка трека вместо
  /// длительности. Вычислить его из очереди нельзя: один и тот же состав легко
  /// лежит сразу в двух списках.
  final PlaySource? source;

  const PlaybackState({
    this.queue = const [],
    this.index = -1,
    this.loading = false,
    this.error,
    this.repeat = PlayerRepeat.off,
    this.shuffle = false,
    this.smartShuffle = false,
    this.source,
  });

  Track? get track =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  /// Что заиграет после текущего трека — для плашки «Далее» в плеере.
  ///
  /// `null` — дальше ничего: очередь кончилась и не закольцована. На последнем
  /// треке смотрим на повтор, потому что закольцовку делает [next]
  /// (`(index + 1) % length`), а не порядок очереди: при `all` дальше
  /// действительно первый трек, при `off` и `one` — тишина либо тот же трек, и
  /// называть «следующим» нечего. Очередь из одного трека молчит всегда: сам
  /// себе он не «дальше».
  Track? get nextTrack {
    if (index < 0 || queue.length < 2) return null;
    if (index + 1 < queue.length) return queue[index + 1];
    return repeat == PlayerRepeat.all ? queue.first : null;
  }

  /// Ключ источника для сравнения с id списка — см. [PlaySource.id].
  String? get sourceId => source?.id;

  PlaybackState copyWith({
    List<Track>? queue,
    int? index,
    bool? loading,
    String? error,
    bool clearError = false,
    PlayerRepeat? repeat,
    bool? shuffle,
    bool? smartShuffle,
    PlaySource? source,
    bool clearSource = false,
  }) => PlaybackState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    repeat: repeat ?? this.repeat,
    shuffle: shuffle ?? this.shuffle,
    // Выключенная перемешка гасит и умную: подвид без неё не живёт.
    smartShuffle: (shuffle ?? this.shuffle)
        ? (smartShuffle ?? this.smartShuffle)
        : false,
    source: clearSource ? null : (source ?? this.source),
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

/// Очередь после «Следующим»: [track] встаёт сразу за играющим ([index]), а
/// если он в очереди уже стоял — переезжает оттуда, а не дублируется (порт
/// `enqueue(..., 'next')` с десктопа). Возвращает новый порядок и новый номер
/// играющего.
///
/// Отдельной функцией — ровно как [indexAfterReorder]: перестановка вокруг
/// играющего трека тихо ломается (играет то же, а «дальше» уводит не туда), и
/// проверять её надо списком, а не на глаз.
(List<Track>, int) queueWithNext(List<Track> queue, int index, Track track) =>
    queueWithNextAll(queue, index, [track]);

/// То же самое для пачки — «Играть следующими» целым плейлистом. Порядок пачки
/// сохраняется, повторы внутри неё схлопываются, уже стоящие в очереди треки
/// переезжают на новое место, а не задваиваются.
///
/// Играющий трек из пачки выбрасывается: он уже звучит, и «следующим» ему быть
/// негде — на десктопе этот случай тихо уводит номер играющего мимо (`enqueue`
/// пересобирает очередь, не глядя на `curId` внутри пачки).
(List<Track>, int) queueWithNextAll(
  List<Track> queue,
  int index,
  List<Track> batch,
) {
  final current = (index >= 0 && index < queue.length) ? queue[index] : null;
  final seen = <String>{};
  final add = [
    for (final t in batch)
      if (t.id != current?.id && seen.add(t.id)) t,
  ];
  if (add.isEmpty) return (queue, index);
  final rest = [
    for (final t in queue)
      if (!seen.contains(t.id)) t,
  ];
  // Номер играющего считаем уже ПОСЛЕ изъятия: треки могли выдернуть сверху.
  final at = current == null ? -1 : rest.indexWhere((t) => t.id == current.id);
  return ([...rest]..insertAll(at + 1, add), at < 0 ? index : at);
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

/// Вес трека для «умной» перемешки — порт `smartShuffleWeight` с ПК: недавно и
/// часто слушанные тяжелее и статистически всплывают в НАЧАЛЕ очереди, но
/// порядок каждый раз новый. Контраст намеренно большой (~140×): холодных
/// треков в библиотеке кратно больше недавних, и при слабом смещении они
/// забивают начало.
///   base:    0.5    — трек без истории
///   recency: до +40 — экспоненциальное затухание, «горячая» неделя, к месяцу гаснет
///   freq:    до +30 — число прослушиваний (потолок 10)
double smartShuffleWeight(PlayStats stats, String id, {DateTime? now}) {
  final count = stats.playCount(id);
  final last = stats.lastPlayedAt(id);
  var recency = 0.0;
  if (last > 0) {
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final days = (at - last) / 86400000;
    recency = 40 * exp(-days / 6);
  }
  return 0.5 + recency + min(count, 10) * 3;
}

/// Взвешенная перемешка без повторов (Эфраимидис—Спиракис): ключ `u^(1/w)`,
/// чем тяжелее трек, тем ближе ключ к 1 и тем раньше он встаёт. Трек [keep]
/// встаёт первым и в тасовке не участвует — как в [shuffledQueue].
List<Track> weightedShuffledQueue(
  List<Track> tracks,
  int keep,
  double Function(Track) weight,
  Random rnd,
) {
  final rest = [...tracks];
  final head = (keep >= 0 && keep < rest.length) ? rest.removeAt(keep) : null;
  final keyed = [
    for (final t in rest)
      (t, pow(rnd.nextDouble(), 1 / max(weight(t), 1e-4)).toDouble()),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  final out = [for (final (t, _) in keyed) t];
  return head == null ? out : [head, ...out];
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

  /// Прослушивание текущего трека уже засчитано. Сбрасывается только при смене
  /// трека (в [_load]) — как `_playCredited` на десктопе, поэтому второй круг
  /// повтора одного трека второй раз не считается.
  bool _credited = false;

  /// Очередь в том виде, какой она была до очистки (кнопка «очистить» или
  /// удаление последнего трека), — её поднимает «Продолжить». Сбрасывается
  /// новой очередью; повторная очистка полную очередь урезанной не перетирает.
  List<Track>? _preClearQueue;

  /// «Авто похожие»: трек, для которого продолжение уже запрошено…
  String? _autoSimilarFor;

  /// …запрос ещё в пути…
  bool _autoSimilarPending = false;

  /// …и «далее» нажали раньше, чем пришла пачка. Все три сбрасываются сменой
  /// трека (в [_load]).
  bool _autoSimilarAdvance = false;

  /// Очередь доиграла до конца без повтора — плеер стоит на начале последнего
  /// трека. Опоздавшая пачка «Авто похожих» тогда переходит на неё сама.
  bool _queueEnded = false;

  @override
  PlaybackState build() {
    final handler = ref.read(audioHandlerProvider);
    handler.commands = this;
    final subs = [
      handler.player.processingStateStream.listen((s) {
        if (s == ProcessingState.completed) _onCompleted();
      }),
      // Зачёт прослушивания — на 90% трека, как на десктопе; плюс своё,
      // независимое правило зачёта у Last.fm (см. [_onPosition]).
      handler.player.positionStream.listen(_onPosition),
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
    // Скорость и питч — своя настройка (`speed_store`), а плеер здесь: ставим
    // их сами и держим подписку. Порт `bootstrapSpeed` + `setPlaybackRate` с
    // десктопа: сохранённая скорость должна работать с первого же трека, а не
    // с момента, когда человек откроет пикер.
    ref.listen(speedProvider, (_, next) => unawaited(_applySpeed(next)));
    unawaited(_applySpeed(ref.read(speedProvider)));
    // Таймер сна: стор тикает временем, паузу и затухание делаем здесь — плеер
    // наш. Слушаем каждый тик, а не только заведение таймера: остаток на нуле
    // и есть команда «пора».
    ref.listen(sleepTimerProvider, (_, next) => _applySleep(next));
    ref.onDispose(_stopFade);
    // Сердечко в шторке: лайк могут поставить где угодно в приложении, а трек
    // сменить десятком путей — поэтому следим за обоими, а не за кнопками.
    ref.listen(libraryProvider.select((lib) => lib.favs), (_, _) => _syncFav());
    listenSelf((prev, next) {
      if (prev?.track?.id != next.track?.id) _syncFav();
    });
    return const PlaybackState();
  }

  /// Тик затухания перед сном. Не `null` — громкость сейчас крутится вниз.
  Timer? _fadeTick;

  /// Реакция на состояние таймера сна.
  ///
  /// Времени своего не держим: единственные часы — `endsAt` в сторе, поэтому
  /// «сколько осталось» и здесь считается от него. Тик стора идёт раз в
  /// секунду, а затухание крутится своим тиком в 100 мс: посекундными ступенями
  /// уход громкости слышен.
  void _applySleep(SleepTimerState sleep) {
    if (sleep.expired) {
      _fireSleep();
      return;
    }
    if (sleep.mode != SleepMode.timer || !sleep.fade) {
      _stopFade();
      return;
    }
    if (sleep.remaining <= kSleepFade) {
      _fadeTick ??= Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _fadeStep(),
      );
    } else {
      // Таймер продлили или перезавели — вышли из зоны затухания.
      _stopFade();
    }
  }

  /// Шаг затухания: громкость = доля непрожитого окна [kSleepFade].
  void _fadeStep() {
    final endsAt = ref.read(sleepTimerProvider).endsAt;
    if (endsAt == null) {
      _stopFade();
      return;
    }
    final left = endsAt.difference(ref.read(sleepClockProvider)());
    final k = (left.inMilliseconds / kSleepFade.inMilliseconds).clamp(0.0, 1.0);
    unawaited(_player.setVolume(k));
    // Ноль — не повод жать паузу самим: это сделает тик стора через
    // [_fireSleep], и одной точкой останова меньше поводов разъехаться.
  }

  /// Вернуть громкость на место. Зовётся отовсюду, где затухание кончилось —
  /// хоть срабатыванием, хоть отменой таймера: недокрученная громкость иначе
  /// осталась бы и на следующем прослушивании.
  void _stopFade() {
    if (_fadeTick == null) return;
    _fadeTick!.cancel();
    _fadeTick = null;
    unawaited(_player.setVolume(1));
  }

  /// Время вышло: пауза, громкость на место, таймер снять.
  void _fireSleep() {
    _fadeTick?.cancel();
    _fadeTick = null;
    unawaited(_player.pause());
    unawaited(_player.setVolume(1));
    ref.read(sleepTimerProvider.notifier).cancel();
  }

  /// Скорость и питч на плеер. Повторять на каждый трек не надо: just_audio
  /// держит обе величины у себя и переставляет их на новый источник сам.
  Future<void> _applySpeed(SpeedSettings speed) async {
    // iOS — до скорости: установка скорости и докручивает алгоритм треку.
    await setIosNightcore(speed.nightcore);
    await _player.setSpeed(speed.rate);
    try {
      await _player.setPitch(speed.pitch);
    } catch (_) {
      // Питч умеет только Android (ExoPlayer). На iOS канал отвечает ошибкой,
      // и тон за темпом там делает `setIosNightcore`.
    }
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
            source: state.source,
            fullQueue: _preClearQueue,
            shuffle: state.shuffle,
            smartShuffle: state.smartShuffle,
            repeat: state.repeat,
          ),
        );
  }

  BloomAudioHandler get _handler => ref.read(audioHandlerProvider);
  AudioPlayer get _player => _handler.player;

  /// Доля трека, после которой прослушивание засчитывается, — десктопный порог
  /// `creditPlay`.
  static const double _creditAt = 0.9;

  /// Тик позиции. Слушателей у него двое, и пороги у них РАЗНЫЕ: наш зачёт
  /// прослушивания (0.9 длительности) и скробблинг Last.fm (30 с и половина —
  /// это требование самой площадки, а не наш выбор). Пока идёт загрузка нового
  /// трека, тики принадлежат ещё прошлому, поэтому оба ждут её конца.
  void _onPosition(Duration position) {
    if (state.loading) return;
    _maybeCredit(position);
    ref.read(lastfmProvider.notifier).onProgress(position, _player.duration);
  }

  /// Тик позиции: доиграли до порога — засчитываем. Пока идёт загрузка нового
  /// трека, тики принадлежат ещё прошлому — и засчитались бы не тому, кто их
  /// наиграл (на десктопе от этого спасает то, что `curId` меняется только
  /// после успешного резолва).
  void _maybeCredit(Duration position) {
    if (_credited || state.loading) return;
    final total = _player.duration;
    if (total == null || total <= Duration.zero) return;
    if (position.inMilliseconds >= total.inMilliseconds * _creditAt) _credit();
  }

  /// Засчитать прослушивание в журнал. Одна точка на всё, как
  /// `Player::credit` ПК, и зовётся она НЕ на старте: трек, который
  /// пролистнули или который не заиграл, прослушанным не считается.
  void _credit() {
    if (_credited) return;
    final track = state.track;
    if (track == null) return;
    _credited = true;
    // Журнал событий «трек X в момент T» — из него выводятся «История»,
    // статистика профиля и дни, уровень, сиды волны и «Итоги». Своих
    // счётчиков больше нет нигде.
    ref.read(playLogProvider.notifier).log(track);
    // В волне трек теперь услышан — и пора проверить её запас.
    ref.read(waveProvider.notifier).onCounted(track);
    // Засчитан последний трек очереди — просим продолжение заранее, чтобы к
    // концу трека пачка уже стояла и переход шёл обычным путём, без паузы.
    _maybeAutoSimilar();
  }

  /// «Авто похожие» (порт `maybeAutoSimilar` с ПК): последний трек очереди
  /// засчитан, доиграл или на нём нажали «далее» — дописываем в хвост похожие
  /// (см. `WaveController.continueQueue`). Не
  /// срабатывает при повторе (он сам решает, что после конца) и в живой волне
  /// (она догружается сама).
  void _maybeAutoSimilar() {
    if (!ref.read(settingsProvider).autoSimilar) return;
    final track = state.track;
    if (track == null || state.repeat != PlayerRepeat.off) return;
    if (state.index != state.queue.length - 1) return;
    if (state.source is WaveSource && ref.read(waveProvider).active) return;
    if (_autoSimilarFor == track.id) return;
    _autoSimilarFor = track.id;
    _autoSimilarPending = true;
    final source = state.source;
    unawaited(
      ref
          .read(waveProvider.notifier)
          // Источник сменился, пока ждали сеть (запустили плейлист), — в чужую
          // очередь не пишем.
          .continueQueue(isValid: () => identical(state.source, source))
          .catchError((Object _) => false)
          .then((ok) {
            // Трек уже сменился — это продолжение больше не наше.
            if (_autoSimilarFor != track.id) return;
            _autoSimilarPending = false;
            // Пачка опоздала: трек доиграл или жали «далее» — переходим на
            // первый дописанный сами.
            if (ok && (_queueEnded || _autoSimilarAdvance)) unawaited(next());
            _autoSimilarAdvance = false;
          }),
    );
  }

  /// Поставить очередь и заиграть с [index]. [source] — откуда она набрана
  /// (см. [PlaybackState.source]); не передали — считаем, что очередь ниоткуда,
  /// и старый источник сбрасываем.
  ///
  /// При включённой перемешке новая очередь сразу ставится перемешанной:
  /// порядок очереди у нас и есть порядок воспроизведения, иначе флаг перемешки
  /// висел бы, а треки шли подряд.
  Future<void> playQueue(List<Track> tracks, int index, {PlaySource? source}) {
    if (state.shuffle && tracks.length > 1) {
      return _start(
        _shuffled(tracks, index, smart: state.smartShuffle),
        0,
        source: source,
        orig: tracks,
      );
    }
    return _start(tracks, index, source: source, orig: null);
  }

  /// «Перемешать» с карточки списка: включает перемешку и начинает со
  /// случайного трека, а не с первого. Порт `playShuffledFromSource`.
  Future<void> playQueueShuffled(List<Track> tracks, {PlaySource? source}) {
    if (tracks.isEmpty) return Future.value();
    // Кнопка на карточке — всегда обычная перемешка, как на ПК.
    state = state.copyWith(shuffle: true, smartShuffle: false);
    return _start(
      shuffledQueue(tracks, -1, _rnd),
      0,
      source: source,
      orig: tracks,
    );
  }

  Future<void> _start(
    List<Track> tracks,
    int index, {
    required PlaySource? source,
    required List<Track>? orig,
    Duration? startAt,
    bool autoplay = true,
    List<Track>? preClear,
  }) async {
    if (tracks.isEmpty) return;
    _origQueue = orig;
    // Новая очередь — «до очистки» больше нечему быть. Кроме восстановленной
    // урезанной: полную держим дальше, иначе первая же запись снимка её
    // потеряет и «Продолжить» вернёт один трек.
    _preClearQueue = preClear;
    state = state.copyWith(
      queue: tracks,
      index: index,
      clearError: true,
      source: source,
      clearSource: source == null,
    );
    _handler.setQueue(tracks);
    await _load(index, startAt: startAt, autoplay: autoplay);
  }

  /// Один трек — очередь из него же, и в пилюле стоит он сам (десктопный
  /// источник `single`).
  Future<void> play(Track track) =>
      playQueue([track], 0, source: PlainSource.single(track));

  /// Поставить очередь волны. Отдельно от [playQueue] ради перемешки: волна
  /// САМА выбирает порядок, и перетасовать её значило бы выбросить работу
  /// подбора. Флаг снимаем, как `host.shuffle = false` на десктопе.
  Future<void> playWave(List<Track> tracks, WaveSource source) {
    state = state.copyWith(shuffle: false);
    return _start(tracks, 0, source: source, orig: null);
  }

  /// Дописать пачку в конец очереди — догрузка волны. От [addToQueue]
  /// отличается тем, что треков много и уже стоящие в очереди пропускаются
  /// молча: подбор мог предложить то, что там уже есть.
  void appendToQueue(List<Track> tracks) => _append(tracks);

  /// Дописать и вернуть, сколько реально встало.
  int _append(List<Track> tracks) {
    if (tracks.isEmpty || state.queue.isEmpty) return 0;
    final have = {for (final t in state.queue) t.id};
    final add = [
      for (final t in tracks)
        if (have.add(t.id)) t,
    ];
    if (add.isEmpty) return 0;
    final q = [...state.queue, ...add];
    final orig = _origQueue;
    if (orig != null) _origQueue = [...orig, ...add];
    state = state.copyWith(queue: q);
    _handler.setQueue(q);
    _saveResume();
    return add.length;
  }

  /// «Авто похожие»: дописать продолжение, и очередь становится волной — дальше
  /// она догружается сама. Текущий трек не трогаем, он доигрывает. Перемешку
  /// снимаем без отката к снимку «до перемешки»: волна сама задаёт порядок, а
  /// откат выкинул бы только что дописанное. Возвращает, встало ли что-то.
  bool continueAsWave(List<Track> tracks, WaveSource source) {
    if (_append(tracks) == 0) return false;
    _origQueue = null;
    state = state.copyWith(source: source, shuffle: false);
    _saveResume();
    return true;
  }

  /// Продолжить прошлую сессию — очередь из снимка, с той же позиции
  /// (карточка «Продолжить» на главной). Порт `restoreResumeQueue`.
  ///
  /// Снимок мог быть волновым: очередь вернётся сама, а вот память подбора
  /// живёт отдельно — без неё волна доиграла бы сохранённые треки и молча
  /// встала, вместо того чтобы догрузиться.
  ///
  /// [autoplay] `false` — сессия возвращается НА ПАУЗЕ: так работает
  /// «Восстановление очереди» при запуске приложения (`Настройки → Аудио`).
  Future<void> resumeSession(ResumeData data, {bool autoplay = true}) {
    ref.read(waveProvider.notifier).adoptRestored(data.source);
    return _resume(data, autoplay: autoplay);
  }

  Future<void> _resume(ResumeData data, {bool autoplay = true}) {
    // Режимы ставим ДО очереди: `_start` их не трогает, а `_load` уже смотрит
    // на повтор. Порядок очереди в снимке — тот самый, тасованный, так что
    // перемешку возвращаем флагом, не перетасовывая заново.
    state = state.copyWith(
      shuffle: data.shuffle,
      smartShuffle: data.smartShuffle,
      repeat: data.repeat,
    );
    // Исходного порядка до перемешки в снимке нет (см. `ResumeData.shuffle`) —
    // `_origQueue` остаётся пустым, и выключение перемешки просто снимет флаг.
    return _start(
      data.queue,
      data.index,
      source: data.source,
      orig: null,
      // Первые пару секунд перематывать некуда — начинаем с начала трека.
      startAt: data.position > const Duration(seconds: 2)
          ? data.position
          : null,
      autoplay: autoplay,
      preClear: data.fullQueue,
    );
  }

  /// Трек, который загрузили, но играть не начали (восстановление на паузе).
  ///
  /// События «трек пошёл» — волне и Last.fm — обязаны случиться, когда звук
  /// действительно пойдёт: «сейчас играет» на паузе было бы враньём площадке, а
  /// волне отсчёт прослушивания начинать не с чего. Поэтому держим трек здесь и
  /// добираем события из [commandPlay].
  Track? _pendingStart;

  /// Id трека, у которого поток реально открылся. Нужен волне: уходя с трека,
  /// [_reportWaveTrackEnd] докладывает, сколько его слушали, — а у пропущенного
  /// слушать было нечего, и `_player.duration` к тому моменту ещё от прошлого,
  /// по-настоящему игравшего. Без этой отметки цепочка авто-скипов научила бы
  /// подбор тому, чего не было.
  String? _loadedId;

  /// [skipped] — сколько недоступных треков уже пропустили в этой цепочке.
  /// Порог — длина очереди: если не заиграл ни один, авто-скип обязан
  /// остановиться, а не крутить её по кругу (`_skipCount` на десктопе). Счётчик
  /// идёт параметром, а не полем: цепочка живёт ровно один заход, и обнулять
  /// его потом было бы негде.
  Future<void> _load(
    int index, {
    Duration? startAt,
    bool autoplay = true,
    int skipped = 0,
  }) async {
    final track = state.queue[index];
    // Уход с прошлого трека — единственный сигнал, по которому учится волна:
    // сколько его слушали, столько он и «понравился». Считаем до смены
    // состояния, пока позиция и длительность ещё от него.
    _reportWaveTrackEnd(track);
    // Куда «поехал» показ — считаем ровно здесь, на реальном переключении:
    // слои анимации в плеере и миниплеере обязаны ехать в одну сторону, а к
    // моменту перерисовки прошлый номер в очереди уже потерян.
    commitSwapDir(state.queue, index);
    final gen = ++_generation;
    // Прошлый трек умолкает СРАЗУ, а не когда доедет ссылка на новый. Источник
    // у just_audio подменяется только в setUrl — то есть после похода в сеть за
    // стримом, и всё это время в ушах играл бы старый трек, хотя в плеере уже
    // написан новый. Не ждём: pause переставляет `playing` синхронно, а команду
    // платформе шлёт сам, и задерживать ради неё загрузку незачем.
    unawaited(_player.pause());
    state = state.copyWith(index: index, loading: true, clearError: true);
    // Текущим стал другой трек — зачёт для него начинается заново, а
    // отложенный старт прошлого больше не нужен.
    _credited = false;
    _pendingStart = null;
    _autoSimilarFor = null;
    _autoSimilarPending = false;
    _autoSimilarAdvance = false;
    _queueEnded = false;
    // Название в шторке ставим сразу, не дожидаясь ссылки на стрим.
    _handler
      ..setTrack(track, queueIndex: index)
      ..setResolving(true);
    if (!_askedForNotifications) {
      _askedForNotifications = true;
      unawaited(ensureNotificationPermission());
    }
    // Путь трека до звука — по шагам и с немедленной записью на диск.
    //
    // Немедленной не для красоты: если процесс убивает нативная сторона
    // (ExoPlayer, кодек, драйвер), Dart об этом не узнаёт и дописать журнал не
    // успевает — в файле осталась бы тишина. Зато по последней доехавшей
    // строке видно, что именно не пережило: резолв ссылки, открытие потока или
    // уже само воспроизведение.
    final startedAt = DateTime.now();
    var via = 'стрим';
    logInfo(
      'player',
      'ставлю: ${track.name} · ${track.source.name}',
      now: true,
    );
    try {
      // Офлайн-копия выигрывает у сетевого стрима — как резолвер офлайна,
      // который на десктопе стоит первым в очереди. Заодно это единственный
      // способ заиграть без сети.
      final offlinePath = ref.read(offlineProvider.notifier).pathOf(track.id);
      if (offlinePath != null) {
        via = 'офлайн';
        await _player.setFilePath(offlinePath, initialPosition: startAt);
      } else if (isLocalTrack(track)) {
        via = 'свой файл';
        // Свой файл с телефона: площадки за ним нет, спрашивать некого. Копия
        // внутри приложения приходит как `file://`, чужой файл — как
        // `content://`, и тому и другому нужен общий `AudioSource.uri`.
        final uri = localTrackUri(track);
        if (uri == null) throw const LocalFileGone();
        await _player.setAudioSource(
          AudioSource.uri(uri),
          initialPosition: startAt,
        );
      } else {
        final provider = ref.read(registryProvider).forEntity(track.id);
        if (provider == null) {
          throw StateError('нет провайдера для ${track.id}');
        }
        final stream = await provider.resolveStream(track);
        if (stream == null) throw StateError('search.err.noStream');
        if (gen != _generation) return; // пользователь уже переключил трек
        logInfo(
          'player',
          'ссылка получена за '
              '${DateTime.now().difference(startedAt).inMilliseconds} мс, '
              'открываю поток',
          now: true,
        );
        await _player.setUrl(
          stream.url,
          headers: stream.headers.isEmpty ? null : stream.headers,
          initialPosition: startAt,
        );
      }
      if (gen != _generation) return;
      logInfo(
        'player',
        'поток открыт: $via · '
            '${DateTime.now().difference(startedAt).inMilliseconds} мс',
        now: true,
      );
      _loadedId = track.id;
      state = state.copyWith(loading: false);
      _handler.setResolving(false);
      if (autoplay) {
        _fireTrackStart(track);
      } else {
        // Загрузили, но не играем — события «трек пошёл» ждут первого play.
        _pendingStart = track;
      }
      // Снимок «Продолжить» — сразу на новом треке: подписка на playingStream
      // при переходе внутри очереди молчит (плеер и так играл), и до тика
      // таймера карточка звала бы обратно на прошлый трек.
      _saveResume();
      if (autoplay) logInfo('player', 'играю', now: true);
      // play() у just_audio завершается НЕ когда началось воспроизведение, а
      // когда трек доиграл (или его поставили на паузу). Ждать его нельзя:
      // `loading` тогда висит всю песню, а кнопка play остаётся спиннером.
      if (autoplay) unawaited(_player.play());
    } catch (e) {
      if (gen != _generation) return;
      final code = playErrorCode(e);
      state = state.copyWith(loading: false, error: code);
      _handler.setResolving(false);
      logError('player', 'трек не заиграл: ${track.id}', e);
      _skipUnplayable(track, code, autoplay: autoplay, skipped: skipped);
    }
  }

  /// Недоступный трек — дальше по очереди (`skipUnplayable` с ПК).
  ///
  /// Без этого очередь встаёт намертво: DRM-трек не заиграет никогда, а
  /// «дальше» пришлось бы жать руками на каждом.
  void _skipUnplayable(
    Track failed,
    String code, {
    required bool autoplay,
    required int skipped,
  }) {
    final q = state.queue;
    // Куда идти дальше, решаем ДО слов: тост «пропускаем» на очереди из одного
    // трека обещал бы то, чего не будет.
    //
    // Восстановление сессии на паузе (`autoplay: false`) скипом не считается:
    // играть никто не просил, и листать очередь самим на старте приложения
    // нельзя — ошибка просто остаётся на экране.
    final canSkip = autoplay && q.length > 1 && skipped + 1 < q.length;

    // Уведомление — одно на действие человека, а не по одному на каждый трек
    // очереди: дальше идёт авто-скип, и на глухой очереди список уведомлений
    // забился бы ею целиком.
    if (skipped == 0) {
      ref
          .read(notifCenterProvider.notifier)
          .add(
            kind: NotifKind.error,
            title: NotifTitle.trackUnavailable,
            body: failed.name,
          );
    }

    final l = globalL10n;
    if (l != null) {
      // Тост тоже один на цепочку. На ПК их по одному на пропущенный трек, но
      // там их разгребает стек тостов, а у нас `ScaffoldMessenger` показывает
      // строго по одному и ставит остальные в очередь: человек полминуты
      // смотрел бы на плывущие мимо плашки вместо музыки.
      final (String, ToastKind)? say = switch ((canSkip, skipped)) {
        (true, 0) => (
          isDrmError(code) ? l.playerSkipDrm : l.playerSkipUnavailable,
          ToastKind.info,
        ),
        (true, _) => null,
        // Перебрали всю очередь и не заиграл ни один.
        (false, > 0) => (l.playerNoPlayable, ToastKind.error),
        // Пропускать было некуда — тогда важна сама причина.
        (false, _) => (describePlayError(l, code), ToastKind.error),
      };
      if (say != null) {
        bloomMessengerKey.currentState?.toast(say.$1, kind: say.$2);
      }
    }

    if (!canSkip) return;
    markSwapDir(1);
    // Не ждём: цепочка скипов накручивала бы вложенные await на всю длину
    // очереди, а тому, кто позвал первый `_load`, ждать конца перебора незачем.
    unawaited(_load((state.index + 1) % q.length, skipped: skipped + 1));
  }

  /// «Трек пошёл» — тем, кто считает прослушивание.
  ///
  /// Зовётся на успешном старте, а при восстановлении сессии на паузе — из
  /// [commandPlay], когда звук действительно пойдёт (см. [_pendingStart]).
  void _fireTrackStart(Track track) {
    _pendingStart = null;
    // Волне пора решать, догружать ли пачку и не ушёл ли человек из неё.
    // Трек, который не заиграл, для подбора не событие.
    ref.read(waveProvider.notifier).onTrackStart(track);
    // Last.fm — тем же событием: «сейчас играет» имеет смысл слать только про
    // трек, который действительно заиграл, и отсюда же начинается отсчёт
    // времени для скроббла.
    ref.read(lastfmProvider.notifier).onTrackStart(track);
  }

  /// Сообщить волне, сколько наиграл трек, с которого сейчас уходим.
  ///
  /// [next] — тот, на который переключаемся: повторный заход на тот же трек
  /// (перезапуск после `stop()`, перемотка в начало) уходом не считается, иначе
  /// волна засчитала бы его как пролистнутый.
  void _reportWaveTrackEnd(Track next) {
    final prev = state.track;
    if (prev == null || prev.id == next.id) return;
    // Уходим с трека, который так и не заиграл (цепочка авто-скипов): слушать
    // его было нечего, а `_player.duration` всё ещё от прошлого — подбор
    // получил бы второй, выдуманный отзыв о нём (см. [_loadedId]).
    if (prev.id != _loadedId) return;
    final total = _player.duration;
    if (total == null || total <= Duration.zero) return;
    ref.read(waveProvider.notifier).onTrackEnd(prev, _player.position, total);
  }

  void _onCompleted() {
    // Трек доиграл до конца — засчитываем, если ещё не: короткий мог и не
    // попасть на тик с порогом.
    _credit();
    // Таймер сна «до конца трека» бьёт и повтор, и переход по очереди: его для
    // того и ставили — чтобы после ЭТОГО трека стало тихо.
    if (ref.read(sleepTimerProvider).mode == SleepMode.endOfTrack) {
      _player.seek(Duration.zero);
      _player.pause();
      ref.read(sleepTimerProvider.notifier).cancel();
      return;
    }
    if (state.repeat == PlayerRepeat.one) {
      _credited = false; // следующий круг засчитывается заново
      _player.seek(Duration.zero);
      unawaited(_player.play());
      return;
    }
    final isLast = state.index >= state.queue.length - 1;
    if (isLast && state.repeat == PlayerRepeat.off) {
      _queueEnded = true;
      _player.seek(Duration.zero);
      _player.pause();
      // Короткий трек мог кончиться раньше, чем продолжение запросили, — или
      // оно уже в пути и перейдёт на пачку само (см. [_queueEnded]).
      _maybeAutoSimilar();
      return;
    }
    next();
  }

  /// Дальше по очереди. Про перемешку тут ничего не знают: она уже переставила
  /// саму очередь (см. [toggleShuffle]), и «следующий» всегда следующий.
  Future<void> next() async {
    final q = state.queue;
    if (q.isEmpty) {
      cancelSwapSilent();
      return;
    }
    // Последний трек и включены «Авто похожие»: вместо закольцовки ждём
    // продолжение — пачка перейдёт на себя сама. Если запрос для этого трека уже
    // отработал впустую, ведём себя как раньше.
    final track = state.track;
    if (track != null &&
        state.index == q.length - 1 &&
        state.repeat == PlayerRepeat.off &&
        ref.read(settingsProvider).autoSimilar &&
        !(state.source is WaveSource && ref.read(waveProvider).active) &&
        (_autoSimilarFor != track.id || _autoSimilarPending)) {
      _autoSimilarAdvance = true;
      _maybeAutoSimilar();
      cancelSwapSilent();
      return;
    }
    // Направление задаём явно: на закольцовке (последний → первый) сравнение
    // номеров дало бы «назад».
    markSwapDir(1);
    await _load((state.index + 1) % q.length);
  }

  /// Назад: первые 3 секунды — к предыдущему треку, дальше — в начало текущего
  /// (привычное поведение транспорта).
  Future<void> prev() async {
    if (state.queue.isEmpty) {
      cancelSwapSilent();
      return;
    }
    if (_player.position > const Duration(seconds: 3)) {
      // Трек не меняется — снимаем «не анимировать» сами: жест был, а смены
      // не вышло, и флаг достался бы следующей, настоящей смене.
      cancelSwapSilent();
      await _player.seek(Duration.zero);
      return;
    }
    await prevTrack();
  }

  /// Предыдущий трек — без «первые 3 секунды в начало текущего».
  ///
  /// Нужен карусели миниплеера («Соседние треки»): человек тянет к себе
  /// карточку, которую видит, и привести она обязана именно её. Отмотка в
  /// начало на середине трека выглядела бы там как сорвавшийся жест.
  Future<void> prevTrack() async {
    final q = state.queue;
    if (q.isEmpty) {
      cancelSwapSilent();
      return;
    }
    markSwapDir(-1);
    await _load((state.index - 1 + q.length) % q.length);
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

  /// Перемешанная копия: обычная — Фишер—Йетс, умная — с весами по журналу
  /// прослушиваний.
  List<Track> _shuffled(List<Track> tracks, int keep, {required bool smart}) {
    if (!smart) return shuffledQueue(tracks, keep, _rnd);
    final stats = ref.read(playStatsProvider);
    final now = DateTime.now();
    return weightedShuffledQueue(
      tracks,
      keep,
      (t) => smartShuffleWeight(stats, t.id, now: now),
      _rnd,
    );
  }

  /// Перемешка переставляет саму очередь, а не подсовывает случайный номер в
  /// [next] — иначе список в шторке очереди врал бы о том, что пойдёт дальше.
  /// Кнопка крутит режимы: выкл → обычная → умная → выкл; выключение
  /// возвращает запомненный порядок. Порт `cycleShuffle`.
  void toggleShuffle() {
    final q = state.queue;
    if (state.shuffle && !state.smartShuffle) {
      if (q.length <= 1) {
        state = state.copyWith(smartShuffle: true);
        return;
      }
      // Обычная → умная: мешаем заново от исходного порядка, а не от уже
      // перемешанного — иначе снимок «до перемешки» потерялся бы.
      final base = _origQueue ?? [...q];
      final current = state.track;
      final at = current == null
          ? -1
          : base.indexWhere((t) => t.id == current.id);
      _origQueue = base;
      final shuffled = _shuffled(base, at, smart: true);
      state = state.copyWith(queue: shuffled, index: 0, smartShuffle: true);
      _handler
        ..setQueue(shuffled)
        ..setTrack(state.track, queueIndex: 0);
      return;
    }
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

  /// Дописать трек в конец очереди — порт десктопного `addToQueue`
  /// (`enqueue(..., 'end')`). Возвращает `false`, если трек в очереди уже стоит:
  /// второй раз он туда не встаёт, и вызывающему есть о чём сказать.
  bool addToQueue(Track track) => queueTracks([track]) > 0;

  /// Поставить трек сразу после текущего — порт `playNextInQueue`
  /// (`enqueue(..., 'next')`). Уже стоящий в очереди трек не дублируется, а
  /// переезжает на новое место.
  void playNext(Track track) => queueTracksNext([track]);

  /// «В очередь» пачкой — весь список из меню плейлиста (десктопный
  /// `addTracksToQueue`). Возвращает, сколько треков реально встало: уже
  /// стоящие в очереди пропускаются, и вызывающему есть о чём сказать.
  ///
  /// Пустую очередь дополнять нечего — набор просто начинает играть, как и на
  /// десктопе; [source] тогда становится источником очереди.
  int queueTracks(List<Track> tracks, {PlaySource? source}) {
    final batch = _dedup(tracks);
    if (batch.isEmpty) return 0;
    if (state.queue.isEmpty) {
      unawaited(playQueue(batch, 0, source: source));
      return batch.length;
    }
    final have = {for (final t in state.queue) t.id};
    final add = [
      for (final t in batch)
        if (!have.contains(t.id)) t,
    ];
    if (add.isEmpty) return 0;
    final q = [...state.queue, ...add];
    // Снимок «до перемешки» пополняем тоже: иначе выключение перемешки
    // откатило бы очередь к состоянию без добавленных треков.
    final orig = _origQueue;
    if (orig != null) _origQueue = [...orig, ...add];
    state = state.copyWith(queue: q);
    _handler.setQueue(q);
    _saveResume();
    return add.length;
  }

  /// «Играть следующими» пачкой (десктопный `playTracksNext`). Возвращает, для
  /// скольких треков это что-то изменило: играющий из пачки выпадает, он уже
  /// звучит.
  int queueTracksNext(List<Track> tracks, {PlaySource? source}) {
    final batch = _dedup(tracks);
    if (batch.isEmpty) return 0;
    if (state.queue.isEmpty) {
      unawaited(playQueue(batch, 0, source: source));
      return batch.length;
    }
    final current = state.track;
    final (q, index) = queueWithNextAll(state.queue, state.index, batch);
    if (identical(q, state.queue)) return 0;
    // Снимок «до перемешки» правим тем же способом: в нём тот же играющий трек,
    // просто в другом порядке.
    final orig = _origQueue;
    if (orig != null) {
      final at = current == null
          ? -1
          : orig.indexWhere((t) => t.id == current.id);
      _origQueue = queueWithNextAll(orig, at, batch).$1;
    }
    state = state.copyWith(queue: q, index: index);
    _handler
      ..setQueue(q)
      ..setTrack(state.track, queueIndex: index);
    _saveResume();
    return batch.where((t) => t.id != current?.id).length;
  }

  /// Пачка без повторов, в исходном порядке: один и тот же трек мог прийти из
  /// списка дважды, а в очереди ему хватит одного места.
  List<Track> _dedup(List<Track> tracks) {
    final seen = <String>{};
    return [
      for (final t in tracks)
        if (seen.add(t.id)) t,
    ];
  }

  /// Подменить трек в очереди — «Сменить площадку» заменила запись библиотеки,
  /// и очередь не должна ссылаться на исчезнувший трек.
  ///
  /// Позицию воспроизведения не трогаем: это замена ЗАПИСИ, а не «слушать
  /// сейчас» (так же на десктопе). Текущий стрим доигрывает, а дальше очередь
  /// возьмёт трек уже с новой площадки.
  void replaceInQueue(String oldId, Track next) {
    if (!state.queue.any((t) => t.id == oldId)) return;
    final q = [
      for (final t in state.queue)
        if (t.id == oldId) next else t,
    ];
    final orig = _origQueue;
    if (orig != null) {
      _origQueue = [
        for (final t in orig)
          if (t.id == oldId) next else t,
      ];
    }
    state = state.copyWith(queue: q);
    _handler.setQueue(q);
    // Подменили играющий — обновляем и то, что показано в шторке уведомления:
    // сам звук при этом не трогается.
    if (state.track?.id == next.id) {
      _handler.setTrack(state.track, queueIndex: state.index);
    }
    _saveResume();
  }

  /// Убрать трек из очереди (смахивание строки). Порт `removeFromQueue`.
  Future<void> removeAt(int index) async {
    final q = [...state.queue];
    if (index < 0 || index >= q.length) return;
    if (q.length == 1) {
      // Последний — очередь пуста, плеер сбрасываем. Очередь до очистки — для
      // «Продолжить» (если кнопкой очистки уже урезали, берём полную).
      final full = _preClearQueue ?? q;
      await commandStop();
      await _player.stop();
      // Восстанавливать в плеер после перезапуска нечего, а запись при пустой
      // очереди ничего не пишет — помечаем снимок явно, иначе удалённый трек
      // возвращался. Волна тоже закончилась: её очередь только что убрали.
      ref.read(resumeProvider.notifier).markCleared(fullQueue: full);
      ref.read(waveProvider.notifier).endSession();
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
    // Повторная очистка не должна перетереть полную очередь урезанной.
    _preClearQueue ??= state.queue.length > 1 ? state.queue : null;
    _origQueue = null;
    state = state.copyWith(queue: [track], index: 0);
    _handler
      ..setQueue([track])
      ..setTrack(track, queueIndex: 0);
    // Сама по себе очистка ни тика, ни play/pause не даёт — без записи на паузе
    // очищенная очередь вернулась бы после перезапуска.
    _saveResume();
  }

  // --- PlaybackCommands: команды из шторки, с экрана блокировки, с гарнитуры

  @override
  Future<void> commandPlay() async {
    // Идёт загрузка нового трека — играть нечего: источник в плеере ещё от
    // прошлого, и play() вернул бы в уши именно его. Загрузка доиграет до
    // старта сама.
    if (state.loading) return;
    // После stop() (смахнули шторку) источник у just_audio уже отпущен —
    // «играть» должно перезапустить трек, а не молча ничего не сделать.
    if (_player.processingState == ProcessingState.idle &&
        state.track != null) {
      await _load(state.index);
      return;
    }
    // Сессию восстановили на паузе и вот сейчас её пустили — самое время
    // сказать об этом волне и Last.fm.
    final pending = _pendingStart;
    if (pending != null) _fireTrackStart(pending);
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
  Future<void> commandToggleFav() async {
    final track = state.track;
    if (track != null) ref.read(libraryProvider.notifier).toggleFav(track);
  }

  void _syncFav() {
    final id = state.track?.id;
    _handler.setFav(id != null && ref.read(libraryProvider).isFav(id));
  }

  @override
  Future<void> commandStop() async {
    ++_generation; // отменяем резолв, который может быть в полёте
    _origQueue = null; // возвращать нечего: очереди больше нет
    // Очередь уходит, а режимы повтора и перемешивания — нет: это настройки
    // плеера, а не свойство конкретной очереди.
    state = PlaybackState(
      repeat: state.repeat,
      shuffle: state.shuffle,
      smartShuffle: state.smartShuffle,
    );
    _handler
      ..setResolving(false)
      ..setQueue(const [])
      ..setTrack(null);
  }
}
