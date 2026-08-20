/// Навигация: три таба через [StatefulShellRoute] — у каждого свой стек,
/// состояние вкладки переживает переключение.
///
/// Контейнер веток свой ([BranchCrossfade]) вместо готового `indexedStack`:
/// тот меняет вкладку одним кадром, без перехода.
///
/// Вложенные страницы (поиск, списки библиотеки, разделы настроек) живут
/// ВНУТРИ своей ветки: таб-бар и миниплеер остаются на месте.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/customization/ui/app_background.dart';
import '../features/customization/ui/media_item_screen.dart';
import '../features/customization/ui/media_library_screen.dart';
import '../features/customization/ui/presets_screen.dart';
import '../features/home/ui/home_screen.dart';
import '../features/library/ui/library_screen.dart';
import '../features/library/ui/tracklist_screen.dart';
import '../features/onboarding/onboarding_store.dart';
import '../features/onboarding/ui/onboarding_screen.dart';
import '../features/profile/ui/profile_edit_screen.dart';
import '../features/profile/ui/profile_screen.dart';
import '../features/search/ui/search_screen.dart';
import '../features/settings/ui/appearance_screen.dart';
import '../features/settings/ui/audio_screen.dart';
import '../features/settings/ui/lastfm_screen.dart';
import '../features/settings/ui/logs_screen.dart';
import '../features/settings/ui/player_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/settings/ui/soundcloud_screen.dart';
import '../features/settings/ui/storage_screen.dart';
import '../features/settings/ui/system_screen.dart';
import '../features/settings/ui/swipes_screen.dart';
import '../features/settings/ui/yandex_screen.dart';
import '../features/settings/ui/ytmusic_screen.dart';
import '../shared/ui/cover_hero.dart';
import '../shared/ui/glass.dart';
import 'shell.dart';
import 'theme/tokens.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();

/// Навигаторы вкладок — в порядке веток: главная, библиотека, настройки.
///
/// Нужны тем, кто открывает страницу НЕ из дерева вкладки: пилюля источника
/// живёт в полноэкранном плеере, а он лежит в корневом навигаторе, и ближайший
/// `Navigator.of(context)` оттуда — корневой. Положи страницу артиста в него —
/// она накроет таб-бар и миниплеер, хотя из поиска та же страница открывается
/// под ними.
final List<GlobalKey<NavigatorState>> _branchKeys = [
  GlobalKey<NavigatorState>(),
  GlobalKey<NavigatorState>(),
  GlobalKey<NavigatorState>(),
];

/// Навигатор ТОЙ вкладки, что открыта сейчас. `null` — каркас ещё не собран.
NavigatorState? currentBranchNavigator() {
  final path = bloomRouter.state.uri.path;
  final key = path.startsWith('/library')
      ? _branchKeys[1]
      : path.startsWith('/settings')
      ? _branchKeys[2]
      : _branchKeys[0];
  return key.currentState;
}

/// Фон страницы маршрута.
///
/// Экраны веток рисуются без своей заливки — фон им даёт [Scaffold] каркаса.
/// Пока страница одна, это незаметно, но ВО ВРЕМЯ перехода видны обе: верхняя
/// без фона просвечивает, и сквозь плейлист читается список библиотеки.
/// Поэтому каждая страница красится сама.
///
/// Исключение — включённая картинка фона: тогда заливки нет вовсе, иначе фон
/// был бы намертво закрыт (см. `AppBackground`). Просвечивание при переходе в
/// этом случае и не мешает: под обеими страницами лежит одна и та же картинка.
class _Page extends ConsumerWidget {
  const _Page(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: ref.watch(backgroundOnProvider)
        ? Colors.transparent
        : context.bloom.bg,
    // Своя группа стекла на страницу: её плашки не накладываются друг на
    // друга, поэтому один снимок подложки годится им всем. Бары каркаса лежат
    // ПОВЕРХ страницы и потому в группу не входят — у них своя (`shell.dart`).
    child: GlassGroup(child: child),
  );
}

