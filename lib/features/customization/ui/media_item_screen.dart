/// Страница одной картинки библиотеки: превью, куда она применена, её
/// размытие и затемнение, удаление.
///
/// На десктопе это разнесено по трём местам — карточки контекстов, ползунки
/// вкладки «Фон» и крестик на плитке галереи. Пользователь собрал их вместе на
/// странице картинки, и размытие с затемнением стали свойством самой картинки,
/// а не общей настройкой фона (см. [MediaItem.blur]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/glass.dart';
import '../custom_store.dart';
import '../media_store.dart';
import 'custom_widgets.dart';

class MediaItemScreen extends ConsumerWidget {
  const MediaItemScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final item = ref.watch(mediaLibProvider.notifier).byId(id);
    // Смотрим на список, а не только на notifier: без этого правка ползунка
    // не перерисовала бы страницу.
    ref.watch(mediaLibProvider);
    final targets = ref.watch(customProvider);

    void back() => context.go('/settings/media');

    if (item == null) {
      // Картинку удалили из-под ног (например, каскадом) — уходим назад.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) back();
      });
      return const SizedBox.shrink();
    }

    return CustomizationPage(
      title: context.l.custLibrary,
      onBack: back,
      actions: [
        WideButton(
          icon: SolarIconsOutline.trashBinMinimalistic,
          label: context.l.commonDelete,
          danger: true,
          onTap: () {
            removeMedia(ref.read, id);
            back();
          },
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        children: [
          _Preview(item: item),
          const SizedBox(height: 16),
          _Panel(
            children: [
              for (final ctx in CustomCtx.values) ...[
                if (ctx != CustomCtx.values.first) _divider(t),
                _SwitchRow(
                  label: _ctxLabel(context, ctx),
                  value: targets.of(ctx) == item.id,
                  onChanged: (on) => ref
                      .read(customProvider.notifier)
                      .toggle(ctx, item.id, on),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          // Размытие и затемнение работают ТОЛЬКО когда картинка стоит фоном —
          // об этом и говорит заголовок. Показываем их всё равно всегда:
          // картинку настраивают и до того, как поставят её фоном.
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Text(
              context.l.custOnlyForBg.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          _Panel(
            children: [
              _SliderRow(
                label: context.l.custBlur,
                value: item.blur,
                max: kBgBlurMax,
                suffix: 'px',
                onChanged: (v) =>
                    ref.read(mediaLibProvider.notifier).setBlur(item.id, v),
              ),
              _divider(t),
              _SliderRow(
                label: context.l.custDim,
                value: item.dim,
                max: kBgDimMax,
                suffix: '%',
                onChanged: (v) =>
                    ref.read(mediaLibProvider.notifier).setDim(item.id, v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _ctxLabel(BuildContext context, CustomCtx ctx) => switch (ctx) {
    CustomCtx.bg => context.l.custCtxBg,
    CustomCtx.cover => context.l.custCtxCover,
    CustomCtx.slider => context.l.custCtxSlider,
  };
}

Widget _divider(BloomTokens t) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 14),
  child: Divider(
    height: 1,
    color: t.ovlLine.withValues(alpha: t.ovlLine.a * 0.5),
  ),
);

class _Preview extends StatelessWidget {
  const _Preview({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final image = coverImage(item.src);
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radius),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.pill),
          child: image == null
              ? null
              : Image(
                  image: image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(
                    child: Text(
                      context.l.custImageGone,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassBox(child: Column(children: children));
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        BloomSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      // Ряд просторный намеренно: две ручки в притык читались как одна мелкая
      // плашка и в неё было тесно попадать пальцем.
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.titleMedium)),
              Text('${value.round()}$suffix', style: theme.bodyMedium),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: t.accent,
              inactiveTrackColor: t.track,
              thumbColor: t.accent,
            ),
            // Ловушка пальца выше самой дорожки: `Slider` по умолчанию отдаёт
            // ей всего 48, и на просторной плашке она выглядела ниткой.
            child: SizedBox(
              height: 36,
              child: Slider(
                value: value.clamp(0, max),
                max: max,
                // Шаг в единицу: ползунок настройки, а не полоса плеера —
                // целые проценты и пиксели читаются, дробные ничего не дают.
                divisions: max.round(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
