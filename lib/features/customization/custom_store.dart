/// Куда применены картинки библиотеки — порт десктопного
/// `customizationStore.ts`.
///
/// Контекстов на телефоне ТРИ, а не пять: курсора здесь нет вовсе, а
/// визуализатора нет у нас (на ПК это `VizBlock`). Остались фон, обложка
/// плеера и ползунок прогресса.
///
/// Стор хранит только `id` картинок библиотеки, как на ПК хранит их пресет:
/// сама картинка живёт в [mediaLibProvider], и удаление её оттуда обязано
/// снимать контекст — этим занимается [removeMedia], единственная точка, где
/// сходятся библиотека, контексты и пресеты (десктопный каскад
/// `mediaLibStore.remove`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;
import 'media_store.dart';
import 'presets_store.dart';

/// Куда можно поставить картинку.
enum CustomCtx {
  /// Фон приложения (десктопный слой `#bgl`).
  bg,

  /// Обложка в плеере и миниплеере поверх обложки трека.
  cover,

  /// Пуговка ползунка прогресса.
  slider,
}

/// Затемнение фона у «обложки трека как фон»: своей страницы с ползунками у
/// неё нет (картинки-то в библиотеке нет), поэтому берём десктопное умолчание
/// `bgDim: 65` — без него светлая обложка съедает текст интерфейса.
const double kCoverAsBgDim = 65;

class CustomTargets {
  const CustomTargets({this.bg, this.cover, this.slider});

  final String? bg;
  final String? cover;
  final String? slider;

  String? of(CustomCtx ctx) => switch (ctx) {
    CustomCtx.bg => bg,
    CustomCtx.cover => cover,
    CustomCtx.slider => slider,
  };

  /// `next` разворачивается прямо в поле: `copyWith` с `null` не отличил бы
  /// «не трогать» от «снять», а снимать здесь нужно постоянно.
  CustomTargets with_(CustomCtx ctx, String? next) => switch (ctx) {
    CustomCtx.bg => CustomTargets(bg: next, cover: cover, slider: slider),
    CustomCtx.cover => CustomTargets(bg: bg, cover: next, slider: slider),
    CustomCtx.slider => CustomTargets(bg: bg, cover: cover, slider: next),
  };

  bool get isEmpty => bg == null && cover == null && slider == null;

  Map<String, dynamic> toJson() => {
    if (bg != null) 'bg': bg,
    if (cover != null) 'cover': cover,
    if (slider != null) 'slider': slider,
  };
}

final customProvider = NotifierProvider<CustomController, CustomTargets>(
  CustomController.new,
);

class CustomController extends Notifier<CustomTargets> {
  static const _key = 'custom';

  @override
  CustomTargets build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    String? id(String field) {
      final value = raw[field];
      return value is String && value.isNotEmpty ? value : null;
    }

    return CustomTargets(
      bg: id('bg'),
      cover: id('cover'),
      slider: id('slider'),
    );
  }

  /// Поставить картинку в контекст. Контекст держит ОДНУ картинку: поставили
  /// новую — прежняя оттуда ушла (тумблеры на странице картинки читаются
  /// именно так).
  void set(CustomCtx ctx, String? id) {
    if (state.of(ctx) == id) return;
    state = state.with_(ctx, id);
    _save();
  }

  /// Тумблер на странице картинки: включили — картинка встала в контекст,
  /// выключили — контекст снят (но только если там стоит именно она).
  void toggle(CustomCtx ctx, String id, bool on) =>
      set(ctx, on ? id : (state.of(ctx) == id ? null : state.of(ctx)));

  /// Применить снимок пресета: заданные контексты ставим, пустые НЕ трогаем —
  /// как `applyPreset` на десктопе.
  void applyTargets(CustomTargets next) {
    var value = state;
    for (final ctx in CustomCtx.values) {
      final id = next.of(ctx);
      if (id != null) value = value.with_(ctx, id);
    }
    if (value.bg == state.bg &&
        value.cover == state.cover &&
        value.slider == state.slider) {
      return;
    }
    state = value;
    _save();
  }

  /// Убрать ссылки на удалённую картинку.
  void purge(String id) {
    var value = state;
    for (final ctx in CustomCtx.values) {
      if (value.of(ctx) == id) value = value.with_(ctx, null);
    }
    if (identical(value, state)) return;
    state = value;
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, state.toJson());
}

/// Чтение провайдера — `ref.read` экрана, `container.read` теста. Так каскад
/// не привязан ни к виджету, ни к контейнеру.
typedef ReadProvider = T Function<T>(ProviderListenable<T> provider);

/// Удаление картинки из библиотеки со всем каскадом: контексты, пресеты, файл.
///
/// Живёт вне сторов намеренно — стор, который лезет в соседние сторы, на
/// десктопе тянул за собой циклические импорты (`mediaLibStore` ↔
/// `presetsStore` ↔ `customizationStore`).
void removeMedia(ReadProvider read, String id) {
  read(customProvider.notifier).purge(id);
  read(presetsProvider.notifier).purgeImage(id);
  read(mediaLibProvider.notifier).remove(id);
}

/// Картинка контекста целиком (нужна фону — у него ещё размытие и
/// затемнение). `null` — контекст пуст или картинку удалили мимо каскада.
final customItemProvider = Provider.family<MediaItem?, CustomCtx>((ref, ctx) {
  final id = ref.watch(customProvider).of(ctx);
  if (id == null) return null;
  for (final item in ref.watch(mediaLibProvider)) {
    if (item.id == id) return item;
  }
  return null;
});

/// Ссылка на картинку контекста — то, что понимает `coverImage`.
final customSrcProvider = Provider.family<String?, CustomCtx>(
  (ref, ctx) => ref.watch(customItemProvider(ctx))?.src,
);

/// Где стоит эта картинка — для значков на её плитке в библиотеке. Порядок
/// тот же, что у тумблеров на её странице.
final mediaUsageProvider = Provider.family<List<CustomCtx>, String>((ref, id) {
  final targets = ref.watch(customProvider);
  return [
    for (final ctx in CustomCtx.values)
      if (targets.of(ctx) == id) ctx,
  ];
});
