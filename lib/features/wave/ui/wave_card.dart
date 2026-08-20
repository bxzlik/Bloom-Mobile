/// Карточка «Моя волна» на главной — порт `WaveCard.tsx` в виде «кольцо».
///
/// Из двух десктопных видов перенесён один: фаербол держится на
/// `feTurbulence`, которого в Flutter нет, и приближать его вручную смысла
/// мало. Поэтому и переключателя вида в настройках нет — кольцо здесь
/// единственное.
///
/// Слоёв два: кольцо обложек ([WaveRing]) и герой по центру — кнопка запуска и
/// заголовок. Отдельного «Настроить» нет: шторка настройки открывается долгим
/// нажатием на кнопку или на заголовок.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../wave_actions.dart';
import '../wave_controller.dart';
import '../wave_faces.dart';
import '../wave_store.dart';
import 'wave_ring.dart';
import 'wave_tune_sheet.dart';

/// Полы размеров героя: экран телефона вдвое уже десктопного окна, и честно
/// смасштабированная кнопка вышла бы меньше пальца.
const double _kMinPlay = 64;
const double _kMinTitle = 19;

class WaveCard extends ConsumerStatefulWidget {
  const WaveCard({super.key});

  @override
  ConsumerState<WaveCard> createState() => _WaveCardState();
}

class _WaveCardState extends ConsumerState<WaveCard> {
  /// Плитка, с которой волну уже собирают. Одного общего «идёт запуск» мало:
  /// по нему не видно, по какой из восьми обложек попали.
  String? _pendingId;

  Future<void> _startFrom(Track track) async {
    if (_pendingId != null) return;
    setState(() => _pendingId = track.id);
    try {
      await startWaveFromTrack(context, ref, track, seedFirst: true);
    } finally {
      if (mounted) setState(() => _pendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Действующая, а не выбранная: без входа в Яндекс кольцо обязано показать
    // обложки SoundCloud — те, что и зазвучат по кнопке.
    final source = ref.watch(effectiveWaveSourceProvider);
    final starting = ref.watch(waveProvider).starting;
    final faces = ref.watch(waveFacesProvider(source));

    // Пока площадка отвечает — кольцо с дышащими заглушками; ответила пустотой
    // (нет сети, не вошли в аккаунт) — показываем обложки из библиотеки.
    final loading = faces.isLoading;
    final tiles = faces.maybeWhen(
      data: (list) =>
          list.isNotEmpty ? list : ref.watch(waveRingFallbackProvider),
      orElse: () => const <Track>[],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 16 по краям — как у остальных блоков главной.
        final k = ringScale(constraints.maxWidth - 32);
        return Padding(
          // Дизайн-бокс обрезан вплотную по крайним плиткам, и без этого зазора
          // они упираются в соседние блоки главной.
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: kRingDesignHeight * k,
            // Плитки покачиваются и на пару точек выходят за дизайн-бокс — так же,
            // как на ПК, где у контейнера кольца обрезки нет. Обрезать их здесь
            // значило бы подстричь верхнюю обложку на пике качания.
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                WaveRing(
                  faces: tiles,
                  scale: k,
                  loading: loading,
                  busyId: _pendingId,
                  onTap: _startFrom,
                ),
                // Запуск «Моей волны» гасит и плитки: пока собирается одна волна,
                // вторая не нужна.
                _Hero(scale: k, starting: starting || _pendingId != null),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Центр кольца: кнопка запуска и заголовок. Настройка волны — долгим нажатием
/// на любой из них.
class _Hero extends ConsumerWidget {
  const _Hero({required this.scale, required this.starting});

  final double scale;
  final bool starting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final k = scale;
    final gap = max(8.0, 11 * k);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlayButton(
          diameter: max(_kMinPlay, 84 * k),
          starting: starting,
          onTap: () => startPersonalWave(context, ref),
          onLongPress: () => showWaveTuneSheet(context),
        ),
        SizedBox(height: gap),
        GestureDetector(
          // Заголовок — не кнопка, поэтому короткое нажатие по нему ничего не
          // делает: у него только «зажать».
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            Feedback.forLongPress(context);
            showWaveTuneSheet(context);
          },
          child: Text(
            context.l.waveTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: max(_kMinTitle, 23 * k),
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: t.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// Кружок запуска: залит АКЦЕНТОМ, глиф — контрастная пара акцента. На ПК так
/// же: в кольце кнопка сплошная, а не «голая» иконка, как у фаербола.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.diameter,
    required this.starting,
    required this.onTap,
    required this.onLongPress,
  });

  final double diameter;
  final bool starting;
  final VoidCallback onTap;

  /// Живёт и во время запуска: настроить волну можно, пока она собирается.
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      color: t.accent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: starting ? null : onTap,
        onLongPress: onLongPress,
        // Отклик на нажатие — контрастной парой акцента, а не чёрным: на
        // светлом акценте она затемняет кружок, на тёмном подсветит. Держится,
        // пока палец на кнопке, — по нему и видно, что идёт долгое нажатие.
        highlightColor: t.accentText.withValues(alpha: 0.16),
        splashColor: t.accentText.withValues(alpha: 0.12),
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: starting
              ? Padding(
                  padding: EdgeInsets.all(diameter * 0.3),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: t.accentText,
                  ),
                )
              : Icon(
                  SolarIconsBold.play,
                  size: diameter * 0.36,
                  color: t.accentText,
                ),
        ),
      ),
    );
  }
}
