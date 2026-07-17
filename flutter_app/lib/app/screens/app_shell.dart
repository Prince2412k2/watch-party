import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/state.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/bottom_nav.dart';
import '../../ui/widgets/popcorn_control.dart';
import '../../ui/widgets/profile_menu.dart';
import '../shortcuts.dart';

/// The primary navigation destinations, in tab order — the four redesigned web
/// tabs (`WebShell.tsx` `tabs`). Single source of truth reused by the bottom
/// nav, the keyboard layer (`shortcuts.dart`, number keys), and the command
/// palette's quick-nav. Find/Acquire folds into Discover; Offline into
/// Downloads, so neither is a tab.
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
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  String _currentOf(List<NavDestination> destinations) {
    for (final d in destinations) {
      if (location.startsWith(d.route)) return d.route;
    }
    return destinations.first.route;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    final party = ref.watch(partyProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final sharedHostView =
        party != null && (currentUserId == null || party.hostId != currentUserId);

    final destinations = isAuthenticated
        ? kShellDestinations
        : kGuestShellDestinations;

    return Scaffold(
      body: AppShortcuts(
        child: Stack(
          children: [
            const Positioned.fill(child: AmbientWash()),
            Positioned.fill(child: ColoredBox(color: wp.stage)),
            Positioned.fill(
              child: Semantics(
                container: sharedHostView,
                label: sharedHostView ? 'Shared host view' : null,
                child: IgnorePointer(ignoring: sharedHostView, child: child),
              ),
            ),
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
            Positioned(
              top: 20,
              right: 28,
              child: isAuthenticated ? const ProfileMenu() : const _LoginButton(),
            ),
            if (isAuthenticated)
              const Positioned(right: 22, bottom: 10, child: PopcornControl()),
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
