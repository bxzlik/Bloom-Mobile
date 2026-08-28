/// Фон полноэкранного плеера — наша мобильная настройка, на ПК её нет.
///
/// Три варианта: размытая обложка трека, адаптивный градиент по её цвету и
/// «Нет» — то, как плеер выглядел до настройки. Умолчание именно «Нет»: у
/// фона мини-плеера оно такое же (`MiniBg.theme`), и тот, кто настройку не
/// открывал, не должен однажды получить перекрашенный плеер.
///
/// Настройка про ПОЛНОЭКРАННЫЙ плеер и только про него: карточка над таб-баром
/// красится своей («Мини-плеер → Фон»).
///
/// Обои из «Кастомизации» сюда приходят ОТДЕЛЬНЫМ вариантом ([PlayerBg.app]) и
/// только по прямому выбору: сами собой в плеер они по-прежнему не лезут.
library;

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;
import '../customization/custom_store.dart';
import '../customization/media_store.dart';
import '../settings/cover_accent.dart';

/// Что видно за обложкой и кнопками плеера. Порядок — тот, в каком варианты
/// стоят в шторке: сперва самое заметное.
enum PlayerBg {
  /// Обложка трека во весь экран. Что с ней делать — размывать, притемнять или
  /// оставить как есть, — решает [CoverBgFx].
  cover,

  /// Та же картинка, что стоит фоном приложения, — теми же размытием и
  /// затемнением, что у неё в «Кастомизации».
  app,

  /// Градиент от цвета обложки сверху к цвету темы внизу.
  color,

  /// Ничего: заливка темы, как было до настройки.
  none;

  bool get isNone => this == PlayerBg.none;

  bool get isCover => this == PlayerBg.cover;
}

/// Что делаем с обложкой, когда она стоит фоном плеера ([PlayerBg.cover]).
///
/// Настройка появилась после самого фона: размытие во весь экран — не
/// единственный способ поставить обложку за плеер, а один из трёх, и выбирать
/// между ними должен он, а не константа `kPlayerBgBlur`.
///
/// Порядок — тот, в каком варианты стоят в шторке: от самого спокойного к
/// самому голому.
enum CoverBgFx {
  /// Чёткая обложка под той же плёнкой затемнения — видно саму картинку, а
  /// подписи и кнопки поверх неё держатся на плёнке.
  dim,

  /// Глубокое размытие: цветовые пятна вместо картинки. Так фон выглядел до
  /// появления этой настройки — потому и умолчание.
  blur,

  /// Обложка как есть: ни размытия, ни плёнки, ни цветокоррекции.
  original;

  bool get isBlur => this == CoverBgFx.blur;

  bool get isOriginal => this == CoverBgFx.original;
}

final coverBgFxProvider = NotifierProvider<CoverBgFxController, CoverBgFx>(
  CoverBgFxController.new,
);

class CoverBgFxController extends Notifier<CoverBgFx> {
  @override
  CoverBgFx build() {
    final raw = ref.read(jsonStoreProvider).read('playerBgCoverFx');
    // Незнакомая запись — молча размытие: ровно то же правило, что у самого
    // [PlayerBgController], и по той же причине.
    for (final fx in CoverBgFx.values) {
      if (fx.name == raw) return fx;
    }
    return CoverBgFx.blur;
  }

  void set(CoverBgFx fx) {
    if (fx == state) return;
    state = fx;
    ref.read(jsonStoreProvider).write('playerBgCoverFx', fx.name);
  }
}

/// Картинка для [PlayerBg.app] — она же решает, доступен ли сам вариант.
///
/// Берём СТРОГО картинку из библиотеки («Кастомизация» → «Фон»): «Обложка
/// трека как фон» сюда не подмешивается — для неё есть [PlayerBg.cover]. Пусто
/// — вариант в шторке гашеный: ставить его, пока фон приложения не выбран,
/// незачем (его слово).
final playerAppBgProvider = Provider<MediaItem?>(
  (ref) => ref.watch(customItemProvider(CustomCtx.bg)),
);

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
