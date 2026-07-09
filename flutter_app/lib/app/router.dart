import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/state.dart';
import 'screens/app_shell.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/placeholder_screens.dart';

/// FROZEN CONTRACT (PLAN §3.7). Route names + go_router config. The primary
/// destinations live inside a persistent [AppShell]; login and the immersive
/// party screen are top-level. E2 adds the auth redirect/guard below; route
/// names/paths are unchanged.
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

/// Bridges Riverpod's [authProvider] to go_router's `refreshListenable`, so a
/// login/logout re-runs [redirect] without a manual `context.go`.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(WidgetRef ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

/// E2: unauthenticated → `/login`; authenticated visiting `/login` → the
/// route they were headed to (or home). Waits on `auth.initialized` (the
/// boot-time `/me` session-restore probe) before redirecting away from
/// whatever route the app opened to, so a valid persisted session isn't
/// bounced through the login screen.
GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (!auth.initialized) return null;

      final loggingIn = state.matchedLocation == Routes.login;
      if (!auth.isAuthenticated) {
        return loggingIn ? null : Routes.login;
      }
      if (loggingIn) {
        final redirectTo = state.uri.queryParameters['from'];
        return (redirectTo != null && redirectTo.isNotEmpty) ? redirectTo : Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),

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
