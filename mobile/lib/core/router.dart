import 'package:go_router/go_router.dart';

import '../features/compare/compare_screen.dart';
import '../features/home/home_screen.dart';
import '../features/not_found_screen.dart';
import '../features/players/players_screen.dart';
import '../features/players/profile_screen.dart';

/// App router. A friendly not-found page handles unknown or malformed routes
/// (e.g. a stale deep link) instead of GoRouter's default error page.
final appRouter = GoRouter(
  initialLocation: '/',
  errorBuilder: (context, state) =>
      NotFoundScreen(location: state.uri.toString()),
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/compare',
      name: 'compare',
      builder: (context, state) => CompareScreen(
        initialAId: int.tryParse(state.uri.queryParameters['a'] ?? ''),
        initialBId: int.tryParse(state.uri.queryParameters['b'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/players',
      name: 'players',
      builder: (context, state) => const PlayersScreen(),
      routes: [
        GoRoute(
          path: ':id',
          name: 'player',
          builder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return ProfileScreen(playerId: id);
          },
        ),
      ],
    ),
  ],
);
