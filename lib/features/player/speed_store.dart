/// Скорость воспроизведения — порт десктопного `player/model/speedStore.ts`.
///
/// Пресеты, границы, шаг и округление те же, что на ПК: одна и та же цифра
/// должна давать одно и то же и там, и здесь. Nightcore — десктопное
/// `preservesPitch: false`: тон едет вместе с темпом; выключен (умолчание) —
/// тон сохраняется.
///
/// Стор ЧИСТЫЙ: про плеер он не знает, его дело — значение и персист. На сам
/// `AudioPlayer` настройку ставит `PlaybackController` (он один владеет
/// плеером), подписавшись на этот провайдер, — как `bootstrapSpeed` +
/// `audioEngine.setPlaybackRate` на десктопе.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Пресеты-карточки пикера: медленно / обычно / быстро.
const List<double> kSpeedPresets = [0.75, 1, 1.25];

/// Границы и шаг слайдера произвольной скорости.
const double kSpeedMin = 0.5;
const double kSpeedMax = 2;
const double kSpeedStep = 0.05;

/// Засечки под полосой — каждые 0.25×. Совпавшие с пресетами рисуем крупнее.
const List<double> kSpeedTicks = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

/// Число делений слайдера между [kSpeedMin] и [kSpeedMax].
int get kSpeedDivisions => ((kSpeedMax - kSpeedMin) / kSpeedStep).round();

/// Округление до шага слайдера + клемп: 0.05 в double даёт хвосты, и без
/// округления до сотых на диск уезжало бы `1.3000000000000003`.
double clampRate(double rate) {
  if (!rate.isFinite) return 1;
  final snapped = (rate / kSpeedStep).round() * kSpeedStep;
  final rounded = (snapped * 100).round() / 100;
  return rounded.clamp(kSpeedMin, kSpeedMax);
}

/// `1×`, `1.35×` — без хвостовых нулей (десктопный `speedLabel`).
String speedLabel(double rate) {
  var text = rate.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return '$text×';
}

class SpeedSettings {
  const SpeedSettings({this.rate = 1, this.nightcore = false});

  /// Текущая скорость воспроизведения ([kSpeedMin]…[kSpeedMax]).
  final double rate;

  /// Nightcore: питч едет за темпом. Выключен — тон сохраняется.
  final bool nightcore;

  /// Множитель питча для плеера. Выключенный nightcore — ровно 1: тон
  /// сохраняется сам (ExoPlayer тянет темп через sonic).
  double get pitch => nightcore ? rate : 1;

  SpeedSettings copyWith({double? rate, bool? nightcore}) => SpeedSettings(
    rate: rate ?? this.rate,
    nightcore: nightcore ?? this.nightcore,
  );
}

final speedProvider = NotifierProvider<SpeedController, SpeedSettings>(
  SpeedController.new,
);

class SpeedController extends Notifier<SpeedSettings> {
  static const _key = 'speed';

  @override
  SpeedSettings build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    final rate = raw['rate'];
    return SpeedSettings(
      // Битую запись (правили файл руками) молча заменяем на 1×: скорость не
      // повод ронять запуск.
      rate: rate is num ? clampRate(rate.toDouble()) : 1,
      nightcore: raw['nightcore'] == true,
    );
  }

  void setRate(double rate) {
    final value = clampRate(rate);
    if (value == state.rate) return;
    state = state.copyWith(rate: value);
    _save();
  }

  /// Сброс на 1× — тап по пилюле текущего значения (десктопный `sp-cur`).
  void reset() => setRate(1);

  void setNightcore(bool on) {
    if (on == state.nightcore) return;
    state = state.copyWith(nightcore: on);
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, {
    'rate': state.rate,
    'nightcore': state.nightcore,
  });
}
