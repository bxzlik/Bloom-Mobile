/// Панель плеера: карточка миниплеера, которая вырастает в полный экран.
///
/// Плеер здесь — не маршрут, а слой каркаса, лежащий поверх всего, включая
/// таб-бар. Причина одна: панель обязана БЫТЬ той самой карточкой над баром —
/// она растёт из неё за пальцем и в неё же схлопывается. Маршрутом так не
/// выходит: он въезжает отдельным экраном поверх карточки, и та в этот момент
/// просто прячется под ним.
///
/// Цена — всё, что маршрут давал даром, теперь делается руками:
/// - системную «назад» ловит `PopScope` в каркасе;
/// - «свернуть» в шапке плеера, тап по пилюле источника и переход на страницу
///   артиста зовут [collapsePlayerSheet];
/// - содержимое плеера строится, только когда панель начали разворачивать, и
///   умирает, когда она сложилась, — иначе текст песни просили бы у сети на
///   старте приложения, ещё до того, как плеер кто-то открыл.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/store/settings_store.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/track_flick.dart';
import '../../../shared/ui/track_swipes.dart';
import '../mini_style_store.dart';
import '../player_controller.dart';
import 'full_player.dart';
import 'mini_player.dart';

/// Сколько панель едет сама, когда её не ведут пальцем. Разворот заметно
/// длиннее свёртывания: вверх она разворачивается «показывая себя», а вниз
/// обязана убраться сразу, как только человек решил уйти.
const Duration kSheetIn = Duration(milliseconds: 320);
const Duration kSheetOut = Duration(milliseconds: 260);

/// Скорость броска (пикселей в секунду), после которой отпускание решает исход
/// само, сколько бы пути палец ни прошёл.
const double kSheetFling = 500;

/// Доля разворота, к которой содержимое плеера уже непрозрачно. Всё, что до
/// неё, видно сквозь него: заливка карточки, её строка, стекло.
const double _kBodyIn = 0.3;

/// Единственная панель приложения — её ставит каркас. Карточка миниплеера тоже
/// одна, так что второй панели взяться неоткуда.
_PlayerSheetState? _sheet;

/// Развёрнут ли плеер: панель занимает экран или едет к нему.
///
/// Отдельным сигналом, а не полем состояния: на него подписан `PopScope`
/// каркаса, и он обязан пересобираться, когда панель открылась или сложилась.
final ValueNotifier<bool> playerSheetOpen = ValueNotifier<bool>(false);

/// Развернуть плеер во весь экран.
void expandPlayerSheet() => _sheet?.expand();

/// Свернуть плеер обратно в карточку. `false` — сворачивать было нечего
/// (панель уже сложена, каркас ещё не собран).
bool collapsePlayerSheet() {
  final sheet = _sheet;
  if (sheet == null || !playerSheetOpen.value) return false;
  sheet.collapse();
  return true;
}

class PlayerSheet extends ConsumerStatefulWidget {
  const PlayerSheet({super.key});

  @override
  ConsumerState<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<PlayerSheet>
    with SingleTickerProviderStateMixin {
  /// Доля разворота: 0 — карточка над таб-баром, 1 — плеер во весь экран.
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: kSheetIn,
  )..addListener(_report);

  /// Сколько пикселей проходит верхняя кромка панели от карточки до верха
  /// экрана. По ней жест переводит палец в долю: держат именно кромку, и она
  /// обязана идти за пальцем один в один.
  double _travel = 0;

  @override
  void initState() {
    super.initState();
    _sheet = this;
  }

  @override
  void dispose() {
    if (_sheet == this) _sheet = null;
    _t.dispose();
    playerSheetOpen.value = false;
    super.dispose();
  }

  void _report() => playerSheetOpen.value = _t.value > 0;

  void expand() => _drive(true);

  void collapse() => _drive(false);

  /// Довести панель до края. Время — от остатка пути, а не полное: иначе
  /// последние проценты ползут те же 320 мс, что и весь разворот.
  void _drive(bool open) {
    final rest = open ? 1 - _t.value : _t.value;
    final full = (open ? kSheetIn : kSheetOut).inMilliseconds;
    _t.animateTo(
      open ? 1 : 0,
      duration: Duration(milliseconds: (rest * full).round().clamp(90, full)),
      curve: Curves.easeOutCubic,
    );
  }

  void _update(double dy) {
    if (_travel <= 0) return;
    _t.value = (_t.value - dy / _travel).clamp(0.0, 1.0);
  }

  /// Палец отпустили; [velocity] — вертикальная скорость в пикселях в секунду.
  void _end(double velocity) =>
      _drive(velocity.abs() > kSheetFling ? velocity < 0 : _t.value >= 0.5);

