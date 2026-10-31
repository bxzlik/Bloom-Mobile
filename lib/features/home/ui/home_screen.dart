/// Home, top down: the wave, then what's picked for the listener ("for you",
/// "similar to") ahead of what is the same for everyone (releases and the
/// chart). A shelf with nothing in it yet isn't there at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../profile/profile_store.dart';
import '../../profile/ui/profile_avatar.dart';
import '../../wave/ui/wave_card.dart';
import '../discover_store.dart';
import 'for_you_section.dart';
import 'home_sections.dart';
import 'similar_to_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TopBar(),
          Expanded(
            child: ListView(
              // Снизу — воздух под миниплеер и таб-бар: они плавают над
              // содержимым, и без запаса последняя лента уезжает под них.
              padding: EdgeInsets.only(bottom: bottomBarsInset(context) + 16),
              children: const [
                WaveCard(),
                ForYouSection(),
                SimilarToSection(),
                DiscoverSection(mode: DiscoverMode.newReleases),
                DiscoverSection(mode: DiscoverMode.charts),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The header's logo and avatar, one size for both.
const double _kHeaderItem = 40;

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          BloomMark(size: _kHeaderItem, color: context.bloom.text),
          const Spacer(),
          const _ProfileButton(),
        ],
      ),
    );
  }
}

/// Вход в профиль — сам аватар, а не значок «пользователь»: с него же он и
/// летит в шапку страницы.
///
/// Метка перелёта — [UniqueKey] у экземпляра, а не общая строка: две карточки
/// с одной меткой в дереве роняют переход исключением, и заводить такую мину
/// на будущее незачем.
class _ProfileButton extends ConsumerStatefulWidget {
  const _ProfileButton();

  @override
  ConsumerState<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends ConsumerState<_ProfileButton> {
  late final Object _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return GestureDetector(
      onTap: () => context.go(kProfileLocation, extra: CoverFlight(tag: _tag)),
      child: ProfileAvatar(
        profile: profile,
        size: _kHeaderItem,
        flightTag: _tag,
      ),
    );
  }
}
