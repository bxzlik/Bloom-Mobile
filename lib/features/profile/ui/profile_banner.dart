/// Заливка обложки профиля — порт `BannerFill` ПК: своя картинка, иначе цвет,
/// градиент под углом или («Авто») тон обложки самого слушаемого трека.
///
/// Профиль передаётся снаружи: редактор рисует так же свой черновик.
library;

import 'dart:math' show cos, sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/cover_store.dart';
import '../../settings/cover_accent.dart';
import '../profile_store.dart';
import '../stats.dart';

/// Тёмный тон обложки для «Авто» — та же полоса, что у фона миниплеера (на
/// ПК обе берут `darkOf`). Кеш до перезапуска: скан — это загрузка картинки.
final _autoToneProvider = FutureProvider.family<Color?, String?>((
  ref,
  cover,
) async {
  final hsl = await extractCoverHsl(cover);
  return hsl == null ? null : miniBgFromHsl(hsl);
});

class ProfileBannerFill extends ConsumerWidget {
  const ProfileBannerFill({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = coverImage(profile.banner);
    if (image != null) return Image(image: image, fit: BoxFit.cover);

    final t = context.bloom;
    var from = profile.bannerColor;
    var to = from;
    var angle = profile.bannerAngle;
    switch (profile.bannerMode) {
      case BannerColorMode.solid:
        return ColoredBox(color: from);
      case BannerColorMode.gradient:
        to = profile.bannerColor2;
      case BannerColorMode.auto:
        final cover = ref.watch(profileStatsProvider.select((s) => s.topCover));
        // Пока тон не посчитан (или слушать ещё нечего) — свой цвет профиля.
        from = ref.watch(_autoToneProvider(cover)).value ?? from;
        to = Color.lerp(from, t.blockColor, 0.65)!;
        angle = 135;
    }
    // CSS-угол считается от «вверх» по часовой стрелке, у [Alignment] ось Y
    // смотрит вниз — отсюда разворот знаков.
    final a = angle * pi / 180;
    final dx = sin(a);
    final dy = -cos(a);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: [from, to],
        ),
      ),
    );
  }
}
