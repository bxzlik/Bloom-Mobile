/// Фон полноэкранного плеера: размытая обложка или градиент по её цвету.
///
/// Слой лежит ПОД всем содержимым плеера и поверх заливки темы. Блоки плеера
/// (транспорт, ряд инструментов) красятся плёнкой `ovlBg` в считанные проценты
/// — они и должны проступать на фоне подкрашенными, а не закрывать его собой.
///
/// Рисуется внутри плеера, а не под панелью: панель растёт из карточки
/// миниплеера и обрезает содержимое своим окном — так фон приезжает вместе с
/// плеером и ровно по его границам, без второго слоя, который надо было бы
/// гасить синхронно с разворотом.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/cover_store.dart';
import '../../customization/custom_store.dart';
import '../player_bg_store.dart';
import '../player_controller.dart';

/// Размытие фоновой обложки, σ. Крупное: узнаваться должна не картинка, а её
/// цветовые пятна — иначе за подписями и кнопками остаётся каша из деталей.
const double kPlayerBgBlur = 42;

/// Насколько кадр увеличен под размытием. Размытие «съедает» кромки, и без
/// запаса по краям экрана видна размазанная рамка.
const double kPlayerBgScale = 1.18;

/// Затемнение размытой обложки: сверху, посередине и у нижней кромки.
///
/// Неравномерное: внизу стоят транспорт и ряд инструментов, и белым значкам на
/// светлой обложке нужен запас контраста; вверху — одна шапка.
///
/// Заметно легче первой версии (0.46/0.56/0.72): на ТЁМНОЙ обложке — а таких
/// половина — размытая картинка и без плёнки почти чёрная, и фон читался как
/// выключенный (поймал он на «утекай»).
const List<double> kPlayerBgDim = [0.30, 0.40, 0.62];

/// Насыщенность и яркость размытой обложки плюс подъём чёрного.
///
/// Плёнкой сверху тёмную обложку не спасти — её можно только вытянуть саму:
/// множитель поднимает всё разом, слагаемое отрывает чёрное от фона темы
/// (у него светлота 0.04), а насыщенность возвращает цвет, который съедает
/// размытие, усредняя соседние пиксели.
const double kPlayerBgSaturation = 1.25;
const double kPlayerBgBrightness = 1.12;
const double kPlayerBgLift = 0.05;

/// Сколько длится перекрашивание фона на смене трека. Заметно дольше самой
/// смены обложки (420 мс): фон во весь экран, и на её скорости он мигал бы.
const Duration kPlayerBgFade = Duration(milliseconds: 620);

/// Обложка, от которой считается фон: своя из «Кастомизации» важнее обложки
/// трека — тот же порядок, что у самой обложки в плеере (`coverOverride`).
String? playerBgCover(WidgetRef ref) =>
    ref.watch(customSrcProvider(CustomCtx.cover)) ??
    ref.watch(playbackProvider.select((s) => s.track?.cover));

/// Цвета градиента режима «Цвет» сверху вниз.
///
/// Верх — сам цвет обложки, низ уходит в цвет темы, но НЕ доходит до него: с
/// чистым `bg` внизу нижняя треть экрана выглядела бы так, будто фон выключен.
List<Color> playerBgGradient(Color color, Color bg) => [
  color,
  Color.lerp(color, bg, 0.5)!,
  Color.lerp(color, bg, 0.88)!,
];

/// Границы этих цветов. Середина смещена вверх: обложка занимает верхнюю
/// половину экрана, и цвет должен держаться на ней, а гаснуть уже под ней.
const List<double> kPlayerBgStops = [0, 0.5, 1];

class PlayerBackdrop extends ConsumerWidget {
  const PlayerBackdrop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playerBgProvider);
    if (mode.isNone) return const SizedBox.shrink();
    final cover = playerBgCover(ref);
    // Своя граница перерисовки: под фоном каждую секунду тикает время и ползёт
    // полоса прогресса, а размывать картинку и пересчитывать градиент на каждый
    // их кадр незачем.
    return RepaintBoundary(
      child: switch (mode) {
        PlayerBg.cover => _CoverWash(cover: cover),
        PlayerBg.color => _ColorWash(cover: cover),
        PlayerBg.none => const SizedBox.shrink(),
      },
    );
  }
}

