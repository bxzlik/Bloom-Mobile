/// Плавающая пилюля «Сейчас играет» над трек-листом — порт десктопной
/// `.lib-jump` из `LibTracklist.tsx`.
///
/// Всплывает, когда играющий трек уехал за пределы видимой части списка, и по
/// тапу возвращает прокрутку к нему. Строки играющего трека в дереве может не
/// быть вовсе (список ленивый), поэтому её место считается по модели — верх
/// строки отдаёт `rowTopOf`, — а не ищется по ключу, как на ПК считает
/// `win.offsetOf`, а не `querySelector`.
///
/// Вид пилюли не десктопный: там обложка с названием и артистом, здесь —
/// эквалайзер и одна надпись. Так он попросил.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/glass.dart';

/// На сколько строка должна уехать за край видимой части, чтобы пилюля
/// появилась. Полторы строки запаса — чтобы она не мигала, когда трек стоит
/// ровно на границе (десктопный `JUMP_SHOW_GAP`).
const double kJumpShowGap = kTrackRowHeight * 1.5;

/// Просвет над строкой при возврате к ней: она встаёт не впритык под прилипшей
/// шапкой, а с контекстом (десктопный `JUMP_SCROLL_MARGIN`).
const double kJumpScrollMargin = kTrackRowHeight;

/// Дальше этого расстояния плавная прокрутка длится неприлично долго — прыгаем
/// сразу (десктопный `JUMP_SMOOTH_MAX`).
const double kJumpSmoothMax = 4000;

/// Куда уехала строка играющего трека: `0` — видна, пилюля не нужна, `-1` —
/// выше видимой части, `1` — ниже.
///
/// [rowTop] — верх строки в координатах прокрутки; `null` значит, что этого
/// трека в списке нет. Видимая часть срезана сверху прилипшей шапкой
/// ([topInset]), снизу — нижними барами каркаса ([bottomInset]): строка под
/// миниплеером не видна, и считать её видимой нельзя.
int nowPlayingJumpDir({
  required double? rowTop,
  required double offset,
  required double viewport,
  required double topInset,
  required double bottomInset,
}) {
  if (rowTop == null || viewport <= 0) return 0;
  final top = offset + topInset;
  final bottom = offset + viewport - bottomInset;
  if (rowTop + kTrackRowHeight < top - kJumpShowGap) return -1;
  if (rowTop > bottom + kJumpShowGap) return 1;
  return 0;
}

/// Прокрутка, при которой строка [rowTop] встаёт под прилипшей шапкой с
/// просветом [kJumpScrollMargin] над собой.
double nowPlayingJumpTarget({
  required double rowTop,
  required double topInset,
  required double min,
  required double max,
}) => (rowTop - topInset - kJumpScrollMargin).clamp(min, math.max(min, max));

class NowPlayingJump extends ConsumerStatefulWidget {
  const NowPlayingJump({
    super.key,
    required this.controller,
    required this.rowTopOf,
    required this.topInset,
  });

  /// Контроллер того самого списка, над которым висит пилюля.
  final ScrollController controller;

  /// Верх строки трека в координатах прокрутки; `null` — трека в списке нет.
  final double? Function(String trackId) rowTopOf;

  /// Высота сжатой шапки: она прилипла к верху и закрывает собой начало списка.
  final double topInset;

  @override
  ConsumerState<NowPlayingJump> createState() => _NowPlayingJumpState();
}

class _NowPlayingJumpState extends ConsumerState<NowPlayingJump> {
  /// Последнее посчитанное направление — см. [nowPlayingJumpDir].
  int _dir = 0;

  /// Высота нижних баров с последнего кадра: прокрутка случается между
  /// кадрами, а `MediaQuery` там уже не спросить.
  double _bottomInset = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(NowPlayingJump old) {
    super.didUpdateWidget(old);
    if (old.controller == widget.controller) return;
    old.controller.removeListener(_onScroll);
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  /// На прокрутку виджет перестраивается ТОЛЬКО когда направление сменилось:
  /// пилюля с живым эквалайзером внутри — не то, что стоит собирать заново на
  /// каждый пиксель.
  void _onScroll() {
    final next = _eval(ref.read(playbackProvider).track);
    if (next != _dir) setState(() => _dir = next);
  }

  int _eval(Track? cur) {
    final c = widget.controller;
    if (cur == null || !c.hasClients) return 0;
    final pos = c.position;
    // Первый кадр строится ДО раскладки списка: позиция у контроллера уже есть,
    // а размеров в ней ещё нет, и спрашивать их — `Null check operator used on
    // a null value`. Пересчитаем после кадра, см. [build].
    if (!pos.hasPixels || !pos.hasViewportDimension) return 0;
    return nowPlayingJumpDir(
      rowTop: widget.rowTopOf(cur.id),
      offset: pos.pixels,
      viewport: pos.viewportDimension,
      topInset: widget.topInset,
      bottomInset: _bottomInset,
    );
  }

  void _jump() {
    final cur = ref.read(playbackProvider).track;
    final c = widget.controller;
    if (cur == null || !c.hasClients) return;
    final pos = c.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    final rowTop = widget.rowTopOf(cur.id);
    if (rowTop == null) return;
    final target = nowPlayingJumpTarget(
      rowTop: rowTop,
      topInset: widget.topInset,
      min: pos.minScrollExtent,
      max: pos.maxScrollExtent,
    );
    if ((target - pos.pixels).abs() > kJumpSmoothMax) {
      c.jumpTo(target);
      return;
    }
    c.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final cur = ref.watch(playbackProvider).track;
    final playing = ref.watch(playingProvider).value ?? false;
    _bottomInset = bottomBarsInset(context);
    _dir = _eval(cur);
    final show = _dir != 0;
    // Первый кадр строится до раскладки списка — там у контроллера ещё нет
    // позиции, и [_eval] честно возвращает 0. Прокрутки, которая пересчитала бы
    // направление, может и не случиться (список открыли уже прокрученным —
    // например, ушли в трек-лист прямо из плеера), поэтому считаем ещё раз
    // после кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });

    return IgnorePointer(
      ignoring: !show,
      child: AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, 0.45),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          // Скругление полное, а не радиусом темы: это пилюля, как кнопки-
          // пилюли шапки, — его правка по живому виду.
          child: GlassBox(
            shape: StadiumBorder(side: BorderSide(color: t.ovlLine)),
            child: InkWell(
              onTap: _jump,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                child: SizedBox(
                  height: 38,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Эквалайзер замирает вместе с музыкой — он же говорит,
                      // на паузе трек или играет.
                      EqualizerBars(playing: show && playing),
                      const SizedBox(width: 10),
                      Text(
                        context.l.tlJumpToNow,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      BloomIcon(
                        _dir < 0 ? Bi.arrowUp : Bi.arrowDown,
                        size: 17,
                        color: t.text2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
