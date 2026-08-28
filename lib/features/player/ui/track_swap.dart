/// Анимация смены трека: два слоя (уезжающий «прошлый» и приезжающий
/// «текущий») в одной коробке. Порт десктопного `player/ui/TrackSwap.tsx`
/// вместе с его стилями (`shared/styles/track-swap.css`).
///
/// Снимок прошлого трека — это ВИДЖЕТ ПРОШЛОЙ ПЕРЕРИСОВКИ: он неизменяем и
/// держит значения того момента, поэтому старая обложка и старое название
/// рисуются сами, без ручного копирования полей в состояние.
///
/// Тип анимации приходит из настроек ([TrackAnimKind]), направление слайда — из
/// `track_swap_dir.dart`: обе поверхности обязаны ехать в одну сторону.
library;

import 'package:flutter/material.dart';

import '../track_anim_store.dart';
import '../track_swap_dir.dart';

/// Ручки одной поверхности — те же числа, что в CSS-переменных на ПК
/// (`--tsw-dur`, `--tsw-fade-dur`, `--tsw-dist`).
class TrackSwapTuning {
  const TrackSwapTuning({
    required this.dur,
    required this.fadeDur,
    required this.dist,
  });

  /// Длительность слайда.
  final Duration dur;

  /// Длительность затухания. ДОЛЬШЕ слайда: там внимание держит движение, а
  /// тут — одна прозрачность.
  final Duration fadeDur;

  /// Амплитуда слайда, доля ширины слоя.
  final double dist;

  /// Полноэкранный плеер.
  static const player = TrackSwapTuning(
    dur: Duration(milliseconds: 420),
    fadeDur: Duration(milliseconds: 460),
    dist: 0.12,
  );

  /// Миниплеер: коробка маленькая, длинный слайд в ней читается как рывок —
  /// быстрее и с большей амплитудой, как `#miniPlayer .tsw` на ПК.
  static const mini = TrackSwapTuning(
    dur: Duration(milliseconds: 300),
    fadeDur: Duration(milliseconds: 340),
    dist: 0.22,
  );
}

/// Кривая движения (`--tsw-ease`).
const Curve _slideEase = Cubic(0.22, 1, 0.36, 1);

/// Кривая прозрачности (`--tsw-fade-ease`) — почти линейная. На кривой движения
/// 90% затухания проходило за первые ~15% времени, и оно выглядело мгновенной
/// подменой («как будто не работает»).
const Curve _fadeEase = Cubic(0.35, 0, 0.5, 1);

/// Доля времени, за которую приезжающий слой добирает полную непрозрачность.
/// Меньше единицы намеренно: иначе в середине сквозь два полупрозрачных слоя
/// просвечивал бы фон и кадр заметно темнел.
const double _fadeInShare = 0.55;

class TrackSwap extends StatefulWidget {
  const TrackSwap({
    super.key,
    required this.id,
    required this.kind,
    required this.child,
    this.tuning = TrackSwapTuning.player,
  });

  /// id текущего трека: его смена и запускает анимацию.
  final String? id;

  /// Тип анимации из настроек ([TrackAnimKind.none] — слоёв нет вовсе).
  final TrackAnimKind kind;

  final TrackSwapTuning tuning;

  final Widget child;

  @override
  State<TrackSwap> createState() => _TrackSwapState();
}

