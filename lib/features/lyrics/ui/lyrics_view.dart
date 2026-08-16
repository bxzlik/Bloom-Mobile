/// Показ текста песни — порт десктопного `LyricsView.tsx` вместе с
/// `lyrics.css`: строки, подсветка активной, докрутка её в центр, заливка и
/// эффект поверх заливки.
///
/// Главное отличие от ПК — как всё это рисуется. Там строка режется на `<span>`
/// на единицу заливки, и цвет им меняет CSS. Здесь строка остаётся ОДНИМ
/// абзацем `TextPainter`, а «спетая» часть рисуется поверх с обрезкой по
/// границам символов ([_LinePainter]). Иначе переносы считались бы по кускам:
/// у слов-виджетов строка ломается где попало, а у букв — прямо посреди слова.
///
/// Часы отдельные ([_LyricsState._clock]): позиция от `just_audio` тикает
/// несколько раз в секунду, для градиентной заливки этого мало. Между тиками
/// время продолжаем секундомером и красим по кадрам `Ticker` — ровно то же
/// делает ПК (`performance.now()` + rAF).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../lrc.dart';
import '../lyrics_store.dart';
import '../lyrics_style_store.dart';

/// Кегль и раскладка текста на одной поверхности.
///
/// Их две, и различаются они не на вкус, а по ширине коробки — ровно как на ПК,
/// где у панели над обложкой свои числа (`.lyrics-content`: 16 → 19, по
/// центру), а у широкой боковой панели свои (`#grpLyricsContent`: 20 → 24, по
/// левому краю). В узком квадрате обложки крупный текст ломался бы на каждой
/// строке, а на всю ширину экрана мелкий читается как сноска.
class LyricsLayout {
  const LyricsLayout({
    required this.fontSize,
    required this.activeFontSize,
    required this.align,
    required this.lineHeight,
    required this.gap,
  });

  /// Текст поверх обложки — числа `.lyrics-content` с ПК.
  static const overlay = LyricsLayout(
    fontSize: 16,
    activeFontSize: 19,
    align: TextAlign.center,
    lineHeight: 1.75,
    gap: 1,
  );

  /// Текст вместо обложки — числа широкой панели с ПК.
  ///
  /// Строки по ЛЕВОМУ краю: на всю ширину экрана центрированный текст «плавает»
  /// от строки к строке (та же причина, что у `#grpLyricsContent`). Расстояние
  /// между строками даёт [gap], а не интерлиньяж: внутри одной длинной
  /// (перенесённой) строки он обязан остаться плотным, иначе она разъезжается
  /// и перестаёт читаться одной фразой.
  static const replace = LyricsLayout(
    fontSize: 21,
    activeFontSize: 25,
    align: TextAlign.left,
    lineHeight: 1.35,
    gap: 11,
  );

  final double fontSize;
  final double activeFontSize;
  final TextAlign align;

  /// Интерлиньяж ВНУТРИ строки (перенесённой).
  final double lineHeight;

  /// Отступ сверху и снизу у каждой строки — расстояние между соседними.
  final double gap;
}

/// Насколько быстро строка перекрашивается и укрупняется, становясь активной.
const Duration _lineSwitch = Duration(milliseconds: 220);

/// Прозрачность строк по состоянию — те же доли, что в `lyrics.css`.
const double _alphaPast = 0.15;
const double _alphaUpcoming = 0.45;
const double _alphaIdle = 0.25;

/// «Ещё не спетая» часть активной строки (`--lyr-off`).
const double _alphaOff = 0.32;

/// Сколько длится эффект появления единицы (`fade`/`spring` на ПК — .42 с).
const double _fxSec = 0.42;

class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({
    super.key,
    this.active = true,
    this.padding = const EdgeInsets.fromLTRB(14, 28, 14, 28),
    this.layout = LyricsLayout.overlay,
  });

  /// Поверхность видима — только тогда крутим часы и докручиваем строку в
  /// центр. Спрятанная панель не должна жечь кадры.
  final bool active;

  final EdgeInsets padding;

  /// Кегль и раскладка — свои у каждой поверхности, см. [LyricsLayout].
  final LyricsLayout layout;

  @override
  ConsumerState<LyricsView> createState() => _LyricsState();
}

