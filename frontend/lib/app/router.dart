import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/auth_screen.dart';
import '../features/explore/presentation/explore_screen.dart';
import '../features/feed/presentation/feed_screen.dart';
import '../features/layers/presentation/layers_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/reports/presentation/tag_submission_screen.dart';
import '../features/trends/presentation/trends_screen.dart';
import '../shared/providers/app_providers.dart';
import 'widgets/main_shell.dart';

bool _isShellLocation(String loc) {
  const shell = {'/explore', '/feed', '/add-tag', '/layers', '/profile'};
  return shell.contains(loc) || loc.startsWith('/trends');
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/auth',
  refreshListenable: routerRefreshListenable,
  redirect: (BuildContext context, GoRouterState state) {
    final container = ProviderScope.containerOf(context);
    if (!container.read(authBootstrapCompleteProvider)) {
      return null;
    }
    final token = container.read(authTokenProvider);
    final loc = state.matchedLocation;
    final loggedIn = token != null && token.isNotEmpty;
    final onAuth = loc == '/auth';
    if (!loggedIn && _isShellLocation(loc)) {
      return '/auth';
    }
    if (loggedIn && onAuth) {
      return '/explore';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', redirect: (context, state) => '/auth'),
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/explore',
          builder: (context, state) => const ExploreScreen(),
        ),
        GoRoute(path: '/feed', builder: (context, state) => const FeedScreen()),
        GoRoute(
          path: '/add-tag',
          builder: (context, state) => const TagSubmissionScreen(),
        ),
        GoRoute(
          path: '/layers',
          builder: (context, state) => const LayersScreen(),
        ),
        GoRoute(
          path: '/trends',
          builder: (context, state) => TrendsScreen(
            zoneId: state.uri.queryParameters['zoneId'],
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    ),
  ],
);
