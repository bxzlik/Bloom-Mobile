/// Аватар профиля: своя картинка либо винил-диск, в кольце обводки.
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

import '../../../core/store/cover_store.dart';
import '../../../shared/ui/cover_hero.dart';
import '../profile_store.dart';
import 'disc_avatar.dart';

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
    final image = coverImage(profile.avatar);
    final Widget face = image == null
        ? DiscAvatar(idx: profile.discIdx, color: profile.discColor)
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
