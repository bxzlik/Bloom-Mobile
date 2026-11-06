/// The app over an open profile: theme, language, router, the welcome and
/// toasts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/store/settings_store.dart';
import '../features/customization/ui/app_background.dart';
import '../features/settings/user_fonts.dart';
import '../shared/ui/bloom_toast.dart';
import 'router.dart';
import 'theme/bloom_theme.dart';
import 'welcome.dart';

class BloomApp extends ConsumerWidget {
  const BloomApp({super.key, this.firstRun = false});

  /// Show the word of welcome over the app.
  final bool firstRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(settingsProvider).tokens;
    // The background picture lies UNDER the UI, and only those that must let it
    // through drop their fill: router pages, the shell, artist and set pages
    // (see `pageBackground`). The full player and sheets over it stay solid:
    // the background isn't wanted in the player.
    final bgOn = ref.watch(backgroundOnProvider);

    return MaterialApp.router(
      title: 'Bloom',
      debugShowCheckedModeBanner: false,
      // `locale: null` takes the system's language, matched against
      // supportedLocales, where English comes first and so acts as the
      // fallback. A language picked by hand is passed explicitly.
      locale: ref.watch(settingsProvider).locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior: const SpringScroll(),
      theme: buildBloomTheme(
        tokens,
        transparentPages: bgOn,
        fontFamily: ref.watch(uiFontProvider),
      ),
      // The background goes under the navigator: one for the whole app, neither
      // repainted per transition nor moving with a page. Toasts go over it, so
      // no route covers them.
      //
      // System bars follow the theme through a region rather than a one-off
      // call: the open player sets its own over this one, and with nothing
      // under it the bars would keep the player's look once it folds.
      builder: (_, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemBarsStyle(tokens),
        child: Welcome(
          show: firstRun,
          child: ToastHost(
            child: AppBackground(child: child ?? const SizedBox()),
          ),
        ),
      ),
      routerConfig: bloomRouter,
    );
  }
}

/// The iPhone's springy edge on every phone: Android's stretch goes.
class SpringScroll extends MaterialScrollBehavior {
  const SpringScroll();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