  @override
  Widget build(BuildContext context) {
    // Очередь могла опустеть под нами: смахнули последний трек в шторке очереди,
    // пришла остановка из системы. Панель тогда исчезает вместе с карточкой —
    // показывать в ней нечего, — а шторки над ней обязаны уйти следом, иначе
    // останутся висеть над пустым экраном.
    ref.listen(playbackProvider, (_, next) {
      if (next.track != null) return;
      if (_t.value > 0) {
        Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
      }
      _t.value = 0;
    });

    final track = ref.watch(playbackProvider.select((s) => s.track));
    if (track == null) return const SizedBox.shrink();

    final t = context.bloom;
    final style = ref.watch(miniStyleProvider);
    final swipes = ref.watch(swipeProvider).of(SwipeZone.mini);
    final navInset = navBarInset(context, ref.watch(settingsProvider).navStyle);
    final cardRadius = miniCardRadius(style.radius, t.radius);

    return LayoutBuilder(
      builder: (context, box) {
        final screen = box.biggest;
        // Место карточки в покое — ровно то, что держит под неё пустым нижний
        // бар каркаса (`MiniCardSlot`): поля по 8 с боков, столько же над
        // таб-баром.
        final card = Rect.fromLTWH(
          kFloatGap,
          screen.height - navInset - kFloatGap - kMiniCardHeight,
          screen.width - kFloatGap * 2,
          kMiniCardHeight,
        );
        _travel = card.top;

        // Своя группа стекла: панель лежит поверх страницы и поверх баров, и с
        // их общим снимком подложки в размытие не попало бы то, что под ней.
        return GlassGroup(
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final v = _t.value;
              final rect = Rect.lerp(card, Offset.zero & screen, v)!;
              // Строка карточки уходит быстро: панель растёт, и её содержимое
              // становится враньём уже к десятой доле пути. Плеер проявляется
              // внахлёст — он непрозрачен и сам накрывает собой то, что не
              // догорело.
              final row = 1 - const Interval(0, 0.14).transform(v);
              final body = const Interval(0.06, _kBodyIn).transform(v);

              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: TrackFlick(
                      // Перелистывание свайпом по карточке. У развёрнутого плеера
                      // свой такой же жест внутри — он и выиграет: вложенный
                      // распознаватель встаёт в очередь раньше внешнего. Гасить
                      // этот на время разворота нельзя: `TrackFlick` без обоих
                      // обработчиков меняет саму форму дерева, и содержимое
                      // панели пересобиралось бы с нуля на первом же пикселе
                      // тяги.
                      onLeft: swipes.left == SwipeAction.none
                          ? null
                          : () => runSwipeAction(
                              context,
                              ref,
                              swipes.left,
                              track: track,
                              fromFlick: true,
                            ),
                      onRight: swipes.right == SwipeAction.none
                          ? null
                          : () => runSwipeAction(
                              context,
                              ref,
                              swipes.right,
                              track: track,
                              fromFlick: true,
                            ),
                      builder: (context, shift) => FlickSlide(
                        shift: shift,
                        child: _gestures(
                          expanded: v > 0,
                          child: MiniCardSkin(
                            radius: lerpDouble(cardRadius, 0, v)!,
                            // Стекло держим, пока сквозь плеер ещё видно
                            // заливку. Дальше размывать подложку под панелью во
                            // весь экран незачем: её всё равно не видно.
                            glass: v < _kBodyIn,
                            child: Stack(
                              children: [
                                if (row > 0)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: 0,
                                    height: kMiniCardHeight,
                                    child: Opacity(
                                      opacity: row,
                                      child: const MiniCardRow(),
                                    ),
                                  ),
                                // Плеер разложен во весь экран и просто
                                // обрезается окном панели. По горизонтали он
                                // стоит на своём месте (поэтому `-rect.left`) —
                                // ползи он вместе с полями карточки, содержимое
                                // елозило бы вбок на каждом пикселе тяги. А вот
                                // верхняя кромка у них общая: шапка плеера
                                // обязана ехать вверх ВМЕСТЕ с краем панели, из
                                // этого весь разворот и читается.
                                if (body > 0)
                                  Positioned(
                                    left: -rect.left,
                                    top: 0,
                                    width: screen.width,
                                    height: screen.height,
                                    child: Opacity(
                                      opacity: body,
                                      child: const FullPlayerBody(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Тяга и тап по панели.
  ///
  /// Жест один на оба положения: снизу вверх он разворачивает карточку, сверху
  /// вниз — складывает плеер. Кнопки внутри (play в карточке, транспорт в
  /// плеере) тап забирают себе — они лежат глубже.
  Widget _gestures({required bool expanded, required Widget child}) =>
      GestureDetector(
        onTap: expanded ? null : expand,
        onVerticalDragDown: (_) => _t.stop(),
        onVerticalDragUpdate: (d) => _update(d.delta.dy),
        onVerticalDragEnd: (d) => _end(d.velocity.pixelsPerSecond.dy),
        onVerticalDragCancel: () => _end(0),
        child: child,
      );
}

/// Заливка панели — она же заливка карточки: стекло или тон обложки, рамка и
/// скругление, которое по мере разворота распрямляется в углы экрана.
class MiniCardSkin extends ConsumerWidget {
  const MiniCardSkin({
    super.key,
    required this.radius,
    required this.glass,
    required this.child,
  });

  /// Скругление углов в пикселях.
  final double radius;

  /// Пускать ли стекло. Развёрнутой панели оно ни к чему.
  final bool glass;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final style = ref.watch(miniStyleProvider);
    return GlassBox(
      color: miniCardTint(ref, style),
      // Стекло — только у фона «Тема», как на ПК (`body.glass-mode
      // .mp-bg-theme #miniPlayer`). У «Цвета обложки» заливка и так тёмная
      // (L 0.09–0.18), и полупрозрачной поверх тёмного фона она сходится с ним
      // в чёрный — настройка фона перестаёт читаться. Фон-картинка непрозрачна
      // сама по себе, и размывать под ней подложку незачем.
      enabled: glass && style.bg == MiniBg.theme,
      borderSide: BorderSide(color: t.ovlLine),
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }
}
