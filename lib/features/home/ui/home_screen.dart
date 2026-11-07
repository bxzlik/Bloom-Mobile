/// Home, top down: the wave on a screen of its own, then a magnet, then the
/// shelves: what's picked for the listener ("for you", "similar to") ahead of
/// what is the same for everyone (releases and the chart). A shelf with nothing
/// in it yet isn't there at all; with none, and none on the way, the shelves'
/// screen says so. One header stands over both screens.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/pressable.dart';
import '../../player/ui/mini_player.dart';
import '../../profile/profile_store.dart';
import '../../profile/ui/profile_avatar.dart';
import '../../wave/ui/wave_hero.dart';
import '../discover_store.dart';
import '../for_you.dart';
import '../similar_to.dart';
import 'for_you_section.dart';
import 'home_sections.dart';
import 'magnet_scroll.dart';
import 'similar_to_section.dart';

/// The mini player is back by this share of the way to the shelves.
const double _cardBackAt = 0.35;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  final MagnetStop _stop = MagnetStop();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final off = _scroll.offset;
    _stop.settle(off);
    waveHoldsCard.value = (1 - off / (_stop.at * _cardBackAt)).clamp(0.0, 1.0);
  }

  /// A scroll that touched the way between the screens, until it ends.
  bool _crossing = false;

  /// The way between the screens doesn't fold the bars: the card comes out
  /// whole, and folds once the shelves scroll on. The whole scroll is held,
  /// not just the way: the snap's spring overshoots into the shelves and back.
  bool _holdCrossing(ScrollNotification n) {
    if (n.depth != 0) return false;
    final between = n.metrics.pixels < _stop.at - 0.5;
    if (n is ScrollStartNotification) _crossing = between;
    if (between) _crossing = true;
    final hold = _crossing;
    if (n is ScrollEndNotification) _crossing = false;
    return hold;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The panel listening to this is mid-build too.
    final top = ModalRoute.isCurrentOf(context) ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      homeOnTop.value = top;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = bottomBarsInset(context);
    final bg = context.bloom.bg;
    _stop.at = screen;
    return Stack(
      children: [
        // The wave's stage runs up under the status bar.
        NotificationListener<ScrollNotification>(
          onNotification: _holdCrossing,
          child: CustomScrollView(
            controller: _scroll,
            physics: MagnetScrollPhysics(_stop),
            slivers: [
              SliverToBoxAdapter(child: WaveHero(scroll: _scroll)),
              // At least a screen tall: with few shelves the magnet still has
              // somewhere to land.
              SliverToBoxAdapter(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: screen),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: top + kHomeHeaderHeight,
                      bottom: bottom + 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ForYouSection(),
                        const SimilarToSection(),
                        const DiscoverSection(mode: DiscoverMode.newReleases),
                        const DiscoverSection(mode: DiscoverMode.charts),
                        _HomeEmpty(
                          height:
                              screen - top - kHomeHeaderHeight - bottom - 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // It stands still while the screens swap and leaves with the shelves.
        Positioned(
          top: top,
          left: 0,
          right: 0,
          height: kHomeHeaderHeight,
          child: ListenableBuilder(
            listenable: _scroll,
            builder: (context, child) {
              final off = _scroll.hasClients ? _scroll.offset : 0.0;
              return Transform.translate(
                offset: Offset(0, math.min(0, _stop.at - off)),
                child: child,
              );
            },
            child: const _TopBar(),
          ),
        ),
        // The shelves don't: a veil of the page's colour comes in as they
        // reach the status bar.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: _scroll,
              builder: (context, _) {
                final off = _scroll.hasClients ? _scroll.offset : 0.0;
                final k = ((off - (_stop.at - top - 80)) / 80).clamp(0.0, 1.0);
                return ColoredBox(color: bg.withValues(alpha: k));
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Not a shelf came and none is on its way: a word in the middle of the
/// shelves' screen in place of a blank one.
class _HomeEmpty extends ConsumerWidget {
  const _HomeEmpty({required this.height});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forYou = ref.watch(forYouProvider);
    final similar = ref.watch(similarToProvider);
    final fresh = ref.watch(discoverProvider(DiscoverMode.newReleases));
    final charts = ref.watch(discoverProvider(DiscoverMode.charts));
    final some =
        forYou != null ||
        similar != null ||
        fresh.isLoading ||
        fresh.valueOrNull != null ||
        charts.isLoading ||
        charts.valueOrNull != null;
    if (some) return const SizedBox.shrink();
    final fy = ref.watch(forYouProvider.notifier).working;
    final sim = ref.watch(similarToProvider.notifier).working;
    final theme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([fy, sim]),
      builder: (context, _) {
        if (fy.value || sim.value) return const SizedBox.shrink();
        return SizedBox(
          height: math.max(0, height),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l.homeEmpty,
                    textAlign: TextAlign.center,
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l.homeEmptyHint,
                    textAlign: TextAlign.center,
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // A swipe starting on the logo still scrolls what's under it.
          IgnorePointer(
            child: BloomMark(size: _kHeaderItem, color: context.bloom.text),
          ),
          const Spacer(),
          const _ProfileButton(),
        ],
      ),
    );
  }
}

/// Way into the profile: the avatar itself, flying from here into the page's
/// header. The flight tag is an instance's [UniqueKey] rather than a shared
/// string: two cards with one tag in a tree throw when the transition starts.
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
    return Pressable(
      onTap: () => context.go(kProfileLocation, extra: CoverFlight(tag: _tag)),
      child: ProfileAvatar(
        profile: profile,
        size: _kHeaderItem,
        flightTag: _tag,
      ),
    );
  }
}