class _LyricsState extends ConsumerState<LyricsView>
    with SingleTickerProviderStateMixin {
  /// Текущее время трека в секундах — общий источник для всех строк.
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  late final Ticker _ticker = createTicker((_) => _tick());

  /// Позиция последнего тика плеера и секундомер с того момента: между тиками
  /// время считаем сами.
  double _basePos = 0;
  final Stopwatch _since = Stopwatch();

  final ScrollController _scroll = ScrollController();

  /// Ключи строк — по ним докручиваем активную в центр.
  final Map<int, GlobalKey> _keys = {};

  int _curLine = -1;
  bool _playing = false;

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sync(Duration position, bool playing) {
    _basePos = position.inMilliseconds / 1000;
    _since.reset();
    _playing = playing;
    if (playing && widget.active) {
      _since.start();
      if (!_ticker.isActive) _ticker.start();
    } else {
      _since.stop();
      if (_ticker.isActive) _ticker.stop();
    }
    _tick();
  }

  void _tick() {
    _clock.value = _basePos + _since.elapsedMilliseconds / 1000;
    final lines = ref.read(lyricsProvider).lines;
    if (lines.isEmpty) return;
    final next = activeLineAt(lines, _clock.value);
    if (next != _curLine) {
      setState(() => _curLine = next);
      _scrollToActive();
    }
  }

  /// Активную строку — в середину коробки. Как на ПК: до первой строки в центр
  /// уезжают точки-интро.
  void _scrollToActive() {
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[_curLine]?.currentContext;
      if (ctx == null || !_scroll.hasClients) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    // Панель открыли/закрыли — заводим или глушим часы и доводим строку.
    if (widget.active != old.active) {
      _sync(Duration(milliseconds: (_clock.value * 1000).round()), _playing);
      if (widget.active) _scrollToActive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final state = ref.watch(lyricsProvider);
    final style = ref.watch(lyricsStyleProvider);

    ref.listen(playheadProvider, (_, next) {
      final head = next.value;
      if (head != null) _sync(head.position, _playing);
    });
    ref.listen(playingProvider, (_, next) {
      final playing = next.value;
      if (playing != null) {
        _sync(Duration(milliseconds: (_clock.value * 1000).round()), playing);
      }
    });
    // Текст пришёл для другого трека — активную строку считаем заново, иначе
    // подсветка осталась бы стоять на номере из прошлой песни.
    ref.listen(lyricsProvider, (prev, next) {
      if (prev?.trackId != next.trackId || prev?.lines != next.lines) {
        _curLine = -1;
        _keys.clear();
        if (_scroll.hasClients) _scroll.jumpTo(0);
        _tick();
      }
    });

    return SingleChildScrollView(
      controller: _scroll,
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _body(context, t, state, style),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    BloomTokens t,
    LyricsState state,
    LyricsStyle style,
  ) {
    if (state.status == LyricsStatus.loading) {
      return [_Status(text: context.l.lyricsLoading)];
    }
    if (state.lines.isNotEmpty) {
      return [
        _IntroDots(
          key: _keyFor(-1),
          until: state.lines.first.time,
          clock: _clock,
          active: _curLine < 0,
          layout: widget.layout,
        ),
        for (var i = 0; i < state.lines.length; i++)
          _Line(
            key: _keyFor(i),
            line: state.lines[i],
            // Конца у последней строки нет — те же 4 с, что на ПК.
            until: i + 1 < state.lines.length
                ? state.lines[i + 1].time
                : state.lines[i].time + kLastLineSec,
            active: i == _curLine,
            color: _lineColor(t, i),
            style: style,
            layout: widget.layout,
            clock: _clock,
            onTap: () => ref
                .read(playbackProvider.notifier)
                .seek(
                  Duration(milliseconds: (state.lines[i].time * 1000).round()),
                ),
          ),
      ];
    }
    if (state.plain.isNotEmpty) {
      return [
        for (final row in state.plain.split('\n'))
          _Plain(
            text: row,
            color: t.text.withValues(alpha: 0.6),
            layout: widget.layout,
          ),
      ];
    }
    return [
      _Status(
        text: state.status == LyricsStatus.idle
            ? context.l.lyricsLoading
            : context.l.lyricsNotFound,
      ),
    ];
  }

  GlobalKey _keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  Color _lineColor(BloomTokens t, int index) {
    if (index == _curLine) return t.text;
    if (index == _curLine + 1) return t.text.withValues(alpha: _alphaUpcoming);
    if (index < _curLine) return t.text.withValues(alpha: _alphaPast);
    return t.text.withValues(alpha: _alphaIdle);
  }
}

/// Строка синхронного текста: перекрашивается и укрупняется, становясь
/// активной, и по тапу перематывает трек на своё время.
class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.line,
    required this.until,
    required this.active,
    required this.color,
    required this.style,
    required this.layout,
    required this.clock,
    required this.onTap,
  });

  final LrcLine line;

  /// Время следующей строки — по нему делятся единицы заливки.
  final double until;

  final bool active;
  final Color color;
  final LyricsStyle style;
  final LyricsLayout layout;
  final ValueNotifier<double> clock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GestureDetector(
      onTap: active ? null : onTap,
      behavior: HitTestBehavior.opaque,
      // Строку рисует художник, а не `Text`, — в дереве семантики её иначе не
      // было бы вовсе: скринридер читал бы пустой экран.
      child: Semantics(
        label: line.text,
        selected: active,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: active ? 1 : 0),
          duration: _lineSwitch,
          curve: Curves.easeOut,
          builder: (context, k, _) => Padding(
            padding: EdgeInsets.symmetric(vertical: layout.gap),
            child: _PaintedLine(
              text: line.text,
              align: layout.align,
              style: TextStyle(
                fontSize: ui.lerpDouble(
                  layout.fontSize,
                  layout.activeFontSize,
                  k,
                ),
                height: layout.lineHeight,
                fontWeight: FontWeight.lerp(
                  FontWeight.w400,
                  FontWeight.w700,
                  k,
                ),
                color: color,
              ),
              active: active,
              onColor: t.text,
              offColor: t.text.withValues(alpha: _alphaOff),
              accent: t.accent,
              fill: style.fill,
              fx: style.fx,
              from: line.time,
              to: until,
              clock: clock,
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка простого (несинхронного) текста — подсвечивать нечего.
class _Plain extends StatelessWidget {
  const _Plain({required this.text, required this.color, required this.layout});

  final String text;
  final Color color;
  final LyricsLayout layout;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: layout.gap),
    child: SizedBox(
      width: double.infinity,
      child: Text(
        text.isEmpty ? ' ' : text,
        textAlign: layout.align,
        style: TextStyle(
          fontSize: layout.fontSize,
          height: layout.lineHeight,
          color: color,
        ),
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 10),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        height: 1.6,
        color: context.bloom.text.withValues(alpha: _alphaIdle),
      ),
    ),
  );
}

