/// Кольцо обложек вокруг кнопки «Моей волны» — порт `WaveRing.tsx` и
/// `.hwr-*` из `home.css`.
///
/// Восемь плиток через 45° в «дизайн-боксе», числа множатся на масштаб
/// ([ringScale]) — длину одной такой точки. На ПК его считает контейнерный
/// запрос, здесь — [LayoutBuilder] от ширины блока.
///
/// Отличия от ПК, оба из-за размера экрана:
///
/// 1. Кольцо — ОКРУЖНОСТЬ, а не эллипс 250×155. В центре стоит герой (кнопка,
///    заголовок, «Настроить») высотой примерно во столько же, во сколько и
///    шириной, поэтому на сплюснутом кольце боковые просветы выходили вдвое
///    шире верхних. На широком окне ПК это незаметно, на телефоне бросается в
///    глаза сразу.
/// 2. У героя свой ПОЛ размера: честно смасштабированная кнопка вышла бы 47
///    логических точек — меньше, чем палец, а заголовок стал бы нечитаемо
///    мелким.
///
/// Размер плиток тоже единый: разнобой 66…96 с ПК на окружности читается не
/// ритмом, а неровностью.
///
/// Тап по обложке = заиграть ЭТОТ трек и продолжить волной по нему
/// (`startByTrack(seedFirst: true)`), как клик на десктопе.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../shared/ui/atoms.dart';

/// Слот кольца: смещение от центра и сторона плитки в точках дизайн-бокса плюс
/// период и фаза покачивания.
class RingSlot {
  const RingSlot({
    required this.x,
    required this.y,
    required this.size,
    required this.period,
    required this.phase,
    this.round = false,
  });

  final double x;
  final double y;
  final double size;

  /// Круглые — боковые и нижняя: они задают ритм кольца.
  final bool round;

  /// Период качания и сдвиг фазы в секундах (на ПК — `--dur` / `--delay`).
  final double period;
  final double phase;
}

/// Радиус кольца и сторона плитки. Кольцо намеренно просторное, плитки
/// некрупные: тесная сетка «в упор» читается таблицей и душит середину.
const double _kRadius = 172;
const double _kTile = 78;

/// Слот на окружности. [degrees] считаются от «трёх часов» по часовой стрелке,
/// как на экране: 270° — верх.
RingSlot _slot(
  double degrees, {
  required double period,
  required double phase,
  bool round = false,
}) {
  final a = degrees * pi / 180;
  return RingSlot(
    x: _kRadius * cos(a),
    y: _kRadius * sin(a),
    size: _kTile,
    round: round,
    period: period,
    phase: phase,
  );
}

/// Восемь плиток через 45°. Порядок = порядок заполнения обложками: сначала
/// боковые и верхняя, туда попадают самые «сильные» сиды.
final List<RingSlot> kRingSlots = [
  _slot(180, round: true, period: 9, phase: 1.2),
  _slot(0, round: true, period: 10.5, phase: 4.4),
  _slot(270, period: 8, phase: 2.6),
  _slot(225, period: 11, phase: 0.4),
  _slot(315, period: 9.5, phase: 3.1),
  _slot(135, period: 10, phase: 5.2),
  _slot(45, period: 8.5, phase: 1.8),
  _slot(90, round: true, period: 7.5, phase: 3.7),
];

/// Сторона дизайн-бокса: два радиуса плюс плитка, которая на них сидит.
const double kRingDesignWidth = _kRadius * 2 + _kTile;

/// Бокс квадратный — кольцо круглое.
const double kRingDesignHeight = kRingDesignWidth;

/// Ниже этого масштаба обложки перестают читаться — дно, как на ПК.
const double _kMinScale = 0.46;

/// Насколько плитка отъезжает при качании (на ПК — `hwrFloat`).
const double _kFloatAmplitude = 7;

/// Масштаб кольца при доступной ширине [width].
double ringScale(double width) =>
    (width / kRingDesignWidth).clamp(_kMinScale, 1.0);

