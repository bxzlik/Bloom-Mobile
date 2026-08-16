/// Таймер сна — шторка по кнопке-луне в ряду инструментов плеера.
///
/// Своя вещь, десктопного оригинала нет: пресеты, «до конца трека», полоса
/// своего времени, «+5 минут» у идущего таймера и тумблер плавного затухания.
/// Подача — как у шторки скорости (`speed_sheet`): фон сплошной, шторка не
/// закрывается на каждый тап, потому что время подбирают не с первого раза.
///
/// Всё, что она делает, — зовёт `sleep_timer_store`; паузу и громкость крутит
/// `PlaybackController`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/glass.dart';
import '../sleep_timer_store.dart';

/// Полоса своего времени: те же толщина дорожки и бегунок, что у скорости, —
/// две шторки стоят рядом в одном ряду и обязаны выглядеть одинаково.
const double _trackHeight = 5;
const double _thumbRadius = 7;

void showSleepSheet(BuildContext context) {
  showBloomModal<void>(context: context, builder: (_) => const _SleepSheet());
}

class _SleepSheet extends ConsumerWidget {
  const _SleepSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final l = context.l;
    final sleep = ref.watch(sleepTimerProvider);
    final ctrl = ref.read(sleepTimerProvider.notifier);
    final running = sleep.mode == SleepMode.timer;

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
                  children: [
                    Expanded(
                      child: Text(l.playerSleep, style: theme.titleLarge),
                    ),
                    if (running)
                      _StatusPill(
                        text: l.playerSleepLeft(sleepLabel(sleep.remaining)),
                      )
                    else if (sleep.mode == SleepMode.endOfTrack)
                      _StatusPill(text: l.playerSleepEndOfTrack),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final preset in kSleepPresets) ...[
                      if (preset != kSleepPresets.first)
                        const SizedBox(width: 8),
                      Expanded(
                        child: _PresetCard(
                          minutes: preset.inMinutes,
                          active: running && sleep.choice == preset,
                          // Тап по уже выбранному пресету снимает таймер: ради
                          // отмены незачем искать отдельную кнопку.
                          onTap: () => running && sleep.choice == preset
                              ? ctrl.cancel()
                              : ctrl.start(preset),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _EndOfTrackCard(
                  active: sleep.mode == SleepMode.endOfTrack,
                  onTap: () => sleep.mode == SleepMode.endOfTrack
                      ? ctrl.cancel()
                      : ctrl.untilTrackEnd(),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.playerSleepCustom, style: theme.bodySmall),
                    ),
                    _CurrentPill(
                      text: l.playerSleepMinutes(sleep.choice.inMinutes),
                      active: running,
                    ),
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
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                      ),
                      child: Slider(
                        value: clampSleepMinutes(
                          sleep.choice.inMinutes,
                        ).toDouble(),
                        min: kSleepMinMinutes.toDouble(),
                        max: kSleepMaxMinutes.toDouble(),
                        divisions: kSleepDivisions,
                        label: l.playerSleepMinutes(sleep.choice.inMinutes),
                        // Полоса не выбирает время «на будущее», а сразу
                        // переставляет срок: отдельной кнопки «Пуск» в шторке
                        // нет, и время под пальцем должно быть настоящим.
                        onChanged: (v) =>
                            ctrl.start(Duration(minutes: v.round())),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l.playerSleepMinutes(kSleepMinMinutes),
                          style: theme.bodySmall,
                        ),
                        Text(
                          l.playerSleepMinutes(kSleepMaxMinutes),
                          style: theme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (sleep.active) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      // «+5 минут» осмысленно только у идущего времени: у «до
                      // конца трека» продлевать нечего.
                      if (running) ...[
                        Expanded(
                          child: _WideButton(
                            icon: SolarIconsOutline.alarmAdd,
                            text: l.playerSleepExtend,
                            onTap: ctrl.extend,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: _WideButton(
                          icon: SolarIconsOutline.alarmTurnOff,
                          text: l.playerSleepCancel,
                          onTap: ctrl.cancel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Divider(
                height: 1,
                thickness: 1,
                color: t.ovlLine2,
                indent: 20,
                endIndent: 20,
              ),
              _FadeRow(value: sleep.fade, onChanged: ctrl.setFade),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пресет: число крупно, «мин» под ним. Залит акцентом, когда таймер идёт
/// именно на это время.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.minutes,
    required this.active,
    required this.onTap,
  });

  final int minutes;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final radius = BorderRadius.circular(t.radius * 0.8);
    final color = active ? t.accentText : t.text;
    return Material(
      color: active ? t.accent : t.ovlBg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: active ? t.accent : t.ovlLine),
            borderRadius: radius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$minutes',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.1,
                  color: color,
                ),
              ),
              Text(
                context.l.playerSleepMin,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  height: 1.2,
                  color: color.withValues(alpha: active ? 0.75 : 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «До конца трека» — широкая плашка под рядом пресетов.
class _EndOfTrackCard extends StatelessWidget {
  const _EndOfTrackCard({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final radius = BorderRadius.circular(t.radius * 0.8);
    final color = active ? t.accentText : t.text;
    return Material(
      color: active ? t.accent : t.ovlBg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: active ? t.accent : t.ovlLine),
            borderRadius: radius,
          ),
          child: Row(
            children: [
              Icon(SolarIconsOutline.musicNote, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l.playerSleepEndOfTrack,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: color,
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

/// Пилюля выбранного времени у подписи «Своё время» — как `_CurrentPill` у
/// скорости, но без сброса по тапу: у таймера для этого есть своя кнопка.
class _CurrentPill extends StatelessWidget {
  const _CurrentPill({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: active ? t.accent.withValues(alpha: 0.14) : t.ovlBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: active ? t.accent : t.text2,
        ),
      ),
    );
  }
}

/// Остаток (или «до конца трека») в шапке шторки.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: t.accent,
        ),
      ),
    );
  }
}

/// Пилюля-кнопка под полосой: «+5 минут» и «Выключить таймер».
class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final radius = BorderRadius.circular(999);
    return GlassBox(
      borderRadius: radius,
      // Шторка — оверлей, и стекло у неё своей настройки.
      overlay: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: t.text),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: t.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Тумблер «Плавное затухание» — строка целиком нажимается, как «Nightcore» в
/// шторке скорости.
class _FadeRow extends StatelessWidget {
  const _FadeRow({required this.value, required this.onChanged});

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
                  Text(context.l.playerSleepFade, style: theme.titleMedium),
                  const SizedBox(height: 3),
                  Text(context.l.playerSleepFadeSub, style: theme.bodySmall),
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
