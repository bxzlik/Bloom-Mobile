/// Страница альбома или плейлиста площадки: шапка с обложкой и трек-лист.
///
/// Библиотечный плейлист живёт на другом экране (`TracklistScreen`): там свои
/// обложка, сортировка и правка состава. Здесь всё приходит из сети и трогать
/// его нельзя — можно только слушать и сохранить копию к себе, как это делает
/// импорт по ссылке.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/library_store.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/detail_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/util/format.dart';

class SetScreen extends ConsumerStatefulWidget {
  const SetScreen({super.key, required this.set, this.flight});

  /// Сет из карточки: шапка рисуется до ответа сети.
  final Playlist set;

  /// Обложка карточки, с которой пришли: она перелетает в шапку.
  final CoverFlight? flight;

  @override
  ConsumerState<SetScreen> createState() => _SetScreenState();
}

class _SetScreenState extends ConsumerState<SetScreen> {
  late Playlist _set;
  List<Track> _tracks = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _set = widget.set;
    _load();
  }

  Future<void> _load() async {
    final provider = ref.read(registryProvider).forEntity(widget.set.id);
    if (provider == null) {
      setState(() {
        _loading = false;
        _error = 'Площадка этого списка не подключена';
      });
      return;
    }
    try {
      final content = widget.set.isAlbum
          ? await provider.getAlbum(widget.set.id)
          : await provider.getPlaylist(widget.set.id);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (content == null) {
          _error = widget.set.isAlbum
              ? 'Альбом не найден'
              : 'Плейлист не найден';
          return;
        }
        // Обложку и владельца из карточки не теряем: у SoundCloud полная
        // выдача сета иногда приходит без них.
        _set = Playlist(
          id: content.playlist.id,
          title: content.playlist.title,
          cover: content.playlist.cover ?? widget.set.cover,
          trackCount: content.playlist.trackCount ?? content.tracks.length,
          ownerName: content.playlist.ownerName ?? widget.set.ownerName,
          ownerAvatar: content.playlist.ownerAvatar ?? widget.set.ownerAvatar,
          year: content.playlist.year ?? widget.set.year,
          isAlbum: content.playlist.isAlbum,
          duration: content.playlist.duration ?? widget.set.duration,
          sourceUrl: content.playlist.sourceUrl ?? widget.set.sourceUrl,
          source: content.playlist.source,
        );
        _tracks = content.tracks;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String get _kindWord => _set.isAlbum ? 'Альбом' : 'Плейлист';

  void _play() {
    if (_tracks.isEmpty) return;
    ref
        .read(playbackProvider.notifier)
        .playQueue(_tracks, 0, sourceId: _set.id);
  }

  void _shuffle() {
    if (_tracks.isEmpty) return;
    final ctrl = ref.read(playbackProvider.notifier);
    if (!ref.read(playbackProvider).shuffle) ctrl.toggleShuffle();
    ctrl.playQueue(_tracks, 0, sourceId: _set.id);
  }

  /// Есть ли уже сохранённая копия — ищем по ссылке источника, тому же полю, по
  /// которому «Обновить треки» находит источник импортированного плейлиста.
  bool get _saved =>
      _set.sourceUrl != null &&
      ref
          .read(libraryProvider)
          .playlists
          .any((p) => p.sourceUrl != null && p.sourceUrl == _set.sourceUrl);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final queue = _tracks;
    // Уже сохранённая копия ищется по ссылке источника — то же поле, по
    // которому «Обновить треки» находит источник импортированного плейлиста.
    final saved =
        _set.sourceUrl != null &&
        ref
            .watch(libraryProvider)
            .playlists
            .any((p) => p.sourceUrl != null && p.sourceUrl == _set.sourceUrl);

    return Scaffold(
      backgroundColor: t.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: DetailHero(
              image: _set.cover,
              title: _set.title,
              owner: _set.ownerName,
              subtitle: _subtitle(),
              flight: widget.flight,
              onMenu: _menu,
              actions: HeroActions(
                onPlay: queue.isEmpty ? null : _play,
                trailing: [
                  GlassIconButton(
                    icon: SolarIconsOutline.shuffle,
                    size: 46,
                    onTap: queue.isEmpty ? null : _shuffle,
                  ),
                  GlassIconButton(
                    icon: saved
                        ? SolarIconsBold.checkCircle
                        : SolarIconsOutline.addCircle,
                    size: 46,
                    background: saved ? t.accent : null,
                    color: saved ? t.accentText : null,
                    onTap: queue.isEmpty ? null : () => _save(saved),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            )
          else if (_error case final message?)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: t.sysFavIco),
                ),
              ),
            )
          else if (_tracks.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'Нет доступных треков',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: t.muted),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              sliver: SliverList.builder(
                itemCount: _tracks.length,
                itemBuilder: (context, i) => TrackRow(
                  track: _tracks[i],
                  queue: _tracks,
                  index: i,
                  sourceId: _set.id,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Подпись под названием: год, число треков, общая длительность — как в
  /// шапке сета на десктопе.
  String _subtitle() {
    final count = _tracks.isNotEmpty ? _tracks.length : _set.trackCount;
    final total = _tracks.isEmpty
        ? _set.duration
        : _tracks.fold(Duration.zero, (sum, x) => sum + x.duration);
    final year = _set.year;
    return [
      _kindWord,
      if (year != null && year.isNotEmpty) year,
      if (count case final n?) tracksCount(n),
      if (total case final d? when d > Duration.zero) mmss(d),
    ].join(' · ');
  }

  void _save(bool alreadySaved) {
    if (alreadySaved) {
      _toast('Уже в библиотеке');
      return;
    }
    ref
        .read(libraryProvider.notifier)
        .createPlaylist(
          _set.title,
          tracks: _tracks,
          cover: _set.cover,
          sourceUrl: _set.sourceUrl,
          isAlbum: _set.isAlbum,
        );
    _toast('Добавлено: ${_set.title} — ${tracksCount(_tracks.length)}');
  }

  Future<void> _menu() async {
    final link = _set.sourceUrl;
    final saved = _saved;

    await showBloomSheet(
      context: context,
      backdrop: _set.cover,
      header: SheetCoverHeader(
        cover: _set.cover,
        title: _set.title,
        subtitle: _subtitle(),
      ),
      groups: [
        [
          SheetAction(
            icon: SolarIconsBold.play,
            label: 'Воспроизвести',
            onTap: _tracks.isEmpty ? null : _play,
          ),
          SheetAction(
            icon: SolarIconsOutline.shuffle,
            label: 'Перемешать',
            onTap: _tracks.isEmpty ? null : _shuffle,
          ),
        ],
        [
          SheetAction(
            icon: saved ? SolarIconsBold.checkCircle : SolarIconsOutline.import,
            label: saved ? 'Уже в библиотеке' : 'Сохранить в библиотеку',
            onTap: _tracks.isEmpty ? null : () => _save(saved),
          ),
        ],
        [
          if (link != null && link.isNotEmpty)
            SheetAction(
              icon: SolarIconsOutline.link,
              label: 'Скопировать ссылку',
              onTap: () {
                Clipboard.setData(ClipboardData(text: link));
                _toast('Ссылка скопирована');
              },
            ),
        ],
      ],
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
