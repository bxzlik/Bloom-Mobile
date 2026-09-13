/// Карточка релиза для витрины «Релизы» на главной — порт десктопного
/// `ReleaseCard.tsx`: крупный круг с фото артиста (имя поверх низа круга) и
/// плашка релиза внахлёст — мини-обложка, название, «альбом • 14 августа» и
/// play.
///
/// Тапы разведены по смыслу: круг — страница артиста, плашка — страница
/// альбома, play — альбом целиком (треки догружаются по тапу, витрина их
/// заранее не тянет).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/util/format.dart';
import '../../detail/detail_nav.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import 'chart_card.dart' show TilePlayButton;
import 'cover_tones.dart';

/// Геометрия — десктопные ручки `--rel-*`, ужатые под наши карточки 132/140.
const double _k = 132 / 140;
const double _width = 320 * _k;
const double _circle = 262 * _k;

/// Насколько плашка залезает на круг.
const double _overlap = 38 * _k;
const double _tileHeight = 66;

/// Рост карточки целиком — по нему витрина задаёт высоту ленты.
const double kReleaseCardHeight = _circle + _tileHeight - _overlap;

/// Тип релиза словом: «альбом», «сингл», «сборник», «подкаст».
String releaseTypeLabel(AppLocalizations l, String? type) => switch (type) {
  'single' => l.relSingle,
  'compilation' => l.relCompilation,
  'podcast' => l.relPodcast,
  _ => l.relAlbum,
};

/// Дата выхода для подписи: «14 августа» у релизов этого года, с годом — у
/// прошлых. Площадка отдала только год — год; ничего — `null`.
String? releaseDayLabel(Playlist album, String locale, {DateTime? now}) {
  final raw = album.releaseDate;
  final day = raw == null
      ? null
      : DateTime.tryParse(raw.length > 10 ? raw.substring(0, 10) : raw);
  if (day == null) return album.year;
  if (day.year == (now ?? DateTime.now()).year) {
    return DateFormat.MMMMd(locale).format(day);
  }
  return releaseDateLabel(raw, locale);
}

class ReleaseCard extends ConsumerStatefulWidget {
  const ReleaseCard({super.key, required this.album});

  final Playlist album;

  @override
  ConsumerState<ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends ConsumerState<ReleaseCard> {
  /// Грузим треки альбома после тапа по play.
  bool _busy = false;

  /// Первый трек запущенного альбома — пока плеер резолвит его стрим, кнопка
  /// так и крутит спиннер, иначе она «отпускалась» бы на середине пути.
  String? _startedId;

  Future<void> _play() async {
    final album = widget.album;
    final provider = ref.read(registryProvider).forEntity(album.id);
    if (_busy || provider == null) return;
    setState(() => _busy = true);
    try {
      final content = await provider.getAlbum(album.id);
      final tracks = content?.tracks ?? const <Track>[];
      if (!mounted || tracks.isEmpty) return;
      _startedId = tracks.first.id;
      await ref
          .read(playbackProvider.notifier)
          .playQueue(tracks, 0, source: SetSource(content!.playlist));
    } on Object {
      // Не загрузился — кнопка просто отпускается.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openArtist() {
    final album = widget.album;
    final id = album.ownerId;
    if (id == null) return;
    openArtist(
      context,
      id,
      initial: Artist(
        id: id,
        name: album.ownerName ?? '',
        avatar: album.ownerAvatar,
        source: album.source,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final tint =
        ref.watch(coverTonesProvider(album.cover)).valueOrNull?.tint ??
        kCoverTileFallback;
    final resolving = ref.watch(
      playbackProvider.select(
        (s) => s.loading && _startedId != null && s.track?.id == _startedId,
      ),
    );
    // Фото артиста; у сборников его нет — тогда в круг идёт обложка релиза,
    // чтобы ряд не рассыпался на два разных вида карточек.
    final photo = album.ownerAvatar ?? album.cover;
    final day = releaseDayLabel(
      album,
      Localizations.localeOf(context).toString(),
    );
    final type = releaseTypeLabel(l, album.albumType);

    return SizedBox(
      width: _width,
      height: kReleaseCardHeight,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: (_width - _circle) / 2,
            child: GestureDetector(
              onTap: album.ownerId == null ? null : _openArtist,
              child: ClipOval(
                child: SizedBox.square(
                  dimension: _circle,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Cover(url: photo, size: _circle, circle: true),
                      _Shade(tint: tint),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Имя — над кругом, а не внутри него: длинное переносится на вторую
          // строку и растёт вверх (низ прибит к плашке), без многоточия.
          Positioned(
            left: (_width - _circle) / 2 + 11,
            right: (_width - _circle) / 2 + 11,
            bottom: _tileHeight + 7,
            child: IgnorePointer(
              child: Text(
                album.ownerName ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.35,
                  height: 1.32,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _tileHeight,
            child: GestureDetector(
              onTap: () => openSet(context, album),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(t.radius + 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Cover(url: album.cover, size: 48, radius: 10),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            Text(
                              day == null || day.isEmpty
                                  ? type
                                  : '$type • $day',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11.5,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      TilePlayButton(
                        size: 32,
                        busy: _busy || resolving,
                        onTap: _play,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Низ круга: сверху тёмная плёнка под белое имя, под ней цвет плашки, который
/// «заходит» на фото снизу. Круг режет обе заливки ровно по дуге.
class _Shade extends StatelessWidget {
  const _Shade({required this.tint});

  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.64,
        widthFactor: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [tint, tint.withValues(alpha: 0)],
                  stops: const [0, 0.74],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
