import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../state/state.dart';
import '../ui/analog_tokens.dart';
import '../ui/ui.dart';
import 'screens/app_shell.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/movies_stage.dart';
import 'screens/shows_stage.dart';
import 'screens/detail_screen.dart';
import 'screens/download_detail_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/offline_screen.dart';
import 'screens/servarr_screen.dart';
import 'screens/servarr_queue_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';

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

  /// The avatar editor. A step in from [settings] now, behind the pencil on
  /// the face, rather than what the account menu opens directly.
  static const profile = '/profile';

  /// Settings — what the account menu's tune button opens.
  static const settings = '/settings';

  /// Top-level immersive routes.
  static const detail = '/detail'; // /detail/:id

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

/// Routes only a Jellyfin administrator may stand on. Discover and the *arr
/// queue are acquisition surfaces — every action on them puts something on (or
/// takes something off) the server's disk. A member who reaches one anyway (a
/// deep link, a restored location, a stale bookmark) is sent to Movies rather
/// than shown a page whose every request answers 403.
bool isAdminOnlyRoute(String location) =>
    location.startsWith(Routes.discover) ||
    location.startsWith(Routes.servarrQueue) ||
    // `/downloads` itself is everyone's — it is this device's download list.
    // `/downloads/<hash>` is a SERVER torrent, with pause/resume/delete on it.
    location.startsWith('${Routes.downloads}/');

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
      if (isAdminOnlyRoute(loc) && !(auth.user?.isAdmin ?? false)) {
        return Routes.movies;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),
      GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
      // The same fade-through every other full-window surface arrives on, so
      // opening settings from a stage reads like the rest of the app.
      GoRoute(
        path: Routes.settings,
        pageBuilder: (_, state) => fadeThroughPage(
          key: state.pageKey,
          child: const SettingsScreen(),
        ),
      ),

      // Title detail is full-window too (leads into the player) — same
      // fade-through. Every library title, of every type, renders
      // [DetailScreen] → `DetailStage`.
      GoRoute(
        path: '${Routes.detail}/:id',
        pageBuilder: (_, state) => fadeThroughPage(
          key: state.pageKey,
          // Long enough for the poster to arc across, carry past the corner
          // and come back. The rest of the page is staged against the same
          // clock, so it assembles while the poster is still travelling.
          duration: AnalogMotion.heroFlightMs,
          // Back to the library is much quicker: the poster is going home, not
          // being introduced.
          reverseDuration: AnalogMotion.heroReturnMs,
          child: DetailScreen(
            itemId: state.pathParameters['id']!,
            // Whatever the opening surface handed over, if anything. A
            // deep link carries no extra and simply waits for the fetch.
            seed: state.extra is LibraryItem
                ? state.extra! as LibraryItem
                : null,
          ),
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
            // The child depends on auth, so it is chosen inside a Consumer that
            // WATCHES it. A plain `ref.read` here picked the child once and never
            // again: this page's key is stable for the location, so signing in
            // did not rebuild it and the login form stayed on screen even though
            // the session was live — visible as "Sign in does nothing, but
            // restarting the app lands me logged in".
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: Consumer(
                builder: (_, ref, _) =>
                    ref.watch(authProvider.select((s) => s.isAuthenticated))
                    ? const MoviesStage()
                    : const HomeScreen(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.series,
            pageBuilder: (_, state) =>
                NoTransitionPage(key: state.pageKey, child: const ShowsStage()),
          ),
          GoRoute(
            path: Routes.discover,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const ServarrScreen(),
            ),
          ),
          // NOTE: there is deliberately no `/discover/:id`. It existed and
          // rendered a bare [ServarrScreen], discarding the id — a deep link
          // to a title silently landed on the Discover rails instead. Honouring
          // it needs a lookup-by-id the servarr client does not have (the
          // detail surface is built from a [ServarrTitle] out of a discover or
          // search response), so the route is gone rather than lying. It comes
          // back with W2d's in-place detail surface.
          GoRoute(
            path: Routes.downloads,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DownloadsScreen(),
            ),
          ),
          // Download detail, rendered for the hash that was asked for. Its own
          // close action, because a deep link straight here has nothing
          // underneath it to pop back to.
          GoRoute(
            path: '${Routes.downloads}/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: DownloadDetailScreen(
                hash: state.pathParameters['id']!,
                onClose: () => context.canPop()
                    ? context.pop()
                    : context.go(Routes.downloads),
              ),
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

// A library SERIES used to be intercepted here and rendered as [ShowStage] —
// the Sonarr-shaped acquisition surface, which is also what Discover mounts.
// That interception is gone, and the reason is the whole point of this change:
//
//   "Selected episode should always be first. It should follow the same rules
//    the list of movies follows."
//
// The rule is the browse stage's — a fixed cursor with the row travelling
// under it, the scale falloff, the trail dimming, the settle. `DetailStage`
// now runs it, over the same `AnalogRail` the Movies stage uses, and it is the
// surface already held to `title_layout.dart` so the copy lands in the same
// rectangle on both sides of the transition. `ShowStage` restated all of those
// numbers as literals and drew its episodes as a plain `ListView` whose cursor
// moved instead of whose row did — the exact behaviour being replaced. Leaving
// the interception in place would have meant building the rail somewhere no
// user could reach it.
//
// [ShowStage] itself stays, mounted from Discover
// (`servarr_detail_screen.dart`), which is what it was built for: a show that
// is not in the library yet and has nothing to play.
//
// KNOWN TRADE-OFF: the per-season / per-episode / whole-series Sonarr download
// affordances lived on `ShowStage` and are therefore no longer on a library
// show's page. They remain reachable through Discover. Restoring them here
// means porting those actions onto `DetailStage`, not reinstating this
// interception.
