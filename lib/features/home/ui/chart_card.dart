/// Карточка чарта для витрины на главной — порт десктопного `ChartCard.tsx`:
/// обложка, цифра места внахлёст слева и плашка «название · артист · play»
/// снизу. Тон плашки — доминанта обложки, как у релизов. Топ-3 — сплошная
/// белая цифра, дальше контурная, иначе ряд превращается в частокол белых цифр.
///
/// Бейджа площадки нет: чарт целиком с одной площадки, а в углу обложки он
/// спорил бы со значком динамики.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/chart_trend.dart';
import '../../../shared/ui/track_actions.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import 'cover_tones.dart';

/// Геометрия — десктопные ручки `--ch-*`, ужатые под наши карточки 132/140.
const double _k = 132 / 140;
const double _width = 190 * _k;

/// Полоса слева под цифру.
const double _gutter = 16 * _k;
const double _cover = _width - _gutter;
const double _rankSize = 72 * _k;

/// Насколько плашка залезает на обложку.
const double _overlap = 34 * _k;
const double _tileHeight = 46;

/// Рост карточки целиком — по нему витрина задаёт высоту ленты.
const double kChartCardHeight = _cover + _tileHeight - _overlap;

class ChartCard extends ConsumerWidget {
  const ChartCard({
    super.key,
    required this.track,
    required this.pos,
    required this.source,
  });

  final Track track;

  /// Место в чарте (1-based) — цифра на карточке.
  final int pos;
  final PlaySource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final tint =
        ref.watch(coverTonesProvider(track.cover)).valueOrNull?.tint ??
        kCoverTileFallback;
    // Резолв стрима — спиннером в кнопке play, а не плёнкой на обложке.
    final loading = ref.watch(
      playbackProvider.select((s) => s.loading && s.track?.id == track.id),
    );
    // Одиночная карточка играет только свой трек, как на ПК.
    void play() => ref
        .read(playbackProvider.notifier)
        .playQueue([track], 0, source: source);

    return GestureDetector(
      onTap: play,
      onLongPress: () => showTrackActions(context, ref, track),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _width,
        height: kChartCardHeight,
        child: Stack(
          clipBehavior: Clip.none,
          // Порядок = слои: обложка, цифра, плашка поверх нижнего края цифры.
          children: [
            Positioned(
              left: _gutter,
              top: 0,
              child: Stack(
                children: [
                  Cover(url: track.cover, size: _cover, radius: t.radius),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: ChartTrend(track: track, chip: true),
                  ),
                ],
              ),
            ),
            Positioned(
              left: -10,
              bottom: kChartCardHeight - _cover + _overlap - 6,
              child: IgnorePointer(
                child: ChartRank(pos: pos, size: _rankSize),
              ),
            ),
            Positioned(
              left: _gutter,
              right: 0,
              bottom: 0,
              height: _tileHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(
                    (t.radius - 2).clamp(0, double.infinity),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 11.5,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                      TilePlayButton(size: 28, busy: loading, onTap: play),
                    ],
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

/// Цифра места. Контурная — пара «заливка цветом фона + светлая обводка» (в
/// светлой теме обводка тёмная): она читается на любой обложке. Сплошная белая
/// у топ-3 держится тенью; в светлой теме топ-3 тоже контурные — белая цифра
/// утонула бы в светлом фоне страницы.
class ChartRank extends StatelessWidget {
  const ChartRank({super.key, required this.pos, required this.size});

  final int pos;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final style = Theme.of(context).textTheme.displaySmall?.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 0.8,
      letterSpacing: -0.06 * size,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final solid = pos <= 3 && !t.isLight;
    final shadow = Shadow(
      color: Colors.black.withValues(alpha: t.isLight ? 0.18 : 0.55),
      blurRadius: t.isLight ? 14 : 18,
      offset: Offset(0, t.isLight ? 4 : 6),
    );
    if (solid) {
      return Text(
        '$pos',
        style: style?.copyWith(color: Colors.white, shadows: [shadow]),
      );
    }
    return Stack(
      children: [
        // Обводка шире на ширину заливки: заливка поверх прячет внутреннюю
        // половину, снаружи остаются те же 2 точки, что на ПК.
        Text(
          '$pos',
          style: style?.copyWith(
            shadows: [shadow],
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = t.isLight
                  ? Colors.black.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.92),
          ),
        ),
        Text('$pos', style: style?.copyWith(color: t.bg)),
      ],
    );
  }
}

/// Светлая круглая кнопка play на тёмной плашке (чарт и релизы). Пока ждём —
/// тёмный спиннер внутри: акцент на белом круге терялся бы.
class TilePlayButton extends StatelessWidget {
  const TilePlayButton({
    super.key,
    required this.size,
    required this.busy,
    required this.onTap,
  });

  final double size;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: busy ? 0.6 : 0.92),
        ),
        child: busy
            ? SizedBox(
                width: size * 0.5,
                height: size * 0.5,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF111111),
                  backgroundColor: Color(0x40000000),
                ),
              )
            : Padding(
                // Треугольник визуально левее центра — сдвигаем, как на ПК.
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  SolarIconsBold.play,
                  size: 14,
                  color: const Color(0xFF111111),
                ),
              ),
      ),
    );
  }
}
