/// Фон hero-шапки списка библиотеки — общий у обычного экрана и режима правки.
///
/// У встроенных разделов всегда плоский тинт с цветной иконкой; у плейлистов —
/// своя обложка → коллаж из первых треков (`CoverCollage`, он же на плитке
/// библиотеки) → тот же тинт.
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/cover_collage.dart';

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

  /// У `all` / `fav` / `history` своей обложки нет и коллаж не собираем —
  /// шапка всегда остаётся фирменным тинтом раздела.
  bool get _system => listId == 'all' || listId == 'fav' || listId == 'history';

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    if (_system) return _tint(t);

    final image = coverImage(cover);
    if (image != null) {
      return Image(
        image: image,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _tint(t),
      );
    }

    return CoverCollage(
      covers: tracks.map((track) => track.cover),
      fallback: _tint(t),
    );
  }

  Widget _tint(BloomTokens t) {
    final (Color tint, Color color, IconData icon) = switch (listId) {
      'fav' => (t.sysFavTint, t.sysFavIco, SolarIconsBold.heart),
      'history' => (t.sysHistTint, t.sysHistIco, SolarIconsOutline.clockCircle),
      'all' => (t.sysAllTint, t.sysAllIco, SolarIconsOutline.musicNote),
      _ => (t.ovlBg, t.muted, SolarIconsBold.musicNote),
    };
    return ColoredBox(
      // Тинт раздела мешаем с поверхностью темы: как плёнка он показывал бы
      // сквозь шапку картинку-фон, а шапка обязана быть своего цвета.
      color: Color.alphaBlend(tint, t.blockColor),
      child: Center(child: Icon(icon, size: 64, color: color)),
    );
  }
}
