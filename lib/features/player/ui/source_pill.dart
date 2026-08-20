/// Пилюля источника в шапке плеера: что именно сейчас играет — «Любимые»,
/// плейлист, альбом, страница артиста, выдача поиска.
///
/// Порт десктопного `#qpSourcePill` из `QueueBlock.tsx`: слева картинка
/// источника 24×24, дальше его имя, а за именем — значок перемешки, когда она
/// включена (список идёт не в своём порядке, и это должно быть видно). Счётчик
/// треков с ПК не переносим: на телефоне он уже стоит на кнопке очереди в ряду
/// инструментов.
///
/// Тап уводит на сам источник, а плеер при этом закрывается: пилюля — это не
/// подпись, а ссылка «откуда это». У источников без своей страницы (поиск,
/// витрина главной, одиночный трек) тапа нет.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/marquee_text.dart';
import '../../detail/detail_nav.dart';
import '../play_source.dart';
import 'player_sheet.dart';

/// Размеры пилюли. Вынесены сюда, а не размазаны по разметке: шапка плеера
/// собирается из них и из [kHeaderControl] — высота у пилюли та же, что у
/// круглых кнопок по краям, иначе шапка читается ступенькой.
const double _iconSize = 28;
const double _gap = 10;

/// Открыть источник очереди: закрыть плеер (и шторки над ним) и уйти на его
/// страницу.
///
/// Страницу кладём в навигатор ТЕКУЩЕЙ вкладки, а не в корневой: из поиска и
/// библиотеки те же страницы открываются под таб-баром и миниплеером, и
/// открытая отсюда обязана выглядеть так же (см. [currentBranchNavigator]).
void openPlaySource(BuildContext context, PlaySource source) {
  // Шторки над плеером снимает навигатор, а сам плеер — не маршрут: он слой
  // каркаса и складывается своим вызовом (см. `PlayerSheet`).
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  collapsePlayerSheet();
  switch (source) {
    case LibSource(:final listId):
      // Раздел библиотеки живёт маршрутом — заодно переключит вкладку.
      bloomRouter.go('/library/list/$listId');
    case SetSource(:final set):
      final nav = currentBranchNavigator();
      if (nav != null) openSetIn(nav, set);
    case ArtistSource(:final artist):
      final nav = currentBranchNavigator();
      if (nav != null) openArtistIn(nav, artist.id, initial: artist);
    case PlainSource():
    case WaveSource():
      // Поиск, витрина, одиночный трек, волна — открывать нечего.
      break;
  }
}

/// Есть ли у источника своя страница. У [PlainSource] и [WaveSource] её нет —
/// такая пилюля рисуется без ряби и не ловит тап.
bool playSourceOpens(PlaySource source) =>
    source is! PlainSource && source is! WaveSource;

class SourcePill extends ConsumerWidget {
  const SourcePill({super.key, required this.source, required this.shuffle});

  /// Источник очереди. `null` — очередь ниоткуда (снимок старой сессии,
  /// восстановленный до того, как источник начали запоминать): пилюля тогда
  /// просто называет себя очередью.
  final PlaySource? source;

  /// Перемешка — значок за именем источника.
  final bool shuffle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final source = this.source;
    final label = source == null
        ? context.l.playerQueue
        : _label(context, ref, source);
    final tappable = source != null && playSourceOpens(source);

