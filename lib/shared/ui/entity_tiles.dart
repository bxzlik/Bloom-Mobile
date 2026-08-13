/// Строки и карточки сущностей — общие для поиска, страниц артиста и
/// библиотеки. Работают с нейтральными [Track]/[Artist]/[Playlist], поэтому
/// одинаковы для всех площадок.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../features/detail/detail_nav.dart';
import '../../features/offline/offline_store.dart';
import '../../features/player/player_controller.dart';
import '../util/format.dart';
import 'atoms.dart';
import 'cover_hero.dart';
import 'platform_logo.dart';
import 'track_actions.dart';

/// Метка перелёта обложки — своя у КАЖДОГО экземпляра карточки. Считать её из
/// id нельзя: один альбом легко стоит сразу в двух секциях выдачи, а два `Hero`
/// с одинаковой меткой в одном дереве — исключение на старте перехода.
///
/// Обложки нет — перелёта нет: заглушке лететь некуда.
CoverFlight? _flightFor(String? cover, Object tag) =>
    cover == null || cover.isEmpty ? null : CoverFlight(tag: tag, image: cover);

/// Поля строки трека. Высота нужна снаружи: очередь открывается сразу на
/// играющем треке и считает по ней смещение прокрутки.
const EdgeInsets kTrackRowPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 6,
);
const double kTrackRowCover = 52;
const double kTrackRowHeight = kTrackRowCover + 12;

/// Строка трека: обложка, название/артист, длительность. Тап ставит [queue]
/// целиком, чтобы работали «дальше»/«назад», а не один трек.
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.sourceId,
    this.dragIndex,
  });

  final Track track;
  final List<Track> queue;
  final int index;

  /// Список, из которого взята [queue] — см. [PlaybackState.sourceId]. Строка
  /// внутри плейлиста заводит его целиком, поэтому плитка этого плейлиста тоже
  /// должна показать эквалайзер.
  final String? sourceId;

  /// Номер строки в `ReorderableList` — см. [TrackRowShell.dragIndex]. `null` в
  /// списках, где порядок не свой: в выдаче поиска и на страницах площадок
  /// двигать нечего.
  final int? dragIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackRowShell(
      track: track,
      active: ref.watch(playbackProvider).track?.id == track.id,
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playQueue(queue, index, sourceId: sourceId),
      onMenu: () => showTrackActions(context, ref, track),
      dragIndex: dragIndex,
    );
  }
}

/// Строка трека без привязки к списку: вид и жесты, действия — снаружи. Одна
/// на всё — плейлисты, выдачу поиска, страницы площадок и очередь, — иначе
/// списки неминуемо разъезжаются видом.
class TrackRowShell extends StatelessWidget {
  const TrackRowShell({
    super.key,
    required this.track,
    required this.active,
    required this.onTap,
    required this.onMenu,
    this.dragIndex,
  });

  final Track track;

  /// «Играет сейчас»: название акцентом, вместо длительности эквалайзер.
  /// Считает вызывающий — в очереди один трек может стоять дважды, и по id их
  /// не различить.
  final bool active;

  final VoidCallback onTap;

  /// Долгий тап — контекстное меню трека, как на десктопе.
  final VoidCallback onMenu;

  /// Номер строки в `ReorderableList`. Задан — обложка становится тянучкой:
  /// зажать и тащить (на десктопе handle тоже на обложке). Меню при этом
  /// переезжает с обложки на остальную часть строки: два долгих жеста на одном
  /// месте иначе спорят в арене и меню открывается вместо перетаскивания.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final drag = dragIndex;
    final Widget cover = _Cover(track: track);

    return InkWell(
      onTap: onTap,
      onLongPress: drag == null ? onMenu : null,
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: kTrackRowPadding,
        child: Row(
          children: [
            if (drag == null)
              cover
            else
              ReorderableDelayedDragStartListener(index: drag, child: cover),
            const SizedBox(width: 12),
            Expanded(
              child: _Rest(
                track: track,
                active: active,
                onMenu: drag == null ? null : onMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Обложка трека в строке. Бейдж площадки в углу: в общем списке треки могут
/// быть из разных источников, и по обложке этого не понять.
class _Cover extends StatelessWidget {
  const _Cover({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Cover(url: track.cover, size: kTrackRowCover),
        Positioned(
          right: 3,
          bottom: 3,
          child: SourceBadge(track.source, size: 18),
        ),
      ],
    );
  }
}

/// Строка без обложки: тексты, отметка офлайна, длительность. Отдельным
/// куском, потому что у тянущихся строк именно на нём висит долгий тап.
class _Rest extends StatelessWidget {
  const _Rest({required this.track, required this.active, this.onMenu});

  final Track track;
  final bool active;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: active
                    ? theme.titleMedium?.copyWith(color: t.accent)
                    : theme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Ярче обычной подписи: в строке трека артист читается наравне
                // с названием, а не как второстепенная мелочь.
                style: theme.bodySmall?.copyWith(color: t.text2),
              ),
            ],
          ),
        ),
        _OfflineMark(trackId: track.id),
        const SizedBox(width: 10),
        DurationPill(track: track, active: active),
      ],
    );

    if (onMenu == null) return row;
    // `opaque`: меню должно открываться и с пустого места между текстом и
    // длительностью. Тап при этом остаётся у `InkWell` строки — свой тап этот
    // детектор не ловит, и подсветка идёт по всей строке.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onMenu,
      child: row,
    );
  }
}

