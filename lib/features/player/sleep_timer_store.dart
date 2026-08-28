/// Таймер сна: через сколько сама встанет пауза. Своя мобильная вещь — на
/// десктопе таймера нет вовсе, портировать нечего.
///
/// Стор ЧИСТЫЙ, как `speed_store`: он знает только про время и режим, а паузу и
/// затухание громкости делает `PlaybackController` (он один владеет плеером),
/// подписавшись на этот провайдер.
///
/// Время считается по СТЕННЫМ ЧАСАМ (`endsAt`), а не вычитанием из остатка на
/// каждом тике: тик в фоне может и опоздать, а «выключить через полчаса» должно
/// значить полчаса. Из-за этого ручная пауза таймер не останавливает — он идёт
/// дальше, как будильник.
///
/// Активный таймер на диск НЕ пишем: пережить перезапуск процесса ему незачем
/// (музыка после него всё равно молчит). В файле только настройки — затухание и
/// последнее выбранное время, чтобы ползунок открывался там, где его оставили.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Карточки-пресеты шторки.
const List<Duration> kSleepPresets = [
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(minutes: 60),
  Duration(minutes: 90),
];

/// Границы и шаг полосы «своё время», в минутах.
const int kSleepMinMinutes = 5;
const int kSleepMaxMinutes = 120;
const int kSleepStepMinutes = 5;

/// Число делений полосы.
int get kSleepDivisions =>
    (kSleepMaxMinutes - kSleepMinMinutes) ~/ kSleepStepMinutes;

/// Сколько добавляет кнопка «+5 минут» у идущего таймера.
const Duration kSleepExtend = Duration(minutes: 5);

/// Сколько длится затухание перед паузой. Отсчитывается НАЗАД от срабатывания:
/// «через 30 минут» с затуханием — это тишина ровно на тридцатой минуте, а не
/// на тридцатой с четвертью.
const Duration kSleepFade = Duration(seconds: 20);

enum SleepMode {
  /// Таймера нет.
  off,

  /// Пауза в назначенное время ([SleepTimerState.endsAt]).
  timer,

  /// Пауза, когда доиграет текущий трек, — сколько бы в нём ни осталось.
  endOfTrack,
}

class SleepTimerState {
  const SleepTimerState({
    this.mode = SleepMode.off,
    this.endsAt,
    this.remaining = Duration.zero,
    this.choice = const Duration(minutes: 30),
    this.fade = true,
  });

  final SleepMode mode;

  /// Момент срабатывания. Не `null` только в режиме [SleepMode.timer].
  final DateTime? endsAt;

  /// Остаток до срабатывания, пересчитанный на последнем тике. Ноль в режиме
  /// [SleepMode.timer] — сигнал контроллеру: пора вставать на паузу.
  final Duration remaining;

  /// Последнее выбранное время — с него открывается полоса «своё время».
  final Duration choice;

  /// Плавно уводить громкость в ноль перед паузой.
  final bool fade;

  bool get active => mode != SleepMode.off;

  /// Таймер дошёл до нуля и ждёт, пока его исполнят.
  bool get expired => mode == SleepMode.timer && remaining <= Duration.zero;

  SleepTimerState copyWith({
    SleepMode? mode,
    DateTime? endsAt,
    bool clearEndsAt = false,
    Duration? remaining,
    Duration? choice,
    bool? fade,
  }) => SleepTimerState(
    mode: mode ?? this.mode,
    endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
    remaining: remaining ?? this.remaining,
    choice: choice ?? this.choice,
    fade: fade ?? this.fade,
  );
}

/// Часы стора отдельным провайдером — чтобы тесты могли подменить «сейчас»
/// вместо того, чтобы ждать полчаса.
final sleepClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final sleepTimerProvider =
    NotifierProvider<SleepTimerController, SleepTimerState>(
      SleepTimerController.new,
    );