/// Режим «Цвет»: градиент от доминанта обложки к цвету темы.
///
/// Цвет считается асинхронно (картинку надо загрузить и просканировать),
/// поэтому первый кадр честно рисуется цветом темы, а приезжающий доминант
/// вплывает [kPlayerBgFade]. Тем же переходом фон перекрашивается на смене
/// трека — [TweenAnimationBuilder] сам стартует от того, что сейчас на экране.
class _ColorWash extends ConsumerWidget {
  const _ColorWash({required this.cover});

  final String? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    // Обложки нет или её не прочитать — целимся в цвет темы: градиент от него
    // же к нему же невидим, и фон просто не появляется.
    final target = ref.watch(playerBgColorProvider(cover)).value ?? t.bg;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: kPlayerBgFade,
      curve: Curves.easeOut,
      builder: (context, color, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: playerBgGradient(color ?? t.bg, t.bg),
            stops: kPlayerBgStops,
          ),
        ),
      ),
    );
  }
}

/// Режим «Обложка»: та же картинка во весь экран, размытая и притемнённая.
///
/// Кадры сменяются наплывом, а не подменой: [AnimatedSwitcher] по ссылке на
/// обложку. Затемнение стоит СНАРУЖИ переключателя — иначе на середине наплыва
/// две плёнки складывались бы и фон проваливался в чёрный.
class _CoverWash extends StatelessWidget {
  const _CoverWash({required this.cover});

  final String? cover;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: kPlayerBgFade,
          child: KeyedSubtree(
            key: ValueKey(cover),
            child: BlurredCover(image: coverImage(cover)),
          ),
        ),
        const IgnorePointer(child: _Dim()),
      ],
    );
  }
}

/// Сама размытая картинка во весь отведённый ей прямоугольник.
///
/// Публичный (и берёт готовый [ImageProvider], а не ссылку) ради теста: сеть в
/// тестах молчит, и подсунуть картинку иначе нечем — а проверять тут надо
/// именно РАЗМЕР. Первая версия его и провалила: `AnimatedSwitcher` кладёт
/// детей в `Stack` со СВОБОДНЫМИ ограничениями, `Image` без заданных сторон
/// брал размер самой картинки, и вместо фона во весь экран посреди него стоял
/// размытый квадрат — на тёмной обложке этого было просто не видно.
class BlurredCover extends StatelessWidget {
  const BlurredCover({super.key, required this.image});

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) return const SizedBox.shrink();
    return SizedBox.expand(
      child: ClipRect(
        child: ImageFiltered(
          // `TileMode.decal` дал бы прозрачную кромку; `clamp` растягивает
          // крайние пиксели, а увеличение сверху уводит саму кромку за экран.
          imageFilter: ui.ImageFilter.blur(
            sigmaX: kPlayerBgBlur,
            sigmaY: kPlayerBgBlur,
          ),
          child: Transform.scale(
            scale: kPlayerBgScale,
            child: ColorFiltered(
              colorFilter: playerBgFilter(),
              child: Image(
                image: image,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Насыщенность × яркость + подъём чёрного одной матрицей.
///
/// Веса яркости каналов — те же, что у CSS-фильтра `saturate` (и у фона
/// карточки миниплеера). Слагаемое идёт в шкале 0–255: столько прибавляется к
/// каналу ПОСЛЕ умножения.
ColorFilter playerBgFilter() {
  const lr = 0.2126;
  const lg = 0.7152;
  const lb = 0.0722;
  const s = kPlayerBgSaturation;
  const b = kPlayerBgBrightness;
  double diag(double weight) => b * (weight + (1 - weight) * s);
  double off(double weight) => b * (weight * (1 - s));
  const lift = kPlayerBgLift * 255;
  return ColorFilter.matrix(<double>[
    diag(lr), off(lg), off(lb), 0, lift, //
    off(lr), diag(lg), off(lb), 0, lift, //
    off(lr), off(lg), diag(lb), 0, lift, //
    0, 0, 0, 1, 0, //
  ]);
}

/// Плёнка поверх размытой обложки. Чёрная, а не цвета темы: под ней картинка,
/// а не поверхность интерфейса, и тон темы подкрашивал бы её.
class _Dim extends StatelessWidget {
  const _Dim();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          for (final alpha in kPlayerBgDim)
            Colors.black.withValues(alpha: alpha),
        ],
        stops: const [0, 0.45, 1],
      ),
    ),
  );
}
