/// Главная — витрина из секций, порядок как на десктопе 3.0 (`app/pages/HomePage`):
/// «Моя волна» → «Продолжить» → «Любимые»/«История» → «Недавно слушали» и
/// «Плейлисты» в один ряд → «Для вас» → «Похожие на» → «Новинки» → «Чарты».
/// Витрины про самого слушателя идут впереди площадочных: те общие для всех.
///
/// Скрыть секцию нельзя и не нужно — у мобилки нет настроек видимости главной.
///
/// Секции сами решают, показываться ли им: пустая история, пустой список
/// плейлистов и пустая витрина схлопываются в ничто, поэтому на свежей
/// установке остаются только карточки разделов.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/store/settings_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/glass.dart';
import '../../notifications/ui/notif_bell.dart';
import '../../profile/profile_store.dart';
import '../../profile/ui/profile_avatar.dart';
import '../../wave/ui/wave_card.dart';
import '../discover_store.dart';
import 'continue_card.dart';
import 'for_you_section.dart';
import 'home_sections.dart';
import 'quick_cards.dart';
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
                ContinueCard(),
                QuickCards(),
                RecentAndPlaylists(),
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

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final tabs = ref.watch(settingsProvider.select((s) => s.navTabs));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          // Пилюля профиля: знак bloom + имя. Знак без подложки — он и так
          // читается на плёнке пилюли. Высота ровно как у круглых кнопок
          // справа, иначе шапка выглядит съехавшей.
          GlassBox(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: kHeaderControl,
              padding: const EdgeInsets.fromLTRB(15, 0, 19, 0),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BloomMark(size: 22, color: t.text),
                  const SizedBox(width: 10),
                  Text(
                    'Bloom',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: kHeaderTitleSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const NotifBell(),
          const SizedBox(width: 8),
          CircleIconButton(
            icon: SolarIconsOutline.magnifier,
            // Лупа остаётся в шапке, даже когда поиск стоит табом, — просто
            // уводит тогда в его ветку, а не открывает вторую страницу поиска
            // внутри главной.
            onTap: () => context.go(searchLocation(tabs)),
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
    final tabs = ref.watch(settingsProvider.select((s) => s.navTabs));
    return GestureDetector(
      onTap: () =>
          context.go(profileLocation(tabs), extra: CoverFlight(tag: _tag)),
      child: ProfileAvatar(
        profile: profile,
        size: kHeaderControl,
        flightTag: _tag,
      ),
    );
  }
}
