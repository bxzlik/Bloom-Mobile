/// Карточка «Поделиться профилем» — порт десктопного
/// `features/profile/lib/buildProfileCard.ts`.
///
/// На ПК она рисуется на `canvas`; здесь, как и трековая [ShareCard], собрана
/// ВИДЖЕТАМИ и снимается `RepaintBoundary` — перенос строк, эллипсис и круглый
/// аватар у виджетов уже есть.
///
/// Раскладка считается в том же дизайн-боксе 380, что и у трековой карточки,
/// и все числа взяты с ПК один в один: шапка Bloom, ряд «аватар + ник/био» и
/// сетка 2×2 со статистикой. Футера (линейка, число прослушиваний, белый
/// кружок со стрелкой) и разделителя под шапкой больше нет — владелец убрал их
/// 2026-09-19.
///
/// Карточка не зависит от темы приложения — это картинка, которая уедет в чужой
/// мессенджер. Фон общий с трековой ([ShareCardShell]) и строится из тона
/// аватара, а без аватара — из цвета обложки профиля. Серые плашки под цифрами
/// убраны вслед за ПК: на цветном фоне они выглядели дёшево, вместо них две
/// линейки крестом.
library;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/share/share_card.dart'
    show ShareCardShell, kShareBold, kShareCardW, kShareRuleAlpha;
import '../profile_store.dart';

const double _pad = 20;
const double _logoSz = 38;
const double _metaGap = 11;
const double _headerPb = 18;
const double _headerMb = 18;

const double _profAva = 64;
const double _profMb = 20;

/// Зазор между колонками; по его середине идёт вертикальная линейка.
const double _gridGap = 20;
const double _colW = (kShareCardW - _pad * 2 - _gridGap) / 2;
const double _cellValFs = 24;
const double _cellValMin = 13;
const double _cellValMb = 8;
const double _cellLblFs = 9;
const double _cellPadV = 14;
const double _cellH =
    _cellPadV + _cellValFs + _cellValMb + _cellLblFs + _cellPadV;

/// Насколько линейка между колонками короче сетки сверху и снизу.
const double _ruleInset = _cellPadV * 0.4;

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
    required this.tone,
  });

  final UserProfile profile;
  final ProfileCardStats stats;

  /// Уже ЗАГРУЖЕННЫЙ аватар: в снимок попадает ровно то, что отрисовано, и
  /// недогруженная картинка стала бы дыркой в карточке. `null` — заглушки нет,
  /// рисуем градиент обложки с первой буквой ника (десктопный откат).
  final ImageProvider? avatar;

  /// Знак Bloom в шапке — тоже готовым провайдером и по той же причине.
  final ImageProvider? logo;

  /// Тон фона: по аватару, а без него — по обложке профиля.
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final name = profile.displayName(l);
    final bio = profile.bio.trim();

    return ShareCardShell(
      tone: tone,
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
                          fontWeight: kShareBold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.shareProfileSub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
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
          // Разделителя под шапкой нет (владелец убрал 2026-09-19).
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
                          fontWeight: kShareBold,
                        ),
                      ),
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          bio,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
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
          // ── Сетка 2×2 на линейках ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _pad),
            child: Column(
              children: [
                Row(
                  children: [
                    _Cell(value: '${stats.tracks}', label: l.statsTracks),
                    const _VRule(insetTop: _ruleInset),
                    _Cell(value: '${stats.plays}', label: l.statsPlays),
                  ],
                ),
                const _HRule(),
                Row(
                  children: [
                    _Cell(value: stats.time, label: l.statsTime),
                    const _VRule(insetBottom: _ruleInset),
                    _Cell(
                      value: stats.favArtist ?? '—',
                      label: l.statsFavArtist,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Футера (линейка, число прослушиваний, белый кружок со стрелкой)
          // нет — владелец убрал его 2026-09-19, карточка кончается сеткой.
          const SizedBox(height: _bottomPad),
        ],
      ),
    );
  }
}

/// Линейка между колонками сетки. Живёт в зазоре между ячейками, поэтому обе
/// половины сетки остаются ровно по [_colW].
class _VRule extends StatelessWidget {
  const _VRule({this.insetTop = 0, this.insetBottom = 0});

  final double insetTop;
  final double insetBottom;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _gridGap,
      height: _cellH,
      child: Padding(
        padding: EdgeInsets.only(top: insetTop, bottom: insetBottom),
        child: Center(
          child: SizedBox(
            width: 1,
            height: double.infinity,
            child: ColoredBox(
              color: Colors.white.withValues(alpha: kShareRuleAlpha),
            ),
          ),
        ),
      ),
    );
  }
}

/// Линейка между рядами сетки.
class _HRule extends StatelessWidget {
  const _HRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: Colors.white.withValues(alpha: kShareRuleAlpha)),
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
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: _profAva * 0.4,
                      fontWeight: kShareBold,
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
    return SizedBox(
      width: _colW,
      height: _cellH,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _cellPadV),
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
                    fontWeight: kShareBold,
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
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: _cellLblFs,
                height: 1,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кегль значения: длинное имя артиста ужимаем, но не мельче [_cellValMin] —
/// дальше десктоп режет эллипсисом, и мы вслед за ним. Меряем сами, а не
/// `FittedBox`: тому нижнего предела не задать, и «Nine Inch Nails» стал бы
/// нечитаемой строчкой в 4 пункта.
double _fitFontSize(String value) {
  // Ячейки больше не в плашках, но от линейки значение всё равно отступает.
  const maxW = _colW - 4;
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: const TextStyle(
        fontSize: _cellValFs,
        height: 1,
        fontWeight: kShareBold,
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
