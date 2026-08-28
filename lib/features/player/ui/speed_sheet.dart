/// Пикер скорости — шторка по кнопке-спидометру в ряду инструментов плеера.
///
/// Порт десктопного `SpeedPicker.tsx`: три карточки-пресета (0.75× / 1× /
/// 1.25×), полоса произвольной скорости с засечками каждые 0.25× и тумблер
/// «Nightcore» (питч едет за темпом). На ПК это всплывашка у кнопки; на телефоне
/// — шторка снизу, по выбору пользователя, и фон у неё СПЛОШНОЙ (не размытая
/// обложка, как у меню трека) — он попросил именно так.
///
/// Значения уходят в `speed_store`, на плеер их ставит `PlaybackController`.
/// Шторка не закрывается ни по пресету, ни по тумблеру: скорость подбирают на
/// слух, и каждый раз открывать её заново незачем.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../speed_store.dart';

/// Полоса: толщина дорожки и радиус бегунка. От них же считается отступ, на
/// который Slider поджимает дорожку с краёв (`max(thumb, overlay) / 2`, ореола
/// у нас нет), — по нему выставляются засечки, иначе крайние риски не сойдутся
/// с центром бегунка.
const double _trackHeight = 5;
const double _thumbRadius = 7;

void showSpeedSheet(BuildContext context) {
  // Корневой навигатор и стекло затемнения — общие у всех наших шторок
  // (`showBloomModal`): иначе таб-бар и миниплеер остаются поверх затемнения.
  showBloomModal<void>(context: context, builder: (_) => const _SpeedSheet());
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final l = context.l;
    final speed = ref.watch(speedProvider);
    final ctrl = ref.read(speedProvider.notifier);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.radius * 1.7)),
      child: SheetSurface(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  children: [Text(l.playerSpeed, style: theme.titleLarge)],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final preset in kSpeedPresets) ...[
                      if (preset != kSpeedPresets.first)
                        const SizedBox(width: 10),
                      Expanded(
                        child: _PresetCard(
                          value: preset,
                          active: speed.rate == preset,
                          onTap: () => ctrl.setRate(preset),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.playerSpeedCustom, style: theme.bodySmall),
                    ),
                    _CurrentPill(rate: speed.rate, onReset: ctrl.reset),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: _trackHeight,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: _thumbRadius,
                        ),
                        // Делений тридцать — родные метки дали бы рябь;
                        // засечки рисуем свои, каждые 0.25×, как на ПК.
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                      ),
                      child: Slider(
                        value: speed.rate.clamp(kSpeedMin, kSpeedMax),
                        min: kSpeedMin,
                        max: kSpeedMax,
                        divisions: kSpeedDivisions,
                        label: speedLabel(speed.rate),
                        onChanged: ctrl.setRate,
                      ),
                    ),
                    const _Ticks(),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(speedLabel(kSpeedMin), style: theme.bodySmall),
                        Text(speedLabel(kSpeedMax), style: theme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                thickness: 1,
                color: t.ovlLine2,
                indent: 20,
                endIndent: 20,
              ),
              _NightcoreRow(
                value: speed.nightcore,
                onChanged: ctrl.setNightcore,
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка-пресет: залита акцентом, когда стоит именно она.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.value,
    required this.active,
    required this.onTap,
  });

  final double value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final radius = BorderRadius.circular(t.radius * 0.8);
    return Material(
      color: active ? t.accent : t.ovlBg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: active ? t.accent : t.ovlLine),
            borderRadius: radius,
          ),
          child: Text(
            speedLabel(value),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: active ? t.accentText : t.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Пилюля текущего значения. Тап по ней — сброс на 1× (десктопный `sp-cur`).
class _CurrentPill extends StatelessWidget {
  const _CurrentPill({required this.rate, required this.onReset});

  final double rate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final on = rate != 1;
    return Semantics(
      button: true,
      label: context.l.playerSpeedReset,
      child: GestureDetector(
        onTap: onReset,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: on ? t.accent.withValues(alpha: 0.14) : t.ovlBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            speedLabel(rate),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: on ? t.accent : t.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Засечки под полосой — каждые 0.25×, совпавшие с пресетами крупнее.
///
/// Полоса поджата с краёв на пол-бегунка (так Slider считает дорожку), поэтому
/// и засечки живут в тех же границах: иначе крайние риски не сойдутся с
/// центром бегунка в упоре.
class _Ticks extends StatelessWidget {
  const _Ticks();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      height: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _thumbRadius),
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              for (final tick in kSpeedTicks)
                Positioned(
                  left:
                      (tick - kSpeedMin) /
                          (kSpeedMax - kSpeedMin) *
                          box.maxWidth -
                      0.5,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    height: kSpeedPresets.contains(tick) ? 8 : 5,
                    color: t.text.withValues(
                      alpha: kSpeedPresets.contains(tick) ? 0.3 : 0.16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Тумблер «Nightcore»: питч едет вместе с темпом. Нажимается вся строка — на
/// ПК это `<label>`, там кликается тоже всё целиком.
class _NightcoreRow extends StatelessWidget {
  const _NightcoreRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l.playerSpeedNightcore,
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.l.playerSpeedNightcoreSub,
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            BloomSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
