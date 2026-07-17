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

/// The root Navigator's key. Exposed because some app-wide affordances resolve a
/// below-router context via `rootNavigatorKey.currentContext` (e.g. the party
/// return/leave actions that survive full route pushes).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

/// Route table. The primary destinations mirror the redesigned web IA — four
/// bottom tabs **Movies · Shows · Discover · Downloads** — inside a persistent
/// [AppShell]; login, the immersive party screen, and title detail are
/// top-level. Offline folds into Downloads and Find/Acquire folds into Discover,
/// so their old top-level paths (`/home`, `/browse`, `/servarr`) are kept only
/// as redirect aliases for in-flight links and not-yet-rebuilt screens.
abstract final class Routes {
  static const login = '/login';

  /// Bottom-nav tabs.
  static const movies = '/movies';
  static const series = '/series';
  static const discover = '/discover';
  static const downloads = '/downloads';

  /// Secondary shelled routes (reachable but not tabs).
  static const offline = '/offline';
  static const servarrQueue = '/servarr/queue';

  /// `/discover/:id` — a Discover (servarr) title detail deep-link.
  static const discoverDetail = '/discover';

  /// `/downloads/:id` — a download detail deep-link.
  static const downloadsDetail = '/downloads';

  /// Top-level immersive routes.
  static const detail = '/detail'; // /detail/:id
  static const party = '/party'; // /party/:id

  /// Deprecated 6-destination paths, aliased in [buildRouter]'s redirect.
  static const home = '/home';
  static const browse = '/browse';
  static const servarr = '/servarr';
}

/// Old-IA → new-IA path aliases. Applied before auth logic so links (and
/// screens not yet rebuilt to the new paths) keep resolving.
const Map<String, String> _pathAliases = {
  Routes.home: Routes.movies,
  Routes.browse: Routes.series,
  Routes.servarr: Routes.discover,
};

/// Bridges Riverpod's [authProvider] to go_router's `refreshListenable`, so a
/// login/logout re-runs [redirect] without a manual `context.go`.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(WidgetRef ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

/// Routes a logged-out guest may stay on: `/movies` (renders the login page
/// inline via [HomeScreen], PLAN guest-browse), `/offline` (the downloaded-titles
/// library), `/detail/:id` (offline playback of a downloaded title), and
/// `/login` itself. Anything else needs a session.
bool _guestAllowed(String location) =>
    location == Routes.movies ||
    location == Routes.login ||
    location == Routes.offline ||
    location.startsWith('${Routes.detail}/');

/// E2/guest-browse: a logged-out user may browse `/movies` (which renders the
/// login page inline) and the offline library/detail without signing in; every
/// other route bounces them to `/movies`. An authenticated visit to `/login`
/// → the route they were headed to (or Movies). Waits on `auth.initialized`
/// (the boot-time `/me` session-restore probe) before redirecting.
GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.movies,
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final loc = state.uri.path;
      final alias = _pathAliases[loc];
      if (alias != null) return alias;

      final auth = ref.read(authProvider);
      if (!auth.initialized) return null;

      final loggingIn = loc == Routes.login;
      if (!auth.isAuthenticated) {
        return _guestAllowed(loc) ? null : Routes.movies;
      }
      if (loggingIn) {
        final redirectTo = state.uri.queryParameters['from'];
        return (redirectTo != null && redirectTo.isNotEmpty)
            ? redirectTo
            : Routes.movies;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),

      // Immersive party screen — full-window, outside the nav shell. A
      // top-level PUSH route gets the ~180ms fade-through from motion.dart.
      GoRoute(
        path: '${Routes.party}/:id',
        pageBuilder: (_, state) => fadeThroughPage(
          key: state.pageKey,
          child: PartyScreen(partyId: state.pathParameters['id']),
        ),
      ),

      // Title detail is full-window too (leads into the player) — same
      // fade-through. Movie + show detail (W2a rebuild it in place).
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
          // Shelled destinations use NoTransitionPage: an animated ShellRoute
          // child swap cross-fades stale content on every tab switch (a visible
          // desktop flicker). `state.pageKey` gives each destination a distinct
          // page identity so the Navigator replaces rather than reuses it.
          GoRoute(
            path: Routes.movies,
            pageBuilder: (_, state) =>
                NoTransitionPage(key: state.pageKey, child: const HomeScreen()),
          ),
          GoRoute(
            path: Routes.series,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const BrowseScreen(),
            ),
          ),
          GoRoute(
            path: Routes.discover,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const ServarrScreen(),
            ),
          ),
          // Discover (servarr) title detail. Points at the existing Discover
          // screen for now; W2d rebuilds the detail surface in place (as an
          // overlay/deep-link keyed by :id).
          GoRoute(
            path: '${Routes.discover}/:id',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const ServarrScreen(),
            ),
          ),
          GoRoute(
            path: Routes.downloads,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DownloadsScreen(),
            ),
          ),
          // Download detail. Points at the existing Downloads screen for now;
          // W2d rebuilds the detail overlay in place (deep-link keyed by :id).
          GoRoute(
            path: '${Routes.downloads}/:id',
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DownloadsScreen(),
            ),
          ),
          // Offline library — folded under Downloads in the nav, still routable
          // for guest browse and deep links.
          GoRoute(
            path: Routes.offline,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const OfflineScreen(),
            ),
          ),
          GoRoute(
            path: Routes.servarrQueue,
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
