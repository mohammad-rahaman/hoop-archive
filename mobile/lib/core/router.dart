import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';

/// App router. Routes for Players, Profile and Compare are added in their
/// respective phases; the structure is in place from the start.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
  ],
);