    return Center(
      child: Material(
        color: t.pill,
        borderRadius: BorderRadius.circular(kHeaderControl / 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tappable ? () => openPlaySource(context, source) : null,
          child: Padding(
            // Слева поля больше, чем просвет над картинкой: край пилюли
            // скруглён, и квадратная обложка, отодвинутая от него «поровну»,
            // упирается в закругление. Справа ещё больше — там текст, и он
            // должен дышать.
            padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
            child: SizedBox(
              height: kHeaderControl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SourceIcon(source: source),
                  const SizedBox(width: _gap),
                  Flexible(
                    child: MarqueeText(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  if (shuffle) ...[
                    const SizedBox(width: 8),
                    Icon(SolarIconsOutline.shuffle, size: 14, color: t.accent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Подпись источника. У разделов библиотеки берётся ЖИВОЙ — плейлист могли
  /// переименовать, пока он играет (см. `play_source.dart`).
  String _label(BuildContext context, WidgetRef ref, PlaySource source) {
    switch (source) {
      case LibSource(:final listId):
        return switch (listId) {
          'all' => context.l.commonAllTracks,
          'fav' => context.l.commonFavorites,
          'history' => context.l.commonHistory,
          _ =>
            _playlist(ref, listId)?.name ??
                // Плейлист удалили прямо во время воспроизведения — очередь
                // играет дальше, а называть её больше нечем.
                context.l.commonPlaylist,
        };
      case SetSource(:final set):
        return set.title;
      case ArtistSource(:final artist):
        return artist.name;
      case PlainSource(:final label):
        return label;
      case WaveSource(:final label):
        return label;
    }
  }
}

UserPlaylist? _playlist(WidgetRef ref, String id) {
  for (final playlist in ref.watch(libraryProvider).playlists) {
    if (playlist.id == id) return playlist;
  }
  return null;
}

/// Картинка источника: обложка сета, аватар артиста, коллаж плейлиста либо
/// фирменный тинт раздела — ровно то же, что показывает его карточка.
class _SourceIcon extends ConsumerWidget {
  const _SourceIcon({required this.source});

  final PlaySource? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final radius = t.radius * 0.4;

    switch (source) {
      case null:
        return _tint(t, radius, t.ovlBg, t.muted, SolarIconsBold.musicNote);
      case LibSource(:final listId):
        switch (listId) {
          case 'all':
            return _tint(
              t,
              radius,
              t.sysAllTint,
              t.sysAllIco,
              SolarIconsOutline.musicNote,
            );
          case 'fav':
            return _tint(
              t,
              radius,
              t.sysFavTint,
              t.sysFavIco,
              SolarIconsBold.heart,
            );
          case 'history':
            return _tint(
              t,
              radius,
              t.sysHistTint,
              t.sysHistIco,
              SolarIconsOutline.clockCircle,
            );
        }
        // Плейлист: своя обложка → коллаж из первых треков, как на его плитке.
        final lib = ref.watch(libraryProvider);
        final playlist = _playlist(ref, listId);
        return Cover(
          url: playlist?.cover,
          size: _iconSize,
          radius: radius,
          covers: playlist == null
              ? const <String?>[]
              : lib.tracksOf(playlist).map((track) => track.cover),
        );
      case WaveSource():
        // Волна — не список, обложки у неё нет: значок берёт акцент темы, как
        // и её карточка на главной.
        return _tint(t, radius, t.ovlBg, t.accent, SolarIconsBold.playStream);
      case SetSource(:final set):
        return Cover(url: set.cover, size: _iconSize, radius: radius);
      case ArtistSource(:final artist):
        return Cover(url: artist.avatar, size: _iconSize, circle: true);
      case PlainSource(:final cover, :final icon):
        if (cover != null) {
          return Cover(url: cover, size: _iconSize, radius: radius);
        }
        return switch (icon) {
          PlainSourceIcon.search => _tint(
            t,
            radius,
            t.ovlBg,
            t.text2,
            SolarIconsOutline.magnifier,
          ),
          PlainSourceIcon.clock => _tint(
            t,
            radius,
            t.sysHistTint,
            t.sysHistIco,
            SolarIconsOutline.clockCircle,
          ),
          PlainSourceIcon.chart => _tint(
            t,
            radius,
            t.sysAllTint,
            t.sysAllIco,
            SolarIconsOutline.chart_2,
          ),
          PlainSourceIcon.note => _tint(
            t,
            radius,
            t.ovlBg,
            t.muted,
            SolarIconsBold.musicNote,
          ),
        };
    }
  }

  Widget _tint(
    BloomTokens t,
    double radius,
    Color tint,
    Color color,
    IconData icon,
  ) => Container(
    width: _iconSize,
    height: _iconSize,
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Icon(icon, size: _iconSize * 0.54, color: color),
  );
}
