import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/state.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/bottom_nav.dart';
import '../../ui/widgets/profile_menu.dart';
import '../router.dart';
import '../shortcuts.dart';

/// The primary navigation destinations, in tab order — the four redesigned web
/// tabs (`WebShell.tsx` `tabs`). Single source of truth reused by the bottom
/// nav, the keyboard layer (`shortcuts.dart`, number keys), and the command
/// palette's quick-nav. Find/Acquire folds into Discover; Offline into
/// Downloads, so neither is a tab.
///
/// This is the ADMIN nav. Discover exists only to put a title on the server's
/// disk, which is the admin's alone — see [kMemberShellDestinations].
const List<NavDestination> kShellDestinations = [
  NavDestination(icon: Icons.movie_outlined, label: 'Movies', route: '/movies'),
  NavDestination(icon: Icons.tv_outlined, label: 'Shows', route: '/series'),
  NavDestination(
    icon: Icons.explore_outlined,
    label: 'Discover',
    route: '/discover',
  ),
  NavDestination(
    icon: Icons.download_outlined,
    label: 'Downloads',
    route: '/downloads',
  ),
];

/// The nav for a signed-in member who is not a Jellyfin administrator: the same
/// tabs minus Discover. Everything left is about watching what is already here
/// — the library, and what the server is currently pulling down.
///
/// Discover is not disabled or greyed, it is absent: every action on that
/// surface starts a download, so a member has nothing to do there. The server
/// answers 403 to its feeds regardless (`app/server/servarr/index.js`), and the
/// router refuses the route, so this is presentation, not the gate.
final List<NavDestination> kMemberShellDestinations = List.unmodifiable([
  for (final d in kShellDestinations)
    if (d.route != '/discover') d,
]);

/// The destinations for a given account, by admin-ness.
List<NavDestination> shellDestinationsFor({required bool isAdmin}) =>
    isAdmin ? kShellDestinations : kMemberShellDestinations;

/// The nav (+ keyboard layer + command palette) shown to a logged-out guest:
/// just enough to browse and play what's already downloaded (PLAN guest-browse).
/// "Movies" renders the login page inline (see [HomeScreen]); "Downloaded" is
/// the existing `/offline` library.
const List<NavDestination> kGuestShellDestinations = [
  NavDestination(icon: Icons.movie_outlined, label: 'Movies', route: '/movies'),
  NavDestination(
    icon: Icons.download_done_outlined,
    label: 'Downloaded',
    route: '/offline',
  ),
];

/// The section name for a given router [location] — retained for callers/tests
/// that map a path to its destination label. Off the shell it falls back to the
/// app name. Pure + dependency-free.
String shellSectionTitle(String location) {
  for (final d in kShellDestinations) {
    if (location.startsWith(d.route)) return d.label;
  }
  return 'Watchparty';
}

/// The persistent, edge-to-edge shell that wraps the primary destinations
/// (`.web-app`/`.web-stage`, styles.css). No top bar, no left rail, no outer
/// frame: a full-bleed [AmbientWash] backdrop under a translucent stage scrim,
/// the routed content, then floating chrome — the bottom-centered [BottomNav],
/// the top-right [ProfileMenu], and the bottom-right [PopcornControl].
///
/// While a guest is watching a host's shared session, the content layer is
/// pointer-locked and labelled "Shared host view" (mirrors `WebShell.tsx:264`);
/// the floating chrome stays interactive.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmCatalog(ref.read(catalogNamespaceProvider));
    });
  }

  /// Pull the browse catalog down for a launch that did not land on it.
  ///
  /// Only worth anything when the app came up somewhere else — a deep link to
  /// Downloads, a boot-time party resume straight into the player. `/movies`
  /// and `/series` fetch this themselves the moment they build, so warming it
  /// under them would be a second request for a payload already in flight.
  ///
  /// Deferred past the first frame, and best-effort inside the prefetcher, so
  /// it cannot delay or fail the paint it runs behind.
  void _warmCatalog(String? namespace) {
    if (!mounted || namespace == null) return;
    if (widget.location.startsWith(Routes.movies) ||
        widget.location.startsWith(Routes.series)) {
      return;
    }
    ref.read(catalogPrefetcherProvider).warmBrowse(namespace);
  }

  String _currentOf(List<NavDestination> destinations) {
    for (final d in destinations) {
      if (widget.location.startsWith(d.route)) return d.route;
    }
    return destinations.first.route;
  }

  @override
  Widget build(BuildContext context) {
    // Signing in is the other "launch": the shell is already up, so the
    // post-frame warm above has been and gone by the time a namespace exists.
    ref.listen<String?>(
      catalogNamespaceProvider,
      (_, namespace) => _warmCatalog(namespace),
    );
    final wp = context.wp;
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    final destinations = isAuthenticated
        ? shellDestinationsFor(isAdmin: ref.watch(isAdminProvider))
        : kGuestShellDestinations;

    // `/movies` is where a guest meets the login form ([HomeScreen] renders it
    // in place rather than bouncing to `/login`), so on that one location the
    // shell's own top-right control has to stand down.
    final showsLoginForm =
        !isAuthenticated && widget.location.startsWith(Routes.movies);

    return Scaffold(
      body: AppShortcuts(
        child: Stack(
          children: [
            const Positioned.fill(child: AmbientWash()),
            Positioned.fill(child: ColoredBox(color: wp.stage)),
            // Never gated on party role. A guest used to have this whole shell
            // wrapped in IgnorePointer so their library followed the host's —
            // which meant being in a room made your own app unusable. Rooms
            // share playback, chat and A/V; they never take your app away.
            Positioned.fill(child: widget.child),
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Center(
                child: BottomNav(
                  destinations: destinations,
                  currentRoute: _currentOf(destinations),
                  onSelect: (route) => context.go(route),
                ),
              ),
            ),
            // Nothing in this corner on the inline login page: `/movies`
            // renders the login form itself for a guest, and that page already
            // owns the corner with its "set server" chip. The two were landing
            // on top of each other, the round button sitting over the host
            // name. It is also a Login button on the login page, which has
            // nowhere to send anyone.
            //
            // A guest anywhere else — the downloaded library, a title they can
            // play offline — still gets it, because there it is the only way in.
            if (!showsLoginForm)
              Positioned(
                top: 20,
                right: 28,
                child: isAuthenticated
                    ? const ProfileMenu()
                    : const _LoginButton(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Top-right chrome for a logged-out guest: no session to sign out of, so this
/// just routes to `/login` (PLAN guest-browse §D).
class _LoginButton extends StatelessWidget {
  const _LoginButton();

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: 'Login',
      child: Material(
        color: wp.bg,
        shape: CircleBorder(side: BorderSide(color: wp.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.go('/login'),
          child: SizedBox.square(
            dimension: 40,
            child: Icon(Icons.login, size: 20, color: wp.text),
          ),
        ),
      ),
    );
  }
}