class SleepTimerController extends Notifier<SleepTimerState> {
  static const _key = 'sleep';

  /// Тик остатка — ради надписи на кнопке; он же доводит остаток до нуля, и по
  /// этому нулю контроллер плеера жмёт паузу.
  Timer? _tick;

  DateTime get _now => ref.read(sleepClockProvider)();

  @override
  SleepTimerState build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    final minutes = raw['minutes'];
    ref.onDispose(() => _tick?.cancel());
    return SleepTimerState(
      choice: minutes is num
          ? Duration(minutes: clampSleepMinutes(minutes.round()))
          : const Duration(minutes: 30),
      // Битую запись читаем как «затухание включено» — это умолчание.
      fade: raw['fade'] != false,
    );
  }

  /// Завести таймер на [d] — заново, с этой секунды. Ползунок зовёт этот же
  /// метод на каждое движение: срок переставляется под пальцем, отдельной
  /// кнопки «Пуск» в шторке нет.
  ///
  /// Отмену вешает на себя UI (тап по уже выбранному пресету): здесь [d]
  /// приходит и от ползунка, и совпадение с текущим выбором там ничего не
  /// значит.
  void start(Duration d) {
    _tick?.cancel();
    state = state.copyWith(
      mode: SleepMode.timer,
      endsAt: _now.add(d),
      remaining: d,
      choice: d,
    );
    _save();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  /// «До конца трека». Своего времени у режима нет — ждём `_onCompleted` в
  /// плеере, поэтому и тик здесь не нужен.
  void untilTrackEnd() {
    _tick?.cancel();
    _tick = null;
    state = state.copyWith(
      mode: SleepMode.endOfTrack,
      clearEndsAt: true,
      remaining: Duration.zero,
    );
  }

  /// «+5 минут» у идущего таймера. Считаем ОТ НАЗНАЧЕННОГО СРОКА, а не от
  /// «сейчас»: иначе нажатие за минуту до конца отняло бы четыре.
  void extend([Duration by = kSleepExtend]) {
    final endsAt = state.endsAt;
    if (state.mode != SleepMode.timer || endsAt == null) return;
    final next = endsAt.add(by);
    state = state.copyWith(endsAt: next, remaining: next.difference(_now));
    // Тик мог остановиться на нуле — если таймер продлили в последнюю секунду,
    // заводим его заново.
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void cancel() {
    _tick?.cancel();
    _tick = null;
    if (!state.active) return;
    state = state.copyWith(
      mode: SleepMode.off,
      clearEndsAt: true,
      remaining: Duration.zero,
    );
  }

  void setFade(bool on) {
    if (on == state.fade) return;
    state = state.copyWith(fade: on);
    _save();
  }

  void _onTick() {
    final endsAt = state.endsAt;
    if (state.mode != SleepMode.timer || endsAt == null) return;
    final left = endsAt.difference(_now);
    if (left <= Duration.zero) {
      // Дальше тикать нечего: ноль — это сигнал, а снимет его контроллер
      // плеера, когда встанет на паузу.
      _tick?.cancel();
      _tick = null;
      state = state.copyWith(remaining: Duration.zero);
      return;
    }
    state = state.copyWith(remaining: left);
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, {
    'minutes': state.choice.inMinutes,
    'fade': state.fade,
  });
}

/// Клемп минут к границам полосы «своё время».
int clampSleepMinutes(int minutes) =>
    minutes.clamp(kSleepMinMinutes, kSleepMaxMinutes);

/// Остаток на кнопке в ряду инструментов: `23:14` до часа и `1:05` дальше.
/// Часы и минуты вместо минут и секунд — иначе `1:05:00` не влезает в коробку
/// надписи и FittedBox сжимает её до нечитаемого.
///
/// Секунды округляем ВВЕРХ: пока звук ещё идёт, `0:00` на кнопке — враньё.
String sleepLabel(Duration left) {
  final total = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  if (total >= 3600) {
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
