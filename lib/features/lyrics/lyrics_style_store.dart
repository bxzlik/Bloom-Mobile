/// Оформление текста песни — порт `lyricsStyle` из десктопного
/// `settings/model/playerViewStore.ts` плюс своя настройка «вид».
///
/// Поверхность у нас одна (полноэкранный плеер), поэтому и набор один: на ПК
/// их три (страница плеера, боковая панель, фуллскрин) и настраиваются они
/// порознь — там разный кегль и размер коробки.
///
/// Две независимые оси заливки и эффекта — тоже с ПК. ЗАЛИВКА отвечает, чем
/// меряется прогресс по активной строке, ЭФФЕКТ — как единица появляется;
/// комбинируются любые.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Куда девается обложка, когда включён текст.
enum LyricsMode {
  /// Текст ложится ПОВЕРХ обложки, в её же квадрат — как на ПК
  /// (`.lyrics-panel`, overlay внутри рамки).
  overlay,

  /// Обложка уходит совсем, текст занимает всё её место.
  replace,
}

/// Чем меряется прогресс по активной строке.
enum LyricsFill {
  /// Строка целиком, без дробления.
  line,

  /// По словам: слово переключается в свой момент.
  word,

  /// По буквам: то же, но единица — символ.
  letter,

  /// Градиент бежит ВНУТРИ слова за его длительность (как в Apple Music).
  wipe,
}

/// Как выглядит переход единицы.
enum LyricsFx {
  /// Сразу, сменой цвета.
  none,

  /// Единица втекает непрозрачностью.
  fade,

  /// Текущая единица подсвечивается свечением в акцент.
  glow,

  /// Текущая единица вспухает и с отдачей садится назад.
  spring,
}

class LyricsStyle {
  const LyricsStyle({
    this.mode = LyricsMode.overlay,
    this.fill = LyricsFill.word,
    this.fx = LyricsFx.none,
  });

  final LyricsMode mode;

  final LyricsFill fill;
  final LyricsFx fx;

  LyricsStyle copyWith({LyricsMode? mode, LyricsFill? fill, LyricsFx? fx}) =>
      LyricsStyle(
        mode: mode ?? this.mode,
        fill: fill ?? this.fill,
        fx: fx ?? this.fx,
      );
}

final lyricsStyleProvider =
    NotifierProvider<LyricsStyleController, LyricsStyle>(
      LyricsStyleController.new,
    );

class LyricsStyleController extends Notifier<LyricsStyle> {
  @override
  LyricsStyle build() {
    final raw = ref.read(jsonStoreProvider).readMap('lyricsStyle');
    const def = LyricsStyle();
    return LyricsStyle(
      mode: _fromName(LyricsMode.values, raw['mode'], def.mode),
      fill: _fromName(LyricsFill.values, raw['fill'], def.fill),
      fx: _fromName(LyricsFx.values, raw['fx'], def.fx),
    );
  }

  void setMode(LyricsMode mode) => _set(state.copyWith(mode: mode));
  void setFill(LyricsFill fill) => _set(state.copyWith(fill: fill));
  void setFx(LyricsFx fx) => _set(state.copyWith(fx: fx));

  void _set(LyricsStyle next) {
    state = next;
    ref.read(jsonStoreProvider).write('lyricsStyle', {
      'mode': next.mode.name,
      'fill': next.fill.name,
      'fx': next.fx.name,
    });
  }
}

/// Значение из хранилища по имени. Незнакомое (правили файл руками, откат на
/// старую сборку) молча заменяем умолчанием — оформление текста не повод
/// ронять запуск.
T _fromName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}
