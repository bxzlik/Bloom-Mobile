/// «Настроить» у карточки волны — порт попапа `.wave-menu` из `WaveCard.tsx`:
/// выбор площадки и вход в дизлайки.
///
/// Отличие от ПК: переключатель площадки показывается ВСЕГДА, а не только
/// после входа в Яндекс. Спрятанный целиком, он выглядит так, будто выбора
/// нет вовсе — на десктопе рядом стоят настройки интеграций и это заметно, а
/// здесь единственная строка «Дизлайки» ничего не объясняет. Поэтому плитка
/// Яндекса без входа просто гаснет и по тапу говорит, куда идти.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../providers/yandex/ym_auth.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../wave_faces.dart';
import '../wave_store.dart';
import '../wave_types.dart';
import 'wave_dislikes_sheet.dart';

/// Шторка без обложки — как пикер скорости: сплошной фон, ручка и заголовок
/// строкой. Меню трека с размытой обложкой здесь не подходит, картинки у волны
/// нет.
void showWaveTuneSheet(BuildContext context) =>
    showBloomModal<void>(context: context, builder: (_) => const _TuneSheet());

class _TuneSheet extends ConsumerWidget {
  const _TuneSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final source = ref.watch(waveStoreProvider).source;
    final dislikes = ref.watch(waveStoreProvider).dislikes.length;
    // Именно через провайдер, а не `ym.activeToken()`: модульное состояние не
    // реактивно, и после входа шторка осталась бы с погашенной плиткой.
    final ymAuthed = ref.watch(ymAuthProvider).authed;

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
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: Row(
                  children: [
                    Text(
                      context.l.waveTune,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              // Плитки лежат прямо на шторке, без подложки и подписи: их и так
              // двое, и что это выбор площадки, видно по самим логотипам.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _SourceTile(
                        source: MusicSource.soundcloud,
                        label: 'SoundCloud',
                        selected: source == WaveEngineKind.soundcloud,
                        onTap: () => _pick(ref, WaveEngineKind.soundcloud),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SourceTile(
                        source: MusicSource.yandex,
                        label: MusicSource.yandex.label10n(context.l),
                        selected: ymAuthed && source == WaveEngineKind.yandex,
                        enabled: ymAuthed,
                        // Без аккаунта выбирать нечего, но и молчать нельзя —
                        // говорим, куда идти за входом.
                        onTap: ymAuthed
                            ? () => _pick(ref, WaveEngineKind.yandex)
                            : () => showToast(
                                context,
                                context.l.waveToastYmNoAuth,
                                kind: ToastKind.warn,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              SheetPanel(
                children: [
                  _DislikesRow(
                    count: dislikes,
                    onTap: () {
                      Navigator.of(context).pop();
                      showWaveDislikesSheet(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Смена площадки сбрасывает кэш витрины: кольцо обязано показать обложки
  /// ВЫБРАННОЙ станции, а не остаться со старыми.
  void _pick(WidgetRef ref, WaveEngineKind kind) {
    ref.read(waveStoreProvider.notifier).setSource(kind);
    resetWaveFaces();
    ref.invalidate(waveFacesProvider);
  }
}

/// Плитка площадки: логотип и ОБВОДКА в её фирменном цвете, а не в акценте
/// темы. Заливки нет — выбранная отличается тем, что рамка горит в полную силу,
/// а у остальных тот же цвет еле виден.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final MusicSource source;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Площадка доступна. Выключенная гаснет, но тап ловит — чтобы объяснить,
  /// почему она недоступна.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final brand = platformColor[source] ?? t.accent;
    final tile = Material(
      // Заливки нет ни у выбранной, ни у остальных: фирменный цвет здесь
      // только в обводке и логотипе.
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(t.radius * 0.8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius * 0.8),
            border: Border.all(
              color: brand.withValues(alpha: selected ? 1 : 0.28),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              PlatformLogo(source, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? t.text : t.text2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return enabled ? tile : Opacity(opacity: 0.45, child: tile);
  }
}

class _DislikesRow extends StatelessWidget {
  const _DislikesRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(SolarIconsOutline.dislike, size: 22, color: t.text),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                context.l.waveDislikes,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '$count',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.muted),
            ),
            const SizedBox(width: 6),
            Icon(SolarIconsOutline.altArrowRight, size: 18, color: t.muted),
          ],
        ),
      ),
    );
  }
}
