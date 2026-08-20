/// Вход в «Итоги» — круглая кнопка в шапке главной, слева от колокольчика.
///
/// На ПК это пункт сайдбара (`WrappedNavItem`); сайдбара у нас нет. Сперва
/// кружок стоял отдельной строкой над «Моей волной», но пользователь перенёс
/// его в ряд круглых кнопок шапки — там он не двигает витрину вниз и стоит
/// рядом с остальными «событиями» (колокольчик).
///
/// Внутри — обложка самого заслушанного трека периода, вокруг — акцентное
/// кольцо, пока итоги не просмотрены (тот же язык, что у сторис). Коллаж из
/// четырёх обложек тут не годится: в кружок шапки помещаются ячейки по 20
/// точек, и картинка читается рябью, а не музыкой.
///
/// Появляется ТОЛЬКО когда итоги уместны (понедельник / 1-е число /
/// 21–31 декабря, см. `periods.dart`) И за период реально что-то слушали —
/// иначе в шапке нет ничего, ряд просто смыкается. Расписание снимается
/// тумблером «Показывать всегда» (Настройки → Интерфейс).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../wrapped_store.dart';
import 'wrapped_stories.dart';

/// Толщина кольца «не просмотрено» и зазор между ним и обложкой.
const double kWrappedRing = 2.5;
const double kWrappedRingGap = 2.5;

class WrappedCircle extends ConsumerStatefulWidget {
  const WrappedCircle({super.key, this.size = kHeaderControl});

  /// Диаметр вместе с кольцом. По умолчанию — как у соседних кнопок шапки.
  final double size;

  @override
  ConsumerState<WrappedCircle> createState() => _WrappedCircleState();
}

class _WrappedCircleState extends ConsumerState<WrappedCircle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Приложение может провисеть открытым до понедельника: сверяем дату по
    // возвращению из фона — на ПК ту же роль играет слушатель `focus`.
    if (state == AppLifecycleState.resumed) {
      ref.read(wrappedDayProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(wrappedProvider);
    if (ready == null) return const SizedBox.shrink();

    final t = context.bloom;
    final lib = ref.watch(libraryProvider);
    String? cover;
    for (final tr in ready.primaryData.topTracks) {
      cover = coverOfWrappedTrack(tr, lib);
      if (cover != null && cover.isNotEmpty) break;
    }

    return GestureDetector(
      onTap: () => openWrappedStories(context, ready),
      behavior: HitTestBehavior.opaque,
      child: Container(
        // Зазор до соседней кнопки несёт сама кнопка: иначе в дни без итогов в
        // ряду шапки оставалась бы дырка в 8 точек.
        margin: const EdgeInsets.only(right: 8),
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            // Кольцо: акцентное, пока итоги не смотрели, и тихая линия после
            // просмотра — как погасшее кольцо сторис.
            Positioned.fill(
              child: CustomPaint(
                painter: _RingPainter(
                  from: ready.unseen ? t.accent : t.ovlLine2,
                  to: ready.unseen ? t.accent2 : t.ovlLine2,
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(kWrappedRing + kWrappedRingGap),
                child: Cover(
                  url: cover,
                  size: widget.size - (kWrappedRing + kWrappedRingGap) * 2,
                  circle: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кольцо вокруг обложки. Градиент по кругу, как у сторис: ровная заливка
/// акцентом на тёмном фоне читается плоско.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.from, required this.to});

  final Color from;
  final Color to;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kWrappedRing
      ..shader = SweepGradient(
        colors: [from, to, from],
        stops: const [0, 0.5, 1],
        transform: const GradientRotation(-1.2),
      ).createShader(rect);
    canvas.drawCircle(
      rect.center,
      (size.shortestSide - kWrappedRing) / 2,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.from != from || old.to != to;
}
