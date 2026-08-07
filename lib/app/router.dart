/// Навигация: три таба через [StatefulShellRoute.indexedStack] — у каждого
/// свой стек, состояние вкладки переживает переключение.
///
/// Вложенные страницы (поиск, списки библиотеки, разделы настроек) живут
/// ВНУТРИ своей ветки: таб-бар и миниплеер остаются на месте.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/ui/home_screen.dart';
import '../features/library/ui/library_screen.dart';
import '../features/library/ui/tracklist_screen.dart';
import '../features/search/ui/search_screen.dart';
import '../features/settings/ui/appearance_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/settings/ui/soundcloud_screen.dart';
import 'shell.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();

final GoRouter bloomRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => BloomShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const HomeScreen(),
              routes: [
                GoRoute(
                  path: 'search',
                  builder: (_, _) => const SearchScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (_, _) => const LibraryScreen(),
              routes: [
                GoRoute(
                  path: 'list/:id',
                  builder: (_, state) =>
                      TracklistScreen(listId: state.pathParameters['id']!),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'appearance',
                  builder: (_, _) => const AppearanceScreen(),
                ),
                GoRoute(
                  path: 'soundcloud',
                  builder: (_, _) => const SoundCloudSettingsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
