/// Вид миниплеера — порт группы «Мини-плеер» из десктопного
/// `settings/model/playerViewStore.ts` (`mpBgMode`, `mpProgress`,
/// `mpCoverShape`, `mpRounded`).
///
/// Перенесены четыре настройки: фон карточки, индикаторы прогресса, форма
/// обложки и скругление границ. Пресеты и набор кнопок — следующим заходом.
///
/// Скругление на ПК — тумблер (обычный радиус ↔ pill). Здесь четыре ступени:
/// карточка над таб-баром лежит на самом виду, и между «квадратной» и
/// «пилюлей» есть за что зацепиться — промежуточные ступени на ПК просто
/// некуда было положить.
library;

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;
import '../settings/cover_accent.dart';

/// Фон карточки.
enum MiniBg {
  /// Плашка темы — то же, что у остального «хрома».
  theme,

  /// Заливка тёмным доминантом обложки.
  coverColor,

  /// Сама обложка картинкой под содержимым.
  cover,
}

/// Форма обложки в карточке.
enum MiniCoverShape { rounded, circle }

/// Скругление углов карточки.
enum MiniRadius {
  /// Прямые углы.
  none,

  /// Половина радиуса темы.
  soft,

  /// Радиус темы — как у остальных плашек.
  rounded,

  /// Пилюля: скругление в половину высоты.
  pill,
}

/// Индикаторы прогресса — набор, а не выбор: они не спорят друг с другом
/// (десктопный `mpProgress`, мульти-выбор).
class MiniProgress {
  const MiniProgress({this.line = true, this.fill = false, this.ring = false});

  /// Линия по нижней кромке карточки.
  final bool line;

  /// Заливка фона слева направо.
  final bool fill;

  /// Кольцо вокруг обложки.
  final bool ring;

  MiniProgress copyWith({bool? line, bool? fill, bool? ring}) => MiniProgress(
    line: line ?? this.line,
    fill: fill ?? this.fill,
    ring: ring ?? this.ring,
  );
}

/// Что именно включает/выключает строка в шторке «Индикаторы прогресса».
enum MiniProgressKind { line, fill, ring }

/// Кнопка в карточке. Порядок — тот, в каком они стоят в строке справа от
/// подписи (и в каком идут строки шторки).
///
/// На ПК прячется только «Лайк» (`mpHide.fav`), трио перемотки там неснимаемо:
/// в широком баре ему всегда есть место. На телефоне место как раз и кончается
/// — карточка шириной с экран, и выбор «что важнее» тут настоящий.
enum MiniButton { prev, play, next, fav }

/// Умолчание — трио перемотки, как карточка выглядела до настройки. «Лайк»
/// выключен: включённым он ужал бы подпись у всех, кто настройку не открывал.
const Set<MiniButton> kDefaultMiniButtons = {
  MiniButton.prev,
  MiniButton.play,
  MiniButton.next,
};

class MiniStyle {
  const MiniStyle({
    this.bg = MiniBg.theme,
    this.progress = const MiniProgress(),
    this.shape = MiniCoverShape.rounded,
    this.radius = MiniRadius.rounded,
    this.buttons = kDefaultMiniButtons,
  });

  final MiniBg bg;
  final MiniProgress progress;
  final MiniCoverShape shape;
  final MiniRadius radius;
  final Set<MiniButton> buttons;

  bool has(MiniProgressKind kind) => switch (kind) {
    MiniProgressKind.line => progress.line,
    MiniProgressKind.fill => progress.fill,
    MiniProgressKind.ring => progress.ring,
  };

  bool hasButton(MiniButton button) => buttons.contains(button);

  MiniStyle copyWith({
    MiniBg? bg,
    MiniProgress? progress,
    MiniCoverShape? shape,
    MiniRadius? radius,
    Set<MiniButton>? buttons,
  }) => MiniStyle(
    bg: bg ?? this.bg,
    progress: progress ?? this.progress,
    shape: shape ?? this.shape,
    radius: radius ?? this.radius,
    buttons: buttons ?? this.buttons,
  );
}

final miniStyleProvider = NotifierProvider<MiniStyleController, MiniStyle>(
  MiniStyleController.new,
);

class MiniStyleController extends Notifier<MiniStyle> {
  @override
  MiniStyle build() {
    final raw = ref.read(jsonStoreProvider).readMap('miniStyle');
    final progress = raw['progress'];
    return MiniStyle(
      bg: _enumFromJson(MiniBg.values, raw['bg'], MiniBg.theme),
      progress: progress is Map
          ? MiniProgress(
              // Ключа могло не быть вовсе (первая сборка с настройкой) —
              // тогда берём умолчание, а не «выключено».
              line: progress['line'] as bool? ?? true,
              fill: progress['fill'] as bool? ?? false,
              ring: progress['ring'] as bool? ?? false,
            )
          : const MiniProgress(),
      shape: _enumFromJson(
        MiniCoverShape.values,
        raw['shape'],
        MiniCoverShape.rounded,
      ),
      radius: _enumFromJson(
        MiniRadius.values,
        raw['radius'],
        MiniRadius.rounded,
      ),
      // Ключа нет — умолчание; пустой список — это ВЫБОР «ни одной кнопки», и
      // подменять его умолчанием нельзя.
      buttons: raw['buttons'] is List
          ? {
              for (final button in MiniButton.values)
                if ((raw['buttons']! as List).contains(button.name)) button,
            }
          : kDefaultMiniButtons,
    );
  }

  void setBg(MiniBg bg) => _set(state.copyWith(bg: bg));

  void setShape(MiniCoverShape shape) => _set(state.copyWith(shape: shape));

  void setRadius(MiniRadius radius) => _set(state.copyWith(radius: radius));

  void toggleProgress(MiniProgressKind kind, bool on) => _set(
    state.copyWith(
      progress: switch (kind) {
        MiniProgressKind.line => state.progress.copyWith(line: on),
        MiniProgressKind.fill => state.progress.copyWith(fill: on),
        MiniProgressKind.ring => state.progress.copyWith(ring: on),
      },
    ),
  );

  void toggleButton(MiniButton button, bool on) {
    final buttons = {...state.buttons};
    if (on) {
      buttons.add(button);
    } else {
      buttons.remove(button);
    }
    _set(state.copyWith(buttons: buttons));
  }

  void _set(MiniStyle next) {
    state = next;
    ref.read(jsonStoreProvider).write('miniStyle', {
      'bg': next.bg.name,
      'progress': {
        'line': next.progress.line,
        'fill': next.progress.fill,
        'ring': next.progress.ring,
      },
      'shape': next.shape.name,
      'radius': next.radius.name,
      'buttons': [
        for (final button in MiniButton.values)
          if (next.buttons.contains(button)) button.name,
      ],
    });
  }
}

/// Значение перечисления из хранилища. Битую или незнакомую запись (правили
/// файл руками, откат на старую сборку) молча заменяем умолчанием — вид
/// карточки не повод ронять запуск.
T _enumFromJson<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

/// Тёмный доминант обложки — фон карточки в режиме «Цвет обложки».
///
/// Ключ — сама ссылка на обложку, а не трек: карточка может показывать свою
/// картинку из «Кастомизации», и считать цвет надо с той, что видно. `null` —
/// обложки нет или её не удалось прочитать; тогда фон остаётся плашкой темы.
final miniCoverColorProvider = FutureProvider.autoDispose
    .family<Color?, String?>((ref, cover) async {
      final hsl = await extractCoverHsl(cover);
      return hsl == null ? null : miniBgFromHsl(hsl);
    });
