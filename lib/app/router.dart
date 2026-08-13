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
import 'package:go_router/go_router.dart';

import '../features/home/ui/home_screen.dart';
import '../features/library/ui/library_screen.dart';
import '../features/library/ui/tracklist_screen.dart';
import '../features/profile/ui/profile_edit_screen.dart';
import '../features/profile/ui/profile_screen.dart';
import '../features/search/ui/search_screen.dart';
import '../features/settings/ui/appearance_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/settings/ui/soundcloud_screen.dart';
import '../features/settings/ui/storage_screen.dart';
import '../features/settings/ui/yandex_screen.dart';
import '../features/settings/ui/ytmusic_screen.dart';
import '../shared/ui/cover_hero.dart';
import 'shell.dart';
import 'theme/tokens.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();

/// Фон страницы маршрута.
///
/// Экраны веток рисуются без своей заливки — фон им даёт [Scaffold] каркаса.
/// Пока страница одна, это незаметно, но ВО ВРЕМЯ перехода видны обе: верхняя
/// без фона просвечивает, и сквозь плейлист читается список библиотеки.
/// Поэтому каждая страница красится сама.
class _Page extends StatelessWidget {
  const _Page(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.bloom.bg, child: child);
}

final GoRouter bloomRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute(
      builder: (context, state, shell) => BloomShell(shell: shell),
      navigatorContainerBuilder: (context, shell, children) =>
          BranchCrossfade(index: shell.currentIndex, children: children),
      branches: [
        StatefulShellBranch(
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
                  path: 'storage',
                  builder: (_, _) => const _Page(StorageSettingsScreen()),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