/// Слой плиток. Кнопка и заголовок лежат отдельным слоем поверх — см.
/// `wave_card.dart`.
class WaveRing extends StatefulWidget {
  const WaveRing({
    super.key,
    required this.faces,
    required this.scale,
    required this.loading,
    required this.onTap,
    this.busyId,
  });

  /// Обложки по порядку слотов. Короче списка слотов — остаток занимают
  /// заглушки: дырок в кольце быть не должно.
  final List<Track> faces;
  final double scale;

  /// Ждём ответа площадки — заглушки мягко дышат.
  final bool loading;

  /// id трека, с которого волна уже стартует.
  final String? busyId;

  final void Function(Track track) onTap;

  @override
  State<WaveRing> createState() => _WaveRingState();
}

class _WaveRingState extends State<WaveRing>
    with SingleTickerProviderStateMixin {
  /// Одни часы на все плитки: у каждой свои период и фаза, поэтому восемь
  /// контроллеров ради этого заводить незачем.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    // Общий круг — наименьшее общее кратное периодов брать не нужно: фазу
    // каждая плитка считает от абсолютного времени сама.
    duration: const Duration(seconds: 60),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.scale;
    return SizedBox(
      width: kRingDesignWidth * k,
      height: kRingDesignHeight * k,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final seconds = _clock.value * 60;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < kRingSlots.length; i++)
                _slot(kRingSlots[i], i, k, seconds),
            ],
          );
        },
      ),
    );
  }

  Widget _slot(RingSlot slot, int index, double k, double seconds) {
    final side = slot.size * k;
    // Качание: круг по вертикали со своим периодом. Горизонталь — половина
    // амплитуды и вдвое быстрее, иначе плитки ходят строго вверх-вниз строем.
    final t = (seconds + slot.phase) / slot.period * 2 * pi;
    final dy = sin(t) * _kFloatAmplitude * k;
    final dx = sin(t * 2) * _kFloatAmplitude * 0.5 * k;

    final face = index < widget.faces.length ? widget.faces[index] : null;
    return Positioned(
      left: kRingDesignWidth * k / 2 + slot.x * k - side / 2 + dx,
      top: kRingDesignHeight * k / 2 + slot.y * k - side / 2 + dy,
      width: side,
      height: side,
      child: _Tile(
        track: face,
        side: side,
        round: slot.round,
        loading: widget.loading,
        busy: face != null && face.id == widget.busyId,
        onTap: face == null ? null : () => widget.onTap(face),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.track,
    required this.side,
    required this.round,
    required this.loading,
    required this.busy,
    required this.onTap,
  });

  final Track? track;
  final double side;
  final bool round;
  final bool loading;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final radius = round
        ? BorderRadius.circular(side)
        : BorderRadius.circular(side * 0.3);
    final cover = track?.cover;

    if (cover == null) {
      // Обложки ещё грузятся или их меньше, чем слотов (почти пустая
      // библиотека) — ставим нейтральную заглушку.
      return _Placeholder(radius: radius, side: side, breathing: loading);
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Cover(url: cover, size: side, radius: 0),
            // Волна с этого трека уже собирается — держим затемнение с
            // вертушкой, чтобы было видно, по какой обложке попали.
            if (busy)
              ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: SizedBox(
                    width: side * 0.3,
                    height: side * 0.3,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.radius,
    required this.side,
    required this.breathing,
  });

  final BorderRadius radius;
  final double side;
  final bool breathing;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final box = Container(
      decoration: BoxDecoration(color: t.coverEmpty, borderRadius: radius),
      child: Icon(
        SolarIconsBold.musicNote,
        size: side * 0.32,
        color: t.muted.withValues(alpha: 0.5),
      ),
    );
    if (!breathing) return box;
    return _Breathing(child: box);
  }
}

/// Пульсация прозрачности, пока ждём ответа площадки (на ПК — `hwrBusy`).
class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});

  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: 0.35,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}
