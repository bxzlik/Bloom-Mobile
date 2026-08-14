/// Главная — витрина из секций, порядок как на десктопе (`app/pages/HomePage`):
/// «Продолжить» → «Любимые»/«История» → «Новинки» → «Чарты» → «Недавно
/// слушали» → «Плейлисты».
///
/// Секции сами решают, показываться ли им: пустая история и пустая витрина
/// схлопываются в ничто, поэтому на свежей установке остаются только карточки
/// разделов и плитка «Новый плейлист».
///
/// «Моя волна» на десктопе стоит рядом с «Продолжить»; её движок рекомендаций
/// на мобилку ещё не переносился — это отдельный заход.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../profile/profile_store.dart';
import '../../profile/ui/profile_avatar.dart';
import '../discover_store.dart';
import 'continue_card.dart';
import 'home_sections.dart';
import 'quick_cards.dart';

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
                ContinueCard(),
                QuickCards(),
                DiscoverSection(mode: DiscoverMode.newReleases),
                DiscoverSection(mode: DiscoverMode.charts),
                RecentSection(),
                PlaylistsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          // Пилюля профиля: знак bloom + имя. Знак без подложки — он и так
          // читается на плёнке пилюли. Высота ровно как у круглых кнопок
          // справа, иначе шапка выглядит съехавшей.
          Container(
            height: kHeaderControl,
            padding: const EdgeInsets.fromLTRB(15, 0, 19, 0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.pill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BloomMark(size: 20, color: t.text),
                const SizedBox(width: 10),
                Text('Bloom', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const Spacer(),
          CircleIconButton(icon: SolarIconsOutline.bell, onTap: () {}),
          const SizedBox(width: 8),
          CircleIconButton(
            icon: SolarIconsOutline.magnifier,
            onTap: () => context.go('/home/search'),
          ),
          const SizedBox(width: 8),
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
      onTap: () => context.go('/home/profile', extra: CoverFlight(tag: _tag)),
      child: ProfileAvatar(
        profile: profile,
        size: kHeaderControl,
        flightTag: _tag,
      ),
    );
  }
}
