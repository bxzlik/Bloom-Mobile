/// Карточка «Поделиться» — порт десктопного `shared/lib/buildShareCard.ts`.
///
/// На ПК она рисуется на `canvas` и уходит в PNG. Здесь, как и постер «Итогов»,
/// она СОБРАНА ВИДЖЕТАМИ и снимается `RepaintBoundary`: перенос строк, эллипсис
/// и скруглённая обложка у виджетов уже есть, а рисовать то же самое второй раз
/// на `Canvas` пришлось бы руками.
///
/// Раскладка считается в фиксированном дизайн-боксе шириной [kShareCardW] — те
/// же 380, что на ПК, поэтому все размеры взяты оттуда один в один и не зависят
/// от диагонали телефона. Высота выходит из содержимого: без артиста карточка
/// ровно на строку короче, как и на десктопе.
///
/// Карточка ЧЁРНАЯ всегда, в любой теме приложения — это картинка, которая
/// уедет в чужой мессенджер, а не поверхность интерфейса.
library;

import 'package:flutter/material.dart';

/// Дизайн-бокс карточки (ПК: `CARD_W = 380`).
const double kShareCardW = 380;

/// Во сколько раз снимок крупнее дизайн-бокса. На ПК `SCALE = 2`; берём 3 —
/// 1140 px по ширине, с запасом для любой ленты и без гигантского PNG.
const double kShareCardCapture = 3;

const double _pad = 20;
const double _logoSz = 38;
const double _metaGap = 11;
const double _headerPb = 18;
const double _headerMb = 18;
const double _coverMb = 16;
const double _titleFs = 22;
const double _titleMb = 6;
const double _artistFs = 13;
const double _artistMb = 20;
const double _bottomPad = 22;

class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.title,
    required this.artist,
    required this.cover,
    required this.logo,
  });

  /// Название трека/альбома/плейлиста либо имя артиста.
  final String title;

  /// Подпись под названием; пустая — строки не будет вовсе.
  final String artist;

  /// Уже ЗАГРУЖЕННАЯ картинка обложки: в снимок попадает ровно то, что
  /// отрисовано, и недогруженная обложка стала бы дыркой в карточке.
  final ImageProvider? cover;

  /// Знак Bloom в шапке. Тоже готовым провайдером и по той же причине.
  final ImageProvider? logo;

  @override
  Widget build(BuildContext context) {
    const coverSz = kShareCardW - _pad * 2;

    return SizedBox(
      width: kShareCardW,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Шапка: знак Bloom и слово рядом.
            Padding(
              padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad, _headerPb),
              child: Row(
                children: [
                  SizedBox(
                    width: _logoSz,
                    height: _logoSz,
                    child: logo == null
                        ? null
                        : Image(image: logo!, fit: BoxFit.contain),
                  ),
                  const SizedBox(width: _metaGap),
                  const Text(
                    'Bloom',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            const SizedBox(height: _headerMb),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: coverSz,
                  height: coverSz,
                  child: ColoredBox(
                    color: const Color(0xFF1A1A1A),
                    child: cover == null
                        ? const _NoCover()
                        : Image(
                            image: cover!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const _NoCover(),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: _coverMb),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad + 4),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: _titleFs,
                  fontWeight: FontWeight.w700,
                  height: 1.22,
                ),
              ),
            ),
            const SizedBox(height: _titleMb),
            if (artist.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _pad + 4),
                child: Text(
                  artist,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.36),
                    fontSize: _artistFs,
                    height: 1.3,
                  ),
                ),
              ),
            // Нижний отступ на ПК одинаков и с артистом, и без него.
            const SizedBox(height: _artistMb + _bottomPad),
          ],
        ),
      ),
    );
  }
}

/// Заглушка обложки — та же нота, что рисует `_scrdDraw` без картинки.
class _NoCover extends StatelessWidget {
  const _NoCover();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '♫',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.12),
          fontSize: (kShareCardW - _pad * 2) * 0.14,
        ),
      ),
    );
  }
}
