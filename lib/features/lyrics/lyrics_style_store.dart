/// Оформление текста песни — порт `lyricsStyle` из десктопного
/// `settings/model/playerViewStore.ts` плюс своя настройка «вид».
///
/// Поверхность у нас одна (полноэкранный плеер), поэтому и набор один: на ПК
/// их три (страница плеера, боковая панель, фуллскрин) и настраиваются они
/// порознь — там разный кегль и размер коробки.
///
/// Заливку и эффект с ПК не переносим: активная строка всегда горит целиком.
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

class LyricsStyle {
  const LyricsStyle({this.mode = LyricsMode.overlay});

  final LyricsMode mode;

  LyricsStyle copyWith({LyricsMode? mode}) =>
      LyricsStyle(mode: mode ?? this.mode);
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
    );
  }

  void setMode(LyricsMode mode) => _set(state.copyWith(mode: mode));

  void _set(LyricsStyle next) {
    state = next;
    ref.read(jsonStoreProvider).write('lyricsStyle', {'mode': next.mode.name});
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