final GoRouter bloomRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  // Первый запуск уводит куда угодно на онбординг — то же, что оверлей поверх
  // всего на десктопе. Флаг голый, а не провайдер: `redirect` контейнера
  // Riverpod не видит, а ответ нужен ещё до сборки первого маршрута
  // (`main()` читает стор до первого кадра).
  redirect: (context, state) {
    if (!onboardingPending) return null;
    return state.matchedLocation == '/onboarding' ? null : '/onboarding';
  },
  routes: [
    // Своя страница, а не оверлей: иначе системное «назад» уходило бы мимо
    // мастера в навигатор под ним, а `PopScope` без маршрута-предка молчит.
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    StatefulShellRoute(
      builder: (context, state, shell) => BloomShell(shell: shell),
      navigatorContainerBuilder: (context, shell, children) =>
          BranchCrossfade(index: shell.currentIndex, children: children),
      branches: [
        StatefulShellBranch(
          navigatorKey: _branchKeys[0],
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const _Page(HomeScreen()),
              routes: [
                GoRoute(
                  path: 'search',
                  builder: (_, _) => const _Page(SearchScreen()),
                ),
                GoRoute(
                  path: 'profile',
                  // Растворение на месте: в шапку профиля летит аватар с
                  // кнопки главной, и сдвиг всей страницы спорил бы с ним
                  // (см. `detailPageTransition`).
                  pageBuilder: (_, state) => CustomTransitionPage<void>(
                    key: state.pageKey,
                    transitionsBuilder: detailPageTransition,
                    transitionDuration: kDetailTransition,
                    reverseTransitionDuration: kDetailTransition,
                    child: _Page(
                      ProfileScreen(
                        flight: state.extra is CoverFlight
                            ? state.extra! as CoverFlight
                            : null,
                      ),
                    ),
                  ),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      // Поверх каркаса: редактор — это модалка десктопа, и
                      // таб-бар с миниплеером под кнопкой «Сохранить» ей ни к
                      // чему.
                      parentNavigatorKey: _rootKey,
                      builder: (_, _) => const _Page(ProfileEditScreen()),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _branchKeys[1],
          routes: [
            GoRoute(
              path: '/library',
              builder: (_, _) => const _Page(LibraryScreen()),
              routes: [
                GoRoute(
                  path: 'list/:id',
                  // Растворение на месте вместо общего перехода со сдвигом:
                  // в шапку списка летит обложка плитки, и сдвиг всей страницы
                  // спорил бы с перелётом (см. `detailPageTransition`).
                  //
                  // `extra` — метка того самого перелёта. Приходит только с
                  // плитки; при открытии по ссылке или после перезапуска там
                  // пусто, и шапка просто проявляется.
                  pageBuilder: (_, state) => CustomTransitionPage<void>(
                    key: state.pageKey,
                    transitionsBuilder: detailPageTransition,
                    transitionDuration: kDetailTransition,
                    reverseTransitionDuration: kDetailTransition,
                    child: _Page(
                      TracklistScreen(
                        listId: state.pathParameters['id']!,
                        flight: state.extra is CoverFlight
                            ? state.extra! as CoverFlight
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _branchKeys[2],
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const _Page(SettingsScreen()),
              routes: [
                GoRoute(
                  path: 'appearance',
                  builder: (_, _) => const _Page(AppearanceScreen()),
                ),
                GoRoute(
                  path: 'soundcloud',
                  builder: (_, _) => const _Page(SoundCloudSettingsScreen()),
                ),
                GoRoute(
                  path: 'yandex',
                  builder: (_, _) => const _Page(YandexSettingsScreen()),
                ),
                GoRoute(
                  path: 'ytmusic',
                  builder: (_, _) => const _Page(YtmusicSettingsScreen()),
                ),
                GoRoute(
                  path: 'lastfm',
                  builder: (_, _) => const _Page(LastfmSettingsScreen()),
                ),
                GoRoute(
                  path: 'system',
                  builder: (_, _) => const _Page(SystemSettingsScreen()),
                  routes: [
                    GoRoute(
                      path: 'logs',
                      builder: (_, _) => const _Page(LogsScreen()),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'audio',
                  builder: (_, _) => const _Page(AudioSettingsScreen()),
                ),
                GoRoute(
                  path: 'storage',
                  builder: (_, _) => const _Page(StorageSettingsScreen()),
                ),
                GoRoute(
                  path: 'swipes',
                  builder: (_, _) => const _Page(SwipesScreen()),
                ),
                GoRoute(
                  path: 'player',
                  builder: (_, _) => const _Page(PlayerSettingsScreen()),
                ),
                GoRoute(
                  path: 'media',
                  builder: (_, _) => const _Page(MediaLibraryScreen()),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (_, state) => _Page(
                        MediaItemScreen(id: state.pathParameters['id'] ?? ''),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'presets',
                  builder: (_, _) => const _Page(PresetsScreen()),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
