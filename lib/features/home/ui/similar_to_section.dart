/// «Похожие на X» на главной — порт десктопного `SimilarToSection.tsx`.
///
/// Заголовок «Похожие на» + имя сида, подкрашенное тоном его обложки; в ленте
/// первой стоит плитка сида («тёмный остров» того же тона), за ней треки и
/// артисты вперемешку. Тап по сиду: артист открывает страницу, трек играет.
///
/// Одно отличие от ПК: там плитка сида стоит неподвижно слева от ленты. На
/// телефоне неподвижная плитка шириной в полэкрана оставила бы ленте щель,
/// поэтому здесь она первая карточка и уезжает вместе с лентой.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../detail/detail_nav.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import 'cover_tones.dart';
import '../similar_to.dart';

/// Геометрия плитки сида — десктопные `--sim-seed-w` / `--sim-seed-cov`,
/// ужатые под наши карточки 132 вместо 140.
const double _k = 132 / 140;
const double _seedWidth = 210 * _k;
const double _seedCover = 72 * _k;

/// Рост плитки — рост карточки ленты: обложка, отступ и две строки подписи
/// (на ПК плитка тянется по высоте ряда).
const double _seedHeight = 176;

class SimilarToSection extends ConsumerWidget {
  const SimilarToSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(similarToProvider);
    if (data == null || data.items.isEmpty) return const SizedBox.shrink();
    final seed = data.seed;
    final tones = ref.watch(coverTonesProvider(seed.cover)).valueOrNull;
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final open = _seedAction(context, ref, seed);
    final source = PlainSource(
      id: 'similarTo',
      label: '${l.homeSimilarTo} ${seed.name}',
      cover: seed.cover,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            children: [
              Text(l.homeSimilarTo, style: theme.titleLarge),
              const SizedBox(width: 6),
              Flexible(
                child: GestureDetector(
                  onTap: open,
                  child: Text(
                    seed.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleLarge?.copyWith(
                      color: tones == null
                          ? null
                          : (t.isLight ? tones.inkLight : tones.ink),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        EntityCarousel(
          height: 194,
          padding: 16,
          itemCount: data.items.length + 1,
          builder: (i) {
            if (i == 0) {
              return _SeedTile(seed: seed, tint: tones?.tint, onTap: open);
            }
            return switch (data.items[i - 1]) {
              // Одиночная карточка играет свой трек, как на ПК.
              SimilarTrackItem(:final track) => TrackCard(
                track: track,
                queue: [track],
                index: 0,
                source: source,
              ),
              SimilarArtistItem(:final artist) => _ArtistTile(artist: artist),
            };
          },
        ),
      ],
    );
  }
}

/// Что делает тап по сиду. Трек-сид без самого трека (свой файл, которого нет
/// в библиотеке) играть нечем — тап выключен.
VoidCallback? _seedAction(
  BuildContext context,
  WidgetRef ref,
  SimilarSeed seed,
) => switch (seed) {
  SimilarArtistSeed(:final artist) => () => openArtist(
    context,
    artist.id,
    initial: artist,
  ),
  SimilarTrackSeed(:final track?) =>
    () => ref
        .read(playbackProvider.notifier)
        .playQueue(
          [track],
          0,
          source: PlainSource(
            id: 'similarTo:seed',
            label: track.name,
            cover: track.cover,
          ),
        ),
  SimilarTrackSeed() => null,
};

/// Плитка сида — порт `.sim-seed`: обложка сверху, имя и подпись прижаты к
/// низу. Текст всегда белый: плитка тёмная в любой теме.
class _SeedTile extends StatelessWidget {
  const _SeedTile({required this.seed, required this.tint, this.onTap});

  final SimilarSeed seed;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final isArtist = seed is SimilarArtistSeed;
    final sub = switch (seed) {
      SimilarArtistSeed() => context.l.homeSimilarArtist,
      SimilarTrackSeed(:final artist) => artist,
    };

    return Align(
      alignment: Alignment.topLeft,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: _seedWidth,
          height: _seedHeight,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            // Тон ещё не посчитан или обложки нет — нейтральный тёмный с ПК.
            color: tint ?? kCoverTileFallback,
            borderRadius: BorderRadius.circular(t.radius + 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Cover(
                url: seed.cover,
                size: _seedCover,
                circle: isArtist,
                radius: t.radius,
              ),
              const Spacer(),
              Text(
                seed.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.32,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Артист в ленте — та же геометрия, что у карточки трека, только круг, а под
/// именем «Артист» (порт `.sim-art`).
class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => openArtist(context, artist.id, initial: artist),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 132,
        child: Column(
          children: [
            Cover(url: artist.avatar, size: 132, circle: true),
            const SizedBox(height: 8),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              context.l.homeSimilarArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
