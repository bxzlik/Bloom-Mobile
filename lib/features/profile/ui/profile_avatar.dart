/// Аватар профиля: своя картинка либо заглушка с человечком.
///
/// Один виджет на все места — кнопка в шапке главной, шапка страницы профиля,
/// превью в редакторе, — поэтому профиль приходит параметром: редактор рисует
/// им ЧЕРНОВИК, а не то, что уже сохранено.
///
/// Размер задаётся снаружи [SizedBox], а не внутри: при перелёте кнопка шапки
/// превращается в большой аватар страницы, и распорка с фиксированной стороной
/// внутри летящей копии не дала бы ей вырасти.
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/cover_hero.dart';
import '../profile_store.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    required this.size,
    this.flightTag,
  });

  final UserProfile profile;
  final double size;

  /// Метка перелёта на страницу профиля; `null` — никуда не летим.
  final Object? flightTag;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final image = coverImage(profile.avatar);
    // Своей картинки нет — тот же приём, что у пустой обложки: сплошная тёмная
    // заливка и приглушённый знак поверх. Только знак тут человечек, а не bloom:
    // на месте лица логотип читался бы как «трек без обложки».
    final Widget face = image == null
        ? ColoredBox(
            color: t.coverEmpty,
            child: Center(
              child: Icon(
                SolarIconsBold.user,
                size: size * 0.46,
                color: t.text.withValues(alpha: 0.22),
              ),
            ),
          )
        : Image(image: image, fit: BoxFit.cover);

    return SizedBox(
      width: size,
      height: size,
      child: CoverHero(
        tag: flightTag,
        shape: BorderRadius.circular(size / 2),
        // Кольца вокруг аватара нет: он его не хочет — ни акцентного, ни
        // своего цветом (десктопная «Обводка» на телефон не переехала).
        child: ClipOval(child: face),
      ),
    );
  }
}