class _TrackSwapState extends State<TrackSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this)
    ..addStatusListener((status) {
      // Уехавший слой снимаем по концу анимации, а не по таймеру: пока он
      // висит, коробка тянет лишнее поддерево.
      if (status == AnimationStatus.completed && _prev != null) {
        setState(() => _prev = null);
      }
    });

  /// Прошлая перерисовка: id и её содержимое. Содержимое обновляем и без смены
  /// id (обложка могла поменяться сама — скачали копию, пришла картинка), иначе
  /// уезжал бы протухший кадр.
  ///
  /// Заполняются в [initState], а не инициализатором поля: `late` считается при
  /// ПЕРВОМ ОБРАЩЕНИИ, а первое обращение случается уже в `didUpdateWidget` —
  /// там `widget` новый, и «прошлый» id оказался бы равен текущему. Анимация
  /// при этом молча не играла бы никогда (поймал тест).
  String? _lastId;
  late Widget _lastChild;

  @override
  void initState() {
    super.initState();
    _lastId = widget.id;
    _lastChild = widget.child;
  }

  /// Снимок, который сейчас уезжает, и его id (нужен ключом слоя).
  Widget? _prev;
  String? _prevId;

  /// Направление этого перехода: назад — зеркально.
  bool _back = false;

  @override
  void didUpdateWidget(TrackSwap old) {
    super.didUpdateWidget(old);
    if (widget.id == _lastId) {
      _lastChild = widget.child;
      return;
    }
    final from = _lastChild;
    final fromId = _lastId;
    final hadTrack = _lastId != null;
    _lastId = widget.id;
    _lastChild = widget.child;
    // Первый трек за сессию (нечему уезжать), выключенная анимация и смена «под
    // пальцем» (её рисует сам жест) — без слоёв. setState тут не нужен:
    // `didUpdateWidget` и так идёт перед перерисовкой.
    if (widget.kind == TrackAnimKind.none || !hadTrack || swapSilent) {
      _anim.stop();
      _prev = null;
      _prevId = null;
      return;
    }
    _prev = from;
    _prevId = fromId;
    _back = swapDir < 0;
    _anim
      ..duration = widget.kind == TrackAnimKind.slide
          ? widget.tuning.dur
          : widget.tuning.fadeDur
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Сдвиг (доля ширины) и непрозрачность слоя на текущем кадре.
  /// [incoming] — приезжающий слой (иначе уезжающий).
  (double, double) _frame({required bool incoming}) {
    // В покое слой стоит на месте и виден целиком: обёртки при этом всё равно
    // остаются на месте — их появление и исчезновение пересобирало бы
    // поддерево, а с ним и картинку с бегущей строкой.
    if (_prev == null) return (0, 1);
    final value = _anim.value;
    if (widget.kind == TrackAnimKind.fade) {
      return (
        0,
        incoming
            ? _fadeEase.transform((value / _fadeInShare).clamp(0.0, 1.0))
            : 1 - _fadeEase.transform(value),
      );
    }
    final eased = _slideEase.transform(value);
    final dist = _back ? -widget.tuning.dist : widget.tuning.dist;
    // Новый приезжает со своей стороны к нулю, старый уходит в
    // противоположную — оба движутся в одну сторону, как на ПК.
    return (
      incoming ? dist * (1 - eased) : -dist * eased,
      incoming ? eased : 1 - eased,
    );
  }

  Widget _layer(Widget child, {required bool incoming}) {
    return AnimatedBuilder(
      animation: _anim,
      child: child,
      builder: (context, child) {
        final (shift, opacity) = _frame(incoming: incoming);
        return FractionalTranslation(
          translation: Offset(shift, 0),
          child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child!),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final prev = _prev;
    // Слои режем по своей коробке — десктопное `.tsw{overflow:hidden}`. Одного
    // `Stack` для этого мало: он считает переполнением только позиционированных
    // детей, а сдвиг слоя случается на покраске, уже после раскладки. Без
    // обрезки подпись миниплеера на слайде наезжала на обложку и на кнопки.
    //
    // Обрезка стоит ВСЕГДА, а не только на время анимации: обёртка, которая
    // появляется и пропадает, пересобирала бы поддерево под собой, а с ним —
    // картинку и бегущую строку.
    return ClipRect(
      child: Stack(
        // `passthrough`, а не `loose`: текущий слой обязан получить РОВНО те
        // ограничения, что достались бы самому содержимому без обёртки — иначе
        // подпись, которой в строке была задана ширина, схлопнулась бы по своему
        // тексту и уехала бы к левому краю вместо центра.
        //
        // Прошлый слой при этом уходит в Positioned.fill: высоту коробки держит
        // текущий, иначе на время анимации подпись раздваивалась бы по высоте и
        // толкала всё под собой.
        fit: StackFit.passthrough,
        children: [
          _layer(
            // Ключ по id: новый трек — новый слой, иначе Flutter обновил бы
            // старый на месте и анимации нечего было бы играть.
            KeyedSubtree(key: ValueKey(widget.id ?? '—'), child: widget.child),
            incoming: true,
          ),
          // Уезжающий слой ПОВЕРХ приезжающего: он гаснет, и «просвет» под ним
          // читается как проявление нового, а не как мигание фоном. Тапы он не
          // ловит — под ним живой слой с живыми кнопками.
          if (prev != null)
            Positioned.fill(
              child: _layer(
                IgnorePointer(
                  child: KeyedSubtree(
                    key: ValueKey('prev:$_prevId'),
                    child: prev,
                  ),
                ),
                incoming: false,
              ),
            ),
        ],
      ),
    );
  }
}