/// Отметка «трек лежит на устройстве» — стрелка перед длительностью, аналог
/// десктопной иконки `save` в строке. Пока трек качается, на её месте кольцо
/// прогресса (или бесконечное, если CDN не сказал размер).
///
/// Подписка через `select`: строк в списке сотни, и перерисовывать их все на
/// каждый тик прогресса чужого трека незачем.
class _OfflineMark extends ConsumerWidget {
  const _OfflineMark({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final status = ref.watch(
      offlineProvider.select(
        (s) => (
          saved: s.has(trackId),
          pending: s.isPending(trackId),
          progress: s.progressOf(trackId),
        ),
      ),
    );

    if (status.pending) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value: status.progress,
            strokeWidth: 1.6,
            color: t.accent,
            backgroundColor: t.ovlLine,
          ),
        ),
      );
    }
    if (!status.saved) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      // Дискета и приглушённый цвет — как `.tr-offline` на десктопе (там
      // `Ico name="save"` = solar/diskette-linear, color: var(--text2)).
      child: Icon(SolarIconsOutline.diskette, size: 14, color: t.text2),
    );
  }
}

/// Длительность трека в рамке — десктопный `.trd` (прозрачный фон, тонкая
/// линия), но скругление круче десктопного (0.85 от темы вместо 0.45) и линия
/// самая тихая (`ovlLine`): на мобилке рамка не должна спорить с названием.
/// У играющего трека вместо цифр в той же рамке стоит эквалайзер: строка сама
/// показывает, что играет.
class DurationPill extends ConsumerWidget {
  const DurationPill({super.key, required this.track, required this.active});

  final Track track;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    // Поток play/pause спрашиваем только у играющей строки — остальным он не
    // нужен и лишние подписки в длинном списке ни к чему.
    final child = active
        ? StreamBuilder<bool>(
            stream: ref.watch(audioPlayerProvider).playingStream,
            initialData: ref.read(audioPlayerProvider).playing,
            builder: (context, snap) =>
                EqualizerBars(playing: snap.data ?? false),
          )
        : Text(
            mmss(track.duration),
            style: theme.bodySmall?.copyWith(
              color: t.text2,
              fontWeight: FontWeight.w600,
            ),
          );

    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      height: 30,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.ovlLine),
        borderRadius: BorderRadius.circular(t.radius * 0.85),
      ),
      child: child,
    );
  }
}

/// Эквалайзер играющего сета — оверлей для обложки его карточки. То же, что
/// полоски вместо длительности в строке трека: список сам показывает, что
/// играет именно он. Обложка под полосками слегка притемняется — на пёстрой
/// картинке их иначе не разглядеть.
///
/// Неиграющий сет отдаёт пустоту, а не отсутствие оверлея: решать, показывать
/// ли полоски, должен сам оверлей — иначе подписку на плеер пришлось бы
/// заводить каждой плитке сетки.
class SetEqualizer extends ConsumerWidget {
  const SetEqualizer({super.key, required this.setId});

