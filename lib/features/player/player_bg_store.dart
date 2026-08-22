/// Фон полноэкранного плеера — наша мобильная настройка, на ПК её нет.
///
/// Три варианта: размытая обложка трека, адаптивный градиент по её цвету и
/// «Нет» — то, как плеер выглядел до настройки. Умолчание именно «Нет»: у
/// фона мини-плеера оно такое же (`MiniBg.theme`), и тот, кто настройку не
/// открывал, не должен однажды получить перекрашенный плеер.
///
/// Настройка про ПОЛНОЭКРАННЫЙ плеер и только про него: карточка над таб-баром
/// красится своей («Мини-плеер → Фон»), а обои из «Кастомизации» в плеер по
/// прямому слову пользователя не пускаются вовсе.
library;

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;
import '../settings/cover_accent.dart';

/// Что видно за обложкой и кнопками плеера. Порядок — тот, в каком варианты
/// стоят в шторке: сперва самое заметное.
enum PlayerBg {
  /// Размытая и притемнённая обложка трека во весь экран.
  cover,

  /// Градиент от цвета обложки сверху к цвету темы внизу.
  color,

  /// Ничего: заливка темы, как было до настройки.
  none;

  bool get isNone => this == PlayerBg.none;
}

final playerBgProvider = NotifierProvider<PlayerBgController, PlayerBg>(
  PlayerBgController.new,
);

class PlayerBgController extends Notifier<PlayerBg> {
  @override
  PlayerBg build() {
    final raw = ref.read(jsonStoreProvider).read('playerBg');
    // Незнакомая запись (правили файл руками, откат на старую сборку) молча
    // становится «Нет» — фон не повод ронять запуск.
    for (final mode in PlayerBg.values) {
      if (mode.name == raw) return mode;
    }
    return PlayerBg.none;
  }

  void set(PlayerBg mode) {
    if (mode == state) return;
    state = mode;
    ref.read(jsonStoreProvider).write('playerBg', mode.name);
  }
}

/// Цвет фона плеера в режиме «Цвет» — верхняя точка градиента.
///
/// Ключ — сама ссылка на обложку, а не трек: в плеере может стоять своя
/// картинка из «Кастомизации», и считать цвет надо с той, что видно. `null` —
/// обложки нет или её не прочитать; тогда фона просто не будет.
final playerBgColorProvider = FutureProvider.autoDispose
    .family<Color?, String?>((ref, cover) async {
      final hsl = await extractCoverHsl(cover);
      return hsl == null ? null : playerBgFromHsl(hsl);
    });
