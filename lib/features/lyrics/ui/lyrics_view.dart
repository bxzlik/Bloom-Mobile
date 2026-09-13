/// Показ текста песни — порт десктопного `LyricsView.tsx` вместе с
/// `lyrics.css`: строки, подсветка активной и докрутка её в центр.
///
/// Заливки по словам/буквам и эффектов с ПК здесь нет: активная строка горит
/// целиком, как заливка «по строкам».
///
/// Часы отдельные ([_LyricsState._clock]): позиция от `just_audio` тикает
/// несколько раз в секунду, а точкам вступления нужно время ровнее. Между
/// тиками время продолжаем секундомером по кадрам `Ticker` — ровно то же
/// делает ПК (`performance.now()` + rAF).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../lrc.dart';
import '../lyrics_store.dart';

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

  late final Ticker _ticker;

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
  void initState() {
    super.initState();
    // Часы заводим ЗДЕСЬ, а не ленивым `late final` при первом обращении.
    //
    // К полю притрагивался только `_sync`, а его зовут тики плеера — на паузе
    // или если панель закрыли раньше первого тика, к часам не обращались вовсе,
    // и первым (он же единственным) до них добирался `dispose()`. А
    // `createTicker` оттуда лезет за `TickerMode` в уже мёртвый контекст,
    // роняет `dispose()` на полпути — и `ConsumerStatefulElement.unmount()`,
    // который отцепляет подписки ПОСЛЕ `dispose()`, до них не доходит. Экрана
    // уже нет, а слушатели живы: каждый тик плеера дальше бил и по `ref`, и по
    // выброшенным часам, и так до перезапуска приложения.
    _ticker = createTicker((_) => _tick());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sync(Duration position, bool playing) {
    if (!mounted) return;
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
    // Riverpod отцепляет подписки уже после `dispose()`, так что тик может
    // прийти в эту щель — а там и часы выброшены, и `ref` спрашивать нельзя.
    if (!mounted) return;
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
      // Кадр спустя панели может уже не быть — тогда и докручивать нечего.
      if (!mounted) return;
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
        children: _body(context, t, state),
      ),
    );
  }

  List<Widget> _body(BuildContext context, BloomTokens t, LyricsState state) {
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
            active: i == _curLine,
            color: _lineColor(t, i),
            layout: widget.layout,
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
    required this.active,
    required this.color,
    required this.layout,
    required this.onTap,
  });

  final LrcLine line;
  final bool active;
  final Color color;
  final LyricsLayout layout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: active ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        selected: active,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: active ? 1 : 0),
          duration: _lineSwitch,
          curve: Curves.easeOut,
          builder: (context, k, _) => Padding(
            padding: EdgeInsets.symmetric(vertical: layout.gap),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                line.text,
                textAlign: layout.align,
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
              ),
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