  /// Тот же id, что уходит в `playQueue(sourceId:)`: id сета площадки или
  /// id библиотечного списка.
  final String setId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playingSet = ref.watch(
      playbackProvider.select((s) => s.sourceId == setId),
    );
    if (!playingSet) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.32),
        child: Center(
          child: StreamBuilder<bool>(
            stream: ref.watch(audioPlayerProvider).playingStream,
            initialData: ref.read(audioPlayerProvider).playing,
            // Полоски заданы в пикселях строки трека — на крупной обложке
            // плитки их надо увеличить, на мелкой (строка сета) оставить как
            // есть.
            builder: (context, snap) => EqualizerBars(
              playing: snap.data ?? false,
              scale: (box.maxWidth / 56).clamp(1.0, 3.0),
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка альбома или плейлиста: обложка, название, владелец. Нужна там, где
/// сет стоит в списке, а не в карусели — в репостах артиста.
class SetRow extends StatefulWidget {
  const SetRow({super.key, required this.set});

  final Playlist set;

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final flight = _flightFor(set.cover, _tag);
    final sub = [
      set.isAlbum ? 'Альбом' : 'Плейлист',
      set.ownerName,
      if (set.trackCount != null) tracksCount(set.trackCount!),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: () => openSet(context, set, flight: flight),
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Cover(
              url: set.cover,
              size: 48,
              flight: flight,
              overlay: SetEqualizer(setId: set.id),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    set.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка трека для карусели («Популярные» на странице артиста). Тап ставит
/// [queue] целиком — как и строка трека.
class TrackCard extends ConsumerWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.size = 132,
  });

  final Track track;
  final List<Track> queue;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final active = ref.watch(playbackProvider).track?.id == track.id;

    return GestureDetector(
      onTap: () => ref.read(playbackProvider.notifier).playQueue(queue, index),
      onLongPress: () => showTrackActions(context, ref, track),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Бейдж крупнее и с большим отступом от угла, чем в строке, — как
            // `.sp-tc-cover .cov-badge` на десктопе.
            Stack(
              children: [
                Cover(url: track.cover, size: size),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: SourceBadge(track.source, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: active
                  ? theme.titleSmall?.copyWith(color: t.accent)
                  : theme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка артиста: круглый аватар, имя, подписчики. Тап открывает страницу
/// артиста — других применений у карточки нет.
///
/// [size] `null` — карточка занимает всю ширину ячейки (сетка выдачи); число —
/// фиксированная ширина (карусель).
class ArtistCard extends StatefulWidget {
  const ArtistCard({
    super.key,
    required this.artist,
    this.size = 104,
    this.centerLabel = false,
  });

  final Artist artist;
  final double? size;

  /// Подписи по центру — так стоят артисты в сетке и подписки в библиотеке.
  final bool centerLabel;

  @override
  State<ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<ArtistCard> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final size = widget.size;
    final centerLabel = widget.centerLabel;
    final theme = Theme.of(context).textTheme;
    final followers = artist.followers;
    final align = centerLabel ? TextAlign.center : TextAlign.start;
    final flight = _flightFor(artist.avatar, _tag);

    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: centerLabel
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Cover(
            url: artist.avatar,
            size: box.maxWidth,
            circle: true,
            flight: flight,
          ),
          const SizedBox(height: 8),
          Text(
            artist.name,
            maxLines: 1,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: theme.titleSmall,
          ),
          if (followers != null) ...[
            const SizedBox(height: 2),
            Text(
              '${compactCount(followers)} подписчиков',
              maxLines: 1,
              textAlign: align,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
          ],
        ],
      ),
    );

    return GestureDetector(
      onTap: () =>
          openArtist(context, artist.id, initial: artist, flight: flight),
      behavior: HitTestBehavior.opaque,
      child: size == null ? content : SizedBox(width: size, child: content),
    );
  }
}

/// Карточка плейлиста или альбома: обложка, название, владелец и счётчик.
///
/// [size] `null` — на всю ширину ячейки сетки, число — фиксированная ширина
/// карусели.
class SetCard extends StatefulWidget {
  const SetCard({super.key, required this.set, this.size = 132});

  final Playlist set;
  final double? size;

  @override
  State<SetCard> createState() => _SetCardState();
}

class _SetCardState extends State<SetCard> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final size = widget.size;
    final theme = Theme.of(context).textTheme;
    final flight = _flightFor(set.cover, _tag);
    // Год и счётчик есть не всегда — пустые части просто выпадают, вместо
    // «0 треков» и пустых разделителей.
    final sub = [
      set.ownerName,
      set.year,
      if (set.trackCount != null) tracksCount(set.trackCount!),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Cover(
            url: set.cover,
            size: box.maxWidth,
            flight: flight,
            overlay: SetEqualizer(setId: set.id),
          ),
          const SizedBox(height: 8),
          Text(
            set.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall,
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () => openSet(context, set, flight: flight),
      behavior: HitTestBehavior.opaque,
      child: size == null ? content : SizedBox(width: size, child: content),
    );
  }
}

/// Горизонтальная лента карточек — общая для выдачи поиска и секций страницы
/// артиста.
class EntityCarousel extends StatelessWidget {
  const EntityCarousel({
    super.key,
    required this.height,
    required this.itemCount,
    required this.builder,
  });

  final double height;
  final int itemCount;
  final Widget Function(int index) builder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => builder(i),
      ),
    );
  }
}

/// Заголовок секции выдачи.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