/// Три точки вместо первой строки, пока играет вступление.
///
/// Порт `LyricsIntroDots`: точки зажигаются по мере приближения к первой
/// строке, вся группа при этом мягко дышит; вступление кончилось — уходят в
/// фон, как прошедшая строка. Рисуются у ЛЮБОГО синхронного текста, а не
/// только при длинном вступлении — это постоянный маркер «до первой строки».
class _IntroDots extends StatefulWidget {
  const _IntroDots({
    super.key,
    required this.until,
    required this.clock,
    required this.active,
    required this.layout,
  });

  final double until;
  final ValueNotifier<double> clock;
  final bool active;
  final LyricsLayout layout;

  @override
  State<_IntroDots> createState() => _IntroDotsState();
}

class _IntroDotsState extends State<_IntroDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ValueListenableBuilder<double>(
        valueListenable: widget.clock,
        builder: (context, sec, _) {
          // Вступления нет вовсе (первая строка в 00:00) — точки сразу
          // «прошедшие», иначе доля дала бы NaN и они застряли бы потухшими.
          final prog = widget.until > 0
              ? (sec / widget.until).clamp(0.0, 1.0)
              : 1.0;
          final past = !widget.active;
          return AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => Opacity(
              opacity: past ? 1 : 0.75 + 0.25 * _pulse.value,
              child: Row(
                mainAxisAlignment: widget.layout.align == TextAlign.center
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut,
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.text.withValues(
                          alpha: past
                              ? _alphaPast
                              : (prog >= i / 3 ? 1.0 : 0.22),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Строка, нарисованная художником: даёт ей высоту по разметке абзаца.
class _PaintedLine extends StatelessWidget {
  const _PaintedLine({
    required this.text,
    required this.style,
    required this.align,
    required this.active,
    required this.onColor,
    required this.offColor,
    required this.accent,
    required this.fill,
    required this.fx,
    required this.from,
    required this.to,
    required this.clock,
  });

  final String text;
  final TextStyle style;
  final TextAlign align;
  final bool active;
  final Color onColor;
  final Color offColor;
  final Color accent;
  final LyricsFill fill;
  final LyricsFx fx;
  final double from;
  final double to;
  final ValueNotifier<double> clock;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = _LinePainter(
          text: text,
          style: style,
          align: align,
          scaler: scale,
          active: active,
          onColor: onColor,
          offColor: offColor,
          accent: accent,
          fill: fill,
          fx: fx,
          from: from,
          to: to,
          // Перекрашивать строку по кадрам нужно только активной: у остальных
          // цвет задан состоянием и от времени не зависит.
          clock: active ? clock : null,
        );
        return CustomPaint(
          size: Size(box.maxWidth, painter.heightAt(box.maxWidth)),
          painter: painter,
        );
      },
    );
  }
}

/// Художник одной строки.
///
/// Абзац рисуется дважды: сперва целиком «ещё не спетым» цветом, поверх —
/// «спетая» часть с обрезкой по границам символов. Где проходит граница,
/// решает [fill]:
///   line   — вся строка разом;
///   word   — по конец текущего слова;
///   letter — по конец текущей буквы;
///   wipe   — по НАЧАЛО текущего слова плюс доля внутри него (градиента как
///            такового нет: у нас его роль играет обрезка по ширине, зато без
///            ступеньки на стыке — край и так ровно по пикселям).
class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.text,
    required this.style,
    required this.align,
    required this.scaler,
    required this.active,
    required this.onColor,
    required this.offColor,
    required this.accent,
    required this.fill,
    required this.fx,
    required this.from,
    required this.to,
    required this.clock,
  }) : super(repaint: clock) {
    if (active && fill != LyricsFill.line) {
      final u = lrcUnits(
        text,
        byLetter: fill == LyricsFill.letter,
        from: from,
        to: to,
      );
      _offsets = u.offsets;
      _starts = u.starts;
    }
  }

  final String text;
  final TextStyle style;
  final TextAlign align;
  final TextScaler scaler;
  final bool active;
  final Color onColor;
  final Color offColor;
  final Color accent;
  final LyricsFill fill;
  final LyricsFx fx;
  final double from;
  final double to;
  final ValueNotifier<double>? clock;

  /// Границы единиц заливки в тексте и их времена (пусто у заливки «по
  /// строкам» и у неактивных строк — там резать нечего).
  List<int> _offsets = const [];
  List<double> _starts = const [];

  /// Разметка абзаца одна на все слои — цвет подменяем на самой отрисовке.
  TextPainter? _tp;
  double _tpWidth = -1;

  TextPainter _layout(double width, Color color) {
    if (_tp == null || _tpWidth != width) {
      _tp?.dispose();
      _tp = TextPainter(
        textAlign: align,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      );
      _tpWidth = width;
    }
    final tp = _tp!;
    tp.text = TextSpan(
      text: text,
      style: style.copyWith(color: color),
    );
    tp.layout(maxWidth: width);
    return tp;
  }

  double heightAt(double width) => _layout(width, offColor).height;

  @override
  void paint(Canvas canvas, Size size) {
    // Неактивная строка — один слой своим цветом состояния.
    if (!active) {
      _layout(size.width, style.color ?? offColor).paint(canvas, Offset.zero);
      return;
    }

    final sec = clock?.value ?? 0;
    final cur = _currentUnit(sec);
    final split = _splitAt(cur, sec);

    // Пружина — единственный эффект с движением: текущую единицу рисуем
    // отдельно и увеличенной, поэтому из общего слоя её вырезаем, иначе
    // немасштабированная копия просвечивала бы из-под неё.
    final springRect = fx == LyricsFx.spring && cur >= 0
        ? _unitRect(size.width, cur)
        : null;

    canvas.save();
    if (springRect != null) {
      canvas.clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRect(springRect),
        ),
      );
    }
    _paintLayers(canvas, size, cur, split, sec);
    canvas.restore();

    if (springRect != null) {
      final k = _springScale(sec, cur);
      final center = springRect.center;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(k);
      canvas.translate(-center.dx, -center.dy);
      // Обрезка ПОСЛЕ масштаба: в увеличенном пространстве прямоугольник
      // единицы накрывает ровно её саму, соседние слова в кадр не попадают.
      canvas.clipRect(springRect);
      _paintLayers(canvas, size, cur, split, sec);
      canvas.restore();
    }
  }

  /// Оба слоя строки: «не спето» целиком и «спето» с обрезкой.
  void _paintLayers(
    Canvas canvas,
    Size size,
    int cur,
    ({int chars, double partial}) split,
    double sec,
  ) {
    _layout(size.width, offColor).paint(canvas, Offset.zero);

    // Свечение — позади текущей единицы, размытой копией в акцент. drop-shadow
    // с ПК: тень поверх обрезанного текста не рисуется.
    if (fx == LyricsFx.glow && cur >= 0) {
      final rect = _unitRect(size.width, cur);
      canvas.save();
      canvas.clipRect(rect.inflate(10));
      final tp = _layout(size.width, offColor);
      tp.text = TextSpan(
        text: text,
        style: style.copyWith(
          color: null,
          foreground: Paint()
            ..color = accent.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        ),
      );
      tp.layout(minWidth: size.width, maxWidth: size.width);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    if (split.chars <= 0 && split.partial <= 0) return;

    final onAlpha = fx == LyricsFx.fade ? _fadeAlpha(sec, cur) : 1.0;
    final on = _layout(
      size.width,
      onAlpha >= 1 ? onColor : onColor.withValues(alpha: onAlpha),
    );

    final clip = Path();
    if (split.chars > 0) {
      for (final box in on.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: split.chars),
      )) {
        clip.addRect(box.toRect());
      }
    }
    // Плавная заливка: доля внутри текущей единицы — обрезка по ширине.
    if (split.partial > 0 && cur >= 0) {
      for (final box in on.getBoxesForSelection(
        TextSelection(
          baseOffset: _offsets[cur],
          extentOffset: _offsets[cur + 1],
        ),
      )) {
        final r = box.toRect();
        clip.addRect(
          Rect.fromLTRB(
            r.left,
            r.top,
            r.left + r.width * split.partial,
            r.bottom,
          ),
        );
      }
    }
    canvas.save();
    canvas.clipPath(clip);
    on.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// Номер поющейся сейчас единицы; −1 — строка ещё не началась.
  int _currentUnit(double sec) {
    if (_starts.isEmpty) return -1;
    var idx = -1;
    for (var i = 0; i < _starts.length; i++) {
      // Та же фора 0.05 с, что на ПК: тайминги единиц синтетические, и на
      // границе слово должно загораться чуть раньше, а не позже.
      if (sec + 0.05 >= _starts[i]) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  /// Где проходит граница «спето / ещё нет»: сколько символов залито целиком и
  /// какая доля текущей единицы залита сверх того.
  ({int chars, double partial}) _splitAt(int cur, double sec) {
    if (fill == LyricsFill.line) return (chars: text.length, partial: 0);
    if (cur < 0) return (chars: 0, partial: 0);
    if (fill != LyricsFill.wipe) {
      return (chars: _offsets[cur + 1], partial: 0);
    }
    final start = _starts[cur];
    final end = cur + 1 < _starts.length ? _starts[cur + 1] : to;
    final p = ((sec - start) / math.max(end - start, 0.001)).clamp(0.0, 1.0);
    return (chars: _offsets[cur], partial: p);
  }

  /// Коробка единицы в строке (объединение её боксов — слово могло попасть на
  /// перенос).
  Rect _unitRect(double width, int cur) {
    final tp = _layout(width, offColor);
    final boxes = tp.getBoxesForSelection(
      TextSelection(baseOffset: _offsets[cur], extentOffset: _offsets[cur + 1]),
    );
    if (boxes.isEmpty) return Rect.zero;
    var out = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      out = out.expandToInclude(b.toRect());
    }
    return out;
  }

  /// «Мягко»: единица втекает непрозрачностью за [_fxSec] от своего начала.
  double _fadeAlpha(double sec, int cur) {
    if (cur < 0) return 1;
    final k = ((sec - _starts[cur]) / _fxSec).clamp(0.0, 1.0);
    return 0.45 + 0.55 * k;
  }

  /// «Пружина»: вспухнуть и с отдачей сесть назад — те же ключевые кадры, что
  /// в `@keyframes lyrFxSpring` (1 → 1.09 → 0.984 → 1).
  double _springScale(double sec, int cur) {
    if (cur < 0 || cur >= _starts.length) return 1;
    final k = ((sec - _starts[cur]) / _fxSec).clamp(0.0, 1.0);
    const peak = 1.09;
    if (k < 0.32) return ui.lerpDouble(1, peak, k / 0.32)!;
    if (k < 0.64) {
      return ui.lerpDouble(peak, 1 - (peak - 1) * 0.18, (k - 0.32) / 0.32)!;
    }
    return ui.lerpDouble(1 - (peak - 1) * 0.18, 1, (k - 0.64) / 0.36)!;
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.text != text ||
      old.style != style ||
      old.align != align ||
      old.active != active ||
      old.onColor != onColor ||
      old.offColor != offColor ||
      old.accent != accent ||
      old.fill != fill ||
      old.fx != fx ||
      old.from != from ||
      old.to != to;
}
