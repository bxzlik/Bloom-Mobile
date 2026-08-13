/// Коллаж из обложек первых треков — картинка списка, у которого своей нет.
///
/// Один в один десктопный `PlaylistCover`: сколько РАЗНЫХ обложек нашлось в
/// начале списка, такой и коллаж — 1 на всю площадь, 2 половинами, 3 большой
/// слева плюс две справа, 4 сеткой 2×2. Ни одной — остаётся [fallback]
/// (заглушка карточки или тинт раздела).
///
/// Обложки приходят готовыми ссылками в порядке списка: коллаж ничего не знает
/// ни про плейлисты, ни про библиотеку, и одинаково годится и плитке, и шапке.
library;

import 'package:flutter/material.dart';

import '../../core/store/cover_store.dart';

/// Первые до четырёх разных непустых обложек — в порядке списка.
///
/// Дубли отсеиваются: у альбома все треки с одной картинкой, и сетка 2×2 из
/// четырёх её копий выглядела бы поломанной, а не коллажем.
List<String> pickCollageCovers(Iterable<String?> covers) {
  final out = <String>[];
  for (final cover in covers) {
    if (cover == null || cover.isEmpty || out.contains(cover)) continue;
    out.add(cover);
    if (out.length == 4) break;
  }
  return out;
}

class CoverCollage extends StatelessWidget {
  const CoverCollage({super.key, required this.covers, required this.fallback});

  /// Обложки треков списка в его порядке — с пустыми и повторами, разбор
  /// внутри.
  final Iterable<String?> covers;

  /// Чем занять место, если обложек нет вовсе. Им же закрывается ячейка,
  /// картинка которой не загрузилась.
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final picked = pickCollageCovers(covers);
    if (picked.isEmpty) return fallback;
    if (picked.length == 1) return _cell(picked.first);

    // Две обложки — колонки во всю высоту; три и четыре — два ряда, и при трёх
    // первая занимает левую колонку целиком.
    if (picked.length == 2) {
      return Row(children: [_half(picked[0]), _half(picked[1])]);
    }
    if (picked.length == 3) {
      return Row(
        children: [
          _half(picked[0]),
          Expanded(
            child: Column(children: [_half(picked[1]), _half(picked[2])]),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: Row(children: [_half(picked[0]), _half(picked[1])])),
        Expanded(child: Row(children: [_half(picked[2]), _half(picked[3])])),
      ],
    );
  }

  /// Доля коллажа: `Expanded` в обе стороны — ряды и колонки делят площадь
  /// поровну, размер задаёт родитель.
  Widget _half(String cover) => Expanded(child: _cell(cover));

  Widget _cell(String cover) {
    final image = coverImage(cover);
    if (image == null) return fallback;
    return SizedBox.expand(
      child: Image(
        image: image,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
