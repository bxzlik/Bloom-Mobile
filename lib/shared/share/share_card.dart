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
/// Карточка не зависит от темы приложения — это картинка, которая уедет в чужой
/// мессенджер, а не поверхность интерфейса. Плоско-чёрной она быть перестала:
/// фон строится из тона обложки ([ShareCardShell]), как на ПК.
library;

import 'package:flutter/material.dart';

/// Дизайн-бокс карточки (ПК: `CARD_W = 380`).
const double kShareCardW = 380;

/// Во сколько раз снимок крупнее дизайн-бокса. На ПК `SCALE = 2`; берём 3 —
/// 1140 px по ширине, с запасом для любой ленты и без гигантского PNG.
const double kShareCardCapture = 3;

/// Скругление карточки и толщина её рамки (ПК: `RADIUS`, `lineWidth 2`).
const double kShareCardRadius = 28;

/// Линейки внутри карточки. На цветном фоне десктопные .07 не видно вовсе.
const double kShareRuleAlpha = 0.14;

const double _pad = 20;
const double _logoSz = 38;
const double _metaGap = 11;
const double _headerPb = 18;
const double _headerMb = 18;
const double _coverR = 16;
const double _coverMb = 20;
const double _titleFs = 22;
const double _titleMb = 7;
const double _artistFs = 13;
const double _artistMb = 20;
const double _bottomPad = 22;

/// Вес заголовков карточек. На ПК веса опустили с 700/800 до 600 — здесь тот же
/// шаг, иначе порт выглядит жирнее оригинала.
const FontWeight kShareBold = FontWeight.w600;

/// Каркас обеих карточек: фон из тона, скругление и рамка.
///
/// Фон — те же два слоя, что рисует `paintToneBackground` на ПК: вертикальный
/// градиент тон → чёрный на три четверти высоты и мягкий блик в правом верхнем
/// углу. Ручки (докуда добивает тон, плотность у кромки, сила блика) держим
/// здесь же — их подкручивают вместе с десктопными.
class ShareCardShell extends StatelessWidget {
  const ShareCardShell({super.key, required this.tone, required this.child});

  /// Тон карточки — `shareToneFromHsl` по её обложке/аватару.
  final Color tone;

  final Widget child;

  /// Докуда сверху добивает тон (доля высоты) и его плотность у кромки.
  static const double _reach = 0.74;
  static const double _topAlpha = 0.96;

  /// Блик: сила и радиус (доля короткой стороны).
  static const double _sheenAlpha = 0.4;
  static const double _sheenR = 0.95;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(kShareCardRadius);
    final sheen = HSLColor.fromColor(tone);

    return Container(
      width: kShareCardW,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: radius,
      ),
      // Рамка поверх содержимого — иначе её съедает клип скругления.
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tone.withValues(alpha: _topAlpha),
                    tone.withValues(alpha: 0.42),
                    tone.withValues(alpha: 0.12),
                    tone.withValues(alpha: 0),
                  ],
                  // Доли всей высоты: на ПК градиент кладётся на верхние 74%
                  // со своими стопами 0 / 0.45 / 0.75 / 1. Предпоследняя кладёт
                  // хвост положе — без неё конец градиента даёт границу.
                  stops: const [0, _reach * 0.45, _reach * 0.75, _reach],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.64, -1.08),
                  radius: _sheenR,
                  colors: [
                    sheen
                        .withLightness((sheen.lightness + 0.2).clamp(0.0, 1.0))
                        .toColor()
                        .withValues(alpha: _sheenAlpha),
                    tone.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/* Свечения тоном под обложкой/аватаром нет: владелец убрал его 2026-09-19 —
   цветная тень читалась как лишняя обводка по кругу, а фон карточки должен
   идти только сверху вниз. Та же правка на ПК, в `cardKit.ts`. */

class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.title,
    required this.artist,
    required this.cover,
    required this.logo,
    required this.tone,
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

  /// Тон фона, посчитанный по обложке.
  final Color tone;

  @override
  Widget build(BuildContext context) {
    const coverSz = kShareCardW - _pad * 2;

    return ShareCardShell(
      tone: tone,
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
                    fontWeight: kShareBold,
                  ),
                ),
              ],
            ),
          ),
          // Разделителя под шапкой нет (владелец убрал 2026-09-19): её от
          // обложки отделяет сам отступ.
          const SizedBox(height: _headerMb),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _pad),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(_coverR),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_coverR),
                child: SizedBox(
                  width: coverSz,
                  height: coverSz,
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
              // Две строки, как на ПК: длинное название теряет хвост, а не
              // половину слов.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: _titleFs,
                fontWeight: kShareBold,
                height: 1.26,
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
                  // На цветном фоне десктопные .36 не читались.
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: _artistFs,
                  height: 1.3,
                ),
              ),
            ),
          // Нижний отступ на ПК одинаков и с артистом, и без него.
          const SizedBox(height: _artistMb + _bottomPad),
        ],
      ),
    );
  }
}

/// Заглушка обложки — та же нота, что рисует десктопный `draw` без картинки.
class _NoCover extends StatelessWidget {
  const _NoCover();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '♫',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.14),
          fontSize: (kShareCardW - _pad * 2) * 0.14,
        ),
      ),
    );
  }
}
