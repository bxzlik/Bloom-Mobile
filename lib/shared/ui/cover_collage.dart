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

import '../../app/theme/tokens.dart';
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

  /// Чем занять место, если обложек нет вовсе.
  ///
  /// Только на всю площадь: у заглушки свой значок (тинт раздела, знак bloom),
  /// и в ячейке коллажа он бы повторился — четыре не загрузившиеся картинки
  /// давали четыре иконки вместо картинки. Упавшая ячейка гасится ровной
  /// плашкой, см. [_blank].
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final picked = pickCollageCovers(covers);
    if (picked.isEmpty) return fallback;
    // Одна обложка — это и есть вся площадь: не загрузилась, значит показывать
    // нечего и заглушка раздела уместна.
    if (picked.length == 1) return _cell(picked.first, fallback);

    final blank = _blank(context.bloom);

    // Две обложки — колонки во всю высоту; три и четыре — два ряда, и при трёх
    // первая занимает левую колонку целиком.
    if (picked.length == 2) {
      return Row(children: [_half(picked[0], blank), _half(picked[1], blank)]);
    }
    if (picked.length == 3) {
      return Row(
        children: [
          _half(picked[0], blank),
          Expanded(
            child: Column(
              children: [_half(picked[1], blank), _half(picked[2], blank)],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [_half(picked[0], blank), _half(picked[1], blank)],
          ),
        ),
        Expanded(
          child: Row(
            children: [_half(picked[2], blank), _half(picked[3], blank)],
          ),
        ),
      ],
    );
  }

  /// Ячейка без картинки — глухая плашка подложки, без значка: рядом с
  /// соседними такими же коллаж читается как одно приглушённое пятно, а не как
  /// сетка иконок.
  Widget _blank(BloomTokens t) => ColoredBox(color: t.coverEmpty);

  /// Доля коллажа: `Expanded` в обе стороны — ряды и колонки делят площадь
  /// поровну, размер задаёт родитель.
  Widget _half(String cover, Widget empty) =>
      Expanded(child: _cell(cover, empty));

  Widget _cell(String cover, Widget empty) {
    final image = coverImage(cover);
    if (image == null) return empty;
    return SizedBox.expand(
      child: Image(
        image: image,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => empty,
      ),
    );
  }
}
