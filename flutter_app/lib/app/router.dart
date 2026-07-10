import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/state.dart';
import '../ui/motion.dart';
import 'screens/app_shell.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/offline_screen.dart';
import 'screens/servarr_screen.dart';
import 'screens/servarr_queue_screen.dart';
import 'screens/party_screen.dart';

/// The root Navigator's key. Exposed because the unified title bar in
/// `app.dart` lives ABOVE the router (it wraps `MaterialApp.router`'s Navigator
/// in the window frame), so its command-palette + sign-out actions have no
/// Navigator ancestor of their own. Routing/dialogs from there resolve a
/// below-router context via `rootNavigatorKey.currentContext`.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

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
    navigatorKey: rootNavigatorKey,
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
        return (redirectTo != null && redirectTo.isNotEmpty)
            ? redirectTo
            : Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),

      // Immersive party screen — full-window, outside the nav shell. As a
      // top-level PUSH route (not a shelled tab) it gets the ~180ms
      // fade-through from motion.dart; the deliberate NoTransitionPage
      // anti-flicker rule applies only to the shelled tabs below.
      GoRoute(
        path: '${Routes.party}/:id',
        pageBuilder: (_, state) => fadeThroughPage(
          key: state.pageKey,
          child: PartyScreen(partyId: state.pathParameters['id']),
        ),
      ),

      // Detail is full-window too (leads into the player) — same fade-through.
      GoRoute(
        path: '${Routes.detail}/:id',
        pageBuilder: (_, state) => fadeThroughPage(
          key: state.pageKey,
          child: DetailScreen(itemId: state.pathParameters['id']!),
        ),
      ),

      // The shelled destinations.
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          // Shelled destinations use NoTransitionPage: switching a ShellRoute's
          // child with the default animated page cross-fades the old tab over
          // the new one on every switch (a visible flicker on desktop). An
          // instant swap matches the cinematic-minimal "content is the
          // interface" rule — no cross-fade of stale content. `state.pageKey`
          // gives each destination a distinct page identity so the Navigator
          // replaces rather than reuses the previous subtree.
          GoRoute(
            path: Routes.home,
            pageBuilder: (_, state) =>
                NoTransitionPage(key: state.pageKey, child: const HomeScreen()),
          ),
          GoRoute(
            path: Routes.browse,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const BrowseScreen(),
            ),
          ),
          GoRoute(
            path: Routes.party,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const PartyScreen(),
            ),
          ),
          GoRoute(
            path: Routes.downloads,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DownloadsScreen(),
            ),
          ),
          GoRoute(
            path: Routes.offline,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const OfflineScreen(),
            ),
          ),
          GoRoute(
            path: Routes.servarr,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const ServarrScreen(),
            ),
          ),
          GoRoute(
            path: '${Routes.servarr}/queue',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const ServarrQueueScreen(),
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('No route for ${state.uri}'))),
  );
}
