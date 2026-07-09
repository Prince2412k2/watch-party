import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/app_shell.dart';
import 'screens/home_screen.dart';
import 'screens/placeholder_screens.dart';

/// FROZEN CONTRACT (PLAN §3.7). Route names + go_router config. The primary
/// destinations live inside a persistent [AppShell]; login and the immersive
/// party screen are top-level. E2 adds auth redirects/guards against
/// `authProvider`; the route names/paths here are the seam epics build on.
abstract final class Routes {
  static const login = '/login';
  static const home = '/home';
  static const browse = '/browse';
  static const detail = '/detail'; // /detail/:id
  static const party = '/party'; // /party or /party/:id
  static const downloads = '/downloads';
  static const offline = '/offline';
  static const servarr = '/servarr';
}

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),

      // Immersive party screen — full-window, outside the nav shell.
      GoRoute(
        path: '${Routes.party}/:id',
        builder: (_, state) => PartyScreen(partyId: state.pathParameters['id']),
      ),

      // Detail is full-window too (leads into the player).
      GoRoute(
        path: '${Routes.detail}/:id',
        builder: (_, state) => DetailScreen(itemId: state.pathParameters['id']!),
      ),

      // The shelled destinations.
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          GoRoute(path: Routes.browse, builder: (_, _) => const BrowseScreen()),
          GoRoute(path: Routes.party, builder: (_, _) => const PartyScreen()),
          GoRoute(path: Routes.downloads, builder: (_, _) => const DownloadsScreen()),
          GoRoute(path: Routes.offline, builder: (_, _) => const OfflineScreen()),
          GoRoute(path: Routes.servarr, builder: (_, _) => const ServarrScreen()),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('No route for ${state.uri}')),
    ),
  );
}
