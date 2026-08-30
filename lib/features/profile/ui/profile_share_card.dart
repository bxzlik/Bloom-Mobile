/// Карточка «Поделиться профилем» — порт десктопного
/// `features/profile/lib/buildProfileCard.ts`.
///
/// На ПК она рисуется на `canvas`; здесь, как и трековая [ShareCard], собрана
/// ВИДЖЕТАМИ и снимается `RepaintBoundary` — перенос строк, эллипсис и круглый
/// аватар у виджетов уже есть.
///
/// Раскладка считается в том же дизайн-боксе 380, что и у трековой карточки,
/// и все числа взяты с ПК один в один: шапка Bloom, ряд «аватар + ник/био»,
/// сетка 2×2 со статистикой и футер с числом прослушиваний.
///
/// Карточка ЧЁРНАЯ в любой теме приложения — это картинка, которая уедет в
/// чужой мессенджер, а не поверхность интерфейса.
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/share/share_card.dart' show kShareCardW;
import '../profile_store.dart';

const double _pad = 20;
const double _logoSz = 38;
const double _metaGap = 11;
const double _headerPb = 18;
const double _headerMb = 18;

const double _profAva = 64;
const double _profMb = 16;

const double _gridGap = 10;
const double _colW = (kShareCardW - _pad * 2 - _gridGap) / 2;
const double _cellPadH = 8;
const double _cellValFs = 20;
const double _cellValMin = 11;
const double _cellValMb = 6;
const double _cellLblFs = 8;
const double _cellPadV = 12;
const double _cellH =
    _cellPadV + _cellValFs + _cellValMb + _cellLblFs + _cellPadV;

const double _gridMb = 12;
const double _footerPt = 18;
const double _footerBtn = 40;
const double _bottomPad = 22;

/// Числа для сетки — считаются снаружи, из `profileStatsProvider`.
class ProfileCardStats {
  const ProfileCardStats({
    required this.tracks,
    required this.plays,
    required this.time,
    required this.favArtist,
  });

  /// Сколько треков в библиотеке.
  final int tracks;

  final int plays;

  /// Готовая строка времени (`fmtDurLong`).
  final String time;

  /// Самый слушаемый исполнитель; `null` — прочерк, как на ПК.
  final String? favArtist;
}

class ProfileShareCard extends StatelessWidget {
  const ProfileShareCard({
    super.key,
    required this.profile,
    required this.stats,
    required this.avatar,
    required this.logo,
  });

  final UserProfile profile;
  final ProfileCardStats stats;

  /// Уже ЗАГРУЖЕННЫЙ аватар: в снимок попадает ровно то, что отрисовано, и
  /// недогруженная картинка стала бы дыркой в карточке. `null` — заглушки нет,
  /// рисуем градиент обложки с первой буквой ника (десктопный откат).
  final ImageProvider? avatar;

  /// Знак Bloom в шапке — тоже готовым провайдером и по той же причине.
  final ImageProvider? logo;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final name = profile.displayName(l);
    final bio = profile.bio.trim();

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
            // ── Шапка: знак Bloom и две строки рядом ──
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Bloom',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.shareProfileSub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _Line(),
            const SizedBox(height: _headerMb),
            // ── Профиль: аватар и ник с био ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: Row(
                children: [
                  _CardAvatar(profile: profile, image: avatar, name: name),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            bio,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.36),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _profMb),
            // ── Сетка 2×2 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: Column(
                children: [
                  Row(
                    children: [
                      _Cell(value: '${stats.tracks}', label: l.statsTracks),
                      const SizedBox(width: _gridGap),
                      _Cell(value: '${stats.plays}', label: l.statsPlays),
                    ],
                  ),
                  const SizedBox(height: _gridGap),
                  Row(
                    children: [
                      _Cell(value: stats.time, label: l.statsTime),
                      const SizedBox(width: _gridGap),
                      _Cell(
                        value: stats.favArtist ?? '—',
                        label: l.statsFavArtist,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Футер ──
            const SizedBox(height: _gridMb + _footerPt / 2),
            const _Line(),
            const SizedBox(height: _footerPt / 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.shareProfilePlays(stats.plays),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.26),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Белый кружок со стрелкой — «открыть в Bloom». Он нарисован,
                  // а не нажимается: карточка уедет картинкой.
                  Container(
                    width: _footerBtn,
                    height: _footerBtn,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      SolarIconsOutline.arrowRight,
                      size: 21,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _bottomPad),
          ],
        ),
      ),
    );
  }
}

/// Тонкая линия шапки и футера — десктопные `rgba(255,255,255,.07)`.
class _Line extends StatelessWidget {
  const _Line();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pad),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: 0.07),
      ),
    );
  }
}

/// Аватар на карточке. Своей картинки нет — градиент обложки профиля с первой
/// буквой ника; человечка со страницы сюда не берём, на ПК в карточке буква.
class _CardAvatar extends StatelessWidget {
  const _CardAvatar({
    required this.profile,
    required this.image,
    required this.name,
  });

  final UserProfile profile;
  final ImageProvider? image;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: _profAva,
        height: _profAva,
        child: image != null
            ? Image(image: image!, fit: BoxFit.cover)
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [profile.bannerColor, profile.bannerColor2],
                  ),
                ),
                child: Center(
                  child: Text(
                    name.characters.firstOrNull?.toUpperCase() ?? 'U',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: _profAva * 0.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Ячейка сетки: крупное значение и капсовая подпись под ним.
class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fs = _fitFontSize(value);
    return Container(
      width: _colW,
      height: _cellH,
      padding: const EdgeInsets.symmetric(
        horizontal: _cellPadH,
        vertical: _cellPadV,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _cellValFs,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fs,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: _cellValMb),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: _cellLblFs,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Кегль значения: длинное имя артиста ужимаем, но не мельче [_cellValMin] —
/// дальше десктоп режет эллипсисом, и мы вслед за ним. Меряем сами, а не
/// `FittedBox`: тому нижнего предела не задать, и «Nine Inch Nails» стал бы
/// нечитаемой строчкой в 4 пункта.
double _fitFontSize(String value) {
  const maxW = _colW - _cellPadH * 2;
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: const TextStyle(
        fontSize: _cellValFs,
        height: 1,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  if (width <= maxW) return _cellValFs;
  return (_cellValFs * maxW / width).floorToDouble().clamp(
    _cellValMin,
    _cellValFs,
  );
}
