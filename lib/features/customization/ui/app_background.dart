/// Фоновый слой приложения — порт десктопного `#bgl` (`base.css` +
/// `applyBackground`/`applyBgDim`).
///
/// Слой лежит НИЖЕ всего интерфейса и рисуется один раз на всё приложение:
/// картинка на весь экран `cover`, поверх неё размытие и чёрная плёнка
/// затемнения. Числа берутся у самой картинки ([MediaItem.blur]/[MediaItem.dim]),
/// а не у общей настройки, — так решил пользователь.
///
/// Картинки нет — не рисуем ничего: `Scaffold` каркаса и так красит `bg` темы.
/// А вот когда картинка есть, страницам приходится стать прозрачными, иначе
/// фон был бы под сплошной заливкой (`_Page` в роутере и каркас смотрят на
/// [backgroundOnProvider]).
///
/// Сквозь сами плашки фон идёт только при включённой «Прозрачности»
/// (`features/settings/transparency_store.dart`) — на ПК это ровно так же
/// отдельная настройка «Интерфейса», и без неё фон виден лишь в зазорах между
/// блоками.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/cover_store.dart';
import '../../../core/store/settings_store.dart';
import '../../player/player_controller.dart';
import '../custom_store.dart';

/// Что показываем фоном: своя картинка из библиотеки либо обложка играющего
/// трека («Обложка трека как фон» в «Интерфейсе»). Оба слагаемых пустые — фона
/// нет.
///
/// Своя картинка ВАЖНЕЕ обложки: на десктопе ровно тот же порядок
/// (`if (!url && s.coverAsBg) url = shownCover()`).
final backgroundProvider = Provider<({String src, double blur, double dim})?>((
  ref,
) {
  final item = ref.watch(customItemProvider(CustomCtx.bg));
  if (item != null) {
    return (src: item.src, blur: item.blur, dim: item.dim);
  }
  if (!ref.watch(settingsProvider).coverAsBg) return null;
  final cover = ref.watch(playbackProvider).track?.cover;
  if (cover == null || cover.isEmpty) return null;
  // У обложки трека своей страницы с ползунками нет — берём десктопные
  // умолчания фона (`bgBlur: 0`, `bgDim: 65`).
  return (src: cover, blur: 0, dim: kCoverAsBgDim);
});

/// Фон включён — страницам нельзя красить себя сплошным.
final backgroundOnProvider = Provider<bool>(
  (ref) => ref.watch(backgroundProvider) != null,
);

class AppBackground extends ConsumerWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = ref.watch(backgroundProvider);
    if (bg == null) return child;
    final image = coverImage(bg.src);
    if (image == null) return child;

    // Картинка чуть крупнее экрана (десктопное `#bgl{transform:scale(1.1)}`):
    // размытие тянет края внутрь, и без запаса по краям просвечивала бы
    // пустота. Обрезка обязательна — иначе увеличенный слой вылезет за экран.
    Widget layer = Image(
      image: image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // Пока грузится и если не загрузится — фона просто нет, интерфейс
      // остаётся на своём месте.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    if (bg.blur > 0) {
      layer = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: bg.blur, sigmaY: bg.blur),
        child: layer,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(child: Transform.scale(scale: 1.1, child: layer)),
        ),
        // Плёнка затемнения — десктопный `#bgl::after`.
        if (bg.dim > 0)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: bg.dim / 100),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}
