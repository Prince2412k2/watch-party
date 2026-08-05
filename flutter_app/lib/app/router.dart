import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/show_source.dart';
import '../state/state.dart';
import '../ui/ui.dart';
import '../ui/motion.dart';
import 'screens/app_shell.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/download_detail_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/offline_screen.dart';
import 'screens/servarr_screen.dart';
import 'screens/servarr_queue_screen.dart';
import 'screens/party_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/show_stage.dart';

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

  /// The profile editor — reachable from the account menu on any screen.
  static const profile = '/profile';

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
      GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),

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
      // fade-through. Movie + episode detail keep [DetailScreen]; a series
      // renders the unified [ShowStage] instead (US-3/FR-012) — see
      // [_LibraryDetailRoute].
      GoRoute(
        path: '${Routes.detail}/:id',
        pageBuilder: (_, state) => fadeThroughPage(
          key: state.pageKey,
          child: _LibraryDetailRoute(itemId: state.pathParameters['id']!),
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
                    ? const BrowseScreen(type: BrowseTypeFilter.movie)
                    : const HomeScreen(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.series,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const BrowseScreen(type: BrowseTypeFilter.series),
            ),
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

/// `/detail/:id` dispatch (US-3/FR-012, "one show screen, two purposes"): an
/// authenticated SERIES renders the unified [ShowStage] in place of the
/// classic season-selector stage; a MOVIE, an EPISODE, a guest, or an
/// item whose type hasn't resolved yet all fall through to the existing
/// [DetailScreen] unchanged — it already owns the guest offline-browse path,
/// the loading skeleton, and the error state, so none of that is duplicated
/// here.
class _LibraryDetailRoute extends ConsumerWidget {
  const _LibraryDetailRoute({required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    final isSeries =
        isAuthenticated &&
        ref.watch(itemDetailProvider(itemId)).valueOrNull?.type == 'Series';
    if (!isSeries) return DetailScreen(itemId: itemId);

    final wp = context.wp;
    return Scaffold(
      backgroundColor: wp.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: ShowStage(
              show: ShowRef(kind: ShowSourceKind.library, id: itemId),
              onBack: () =>
                  context.canPop() ? context.pop() : context.go(Routes.movies),
              // Same launcher the detail screen uses, so playback is
              // party-aware and pushed in place — back lands on the show
              // stage instead of a route default.
              onWatch: (episode) {
                final jellyfinId = episode.jellyfinId;
                if (jellyfinId == null) return;
                startPlayback(context, ref, itemId: jellyfinId);
              },
            ),
          ),
          const Positioned(right: 22, bottom: 18, child: PopcornControl()),
        ],
      ),
    );
  }
}
