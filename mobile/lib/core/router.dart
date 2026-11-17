import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/compare/compare_screen.dart';
import '../features/home/home_screen.dart';
import '../features/not_found_screen.dart';
import '../features/players/players_screen.dart';
import '../features/players/profile_screen.dart';
import 'theme.dart';

/// App router: three top-level tabs (Archive, Players, Compare), each with its
/// own navigation stack, so a player profile pushed from Players keeps its
/// place when the user hops to Compare and back. A friendly not-found page
/// handles unknown or malformed routes (e.g. a stale deep link).
final appRouter = GoRouter(
  initialLocation: '/',
  errorBuilder: (context, state) =>
      NotFoundScreen(location: state.uri.toString()),
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/players',
              name: 'players',
              builder: (context, state) => const PlayersScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  name: 'player',
                  builder: (context, state) {
                    final id =
                        int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                    return ProfileScreen(
                      playerId: id,
                      initialSeason: state.uri.queryParameters['season'],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/compare',
              name: 'compare',
              builder: (context, state) => CompareScreen(
                initialAId: int.tryParse(state.uri.queryParameters['a'] ?? ''),
                initialBId: int.tryParse(state.uri.queryParameters['b'] ?? ''),
                initialASeason: state.uri.queryParameters['as'],
                initialBSeason: state.uri.queryParameters['bs'],
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Hosts the tab bar. Tapping the active tab pops it back to its root, as on
/// every iOS app.
class AppShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: shell.currentIndex,
        onTap: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        backgroundColor: Hue.ground,
        activeColor: Hue.volt,
        inactiveColor: Hue.textLo,
        iconSize: 24,
        height: 54,
        border: const Border(top: BorderSide(color: Hue.hairline)),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.archivebox),
            activeIcon: Icon(CupertinoIcons.archivebox_fill),
            label: 'Archive',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_2),
            activeIcon: Icon(CupertinoIcons.person_2_fill),
            label: 'Players',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.arrow_right_arrow_left),
            label: 'Compare',
          ),
        ],
      ),
    );
  }
}
