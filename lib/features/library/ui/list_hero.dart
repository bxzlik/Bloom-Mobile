/// Фон hero-шапки списка библиотеки — общий у обычного экрана и режима правки.
///
/// Порядок такой же, как на десктопе: своя обложка плейлиста → коллаж 2×2 из
/// первых треков → плоский тинт раздела с его цветной иконкой.
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/cover_store.dart';

class ListHeroBackground extends StatelessWidget {
  const ListHeroBackground({
    super.key,
    required this.listId,
    required this.cover,
    required this.tracks,
  });

  /// `all` / `fav` / `history` либо id пользовательского плейлиста.
  final String listId;

  /// Своя обложка плейлиста; у встроенных разделов её нет.
  final String? cover;

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    final image = coverImage(cover);
    if (image != null) {
      return Image(
        image: image,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _tint(t),
      );
    }

    final covers = tracks
        .map((x) => x.cover)
        .whereType<String>()
        .take(4)
        .toList();
    if (covers.length == 4) {
      return GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final c in covers)
            Image.network(
              c,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _tint(t),
            ),
        ],
      );
    }
    if (covers.isNotEmpty) {
      return Image.network(
        covers.first,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _tint(t),
      );
    }
    return _tint(t);
  }

  Widget _tint(BloomTokens t) {
    final (Color tint, Color color, IconData icon) = switch (listId) {
      'fav' => (t.sysFavTint, t.sysFavIco, SolarIconsBold.heart),
      'history' => (t.sysHistTint, t.sysHistIco, SolarIconsOutline.clockCircle),
      'all' => (t.sysAllTint, t.sysAllIco, SolarIconsOutline.musicNote),
      _ => (t.ovlBg, t.muted, SolarIconsBold.musicNote),
    };
    return ColoredBox(
      color: tint,
      child: Center(child: Icon(icon, size: 64, color: color)),
    );
  }
}
