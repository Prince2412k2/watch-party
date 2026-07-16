import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/state.dart';
import '../../ui/ui.dart';
import '../shortcuts.dart';

/// The primary navigation destinations, in tab order. This is the single
/// source of truth reused by [AppShell]'s rail, the app-wide keyboard layer
/// (`shortcuts.dart`, keys 1–6), the command palette's quick-nav, and the
/// unified title bar's section-title lookup (`shellSectionTitle`).
const List<NavDestination> kShellDestinations = [
  NavDestination(icon: Icons.home_outlined, label: 'Home', route: '/home'),
  NavDestination(
    icon: Icons.explore_outlined,
    label: 'Browse',
    route: '/browse',
  ),
  NavDestination(icon: Icons.groups_outlined, label: 'Party', route: '/party'),
  NavDestination(
    icon: Icons.download_outlined,
    label: 'Downloads',
    route: '/downloads',
  ),
  NavDestination(
    icon: Icons.wifi_off_outlined,
    label: 'Offline',
    route: '/offline',
  ),
  NavDestination(
    icon: Icons.cloud_download_outlined,
    label: 'Find',
    route: '/servarr',
  ),
];

/// The nav rail (+ keyboard layer + command palette) shown to a logged-out
/// guest: just enough to browse and play what's already downloaded (PLAN
/// guest-browse). "Home" renders the login page inline (see [HomeScreen]);
/// "Downloaded" is the existing `/offline` library, relabeled here since a
/// guest has no server-backed library to distinguish it from.
const List<NavDestination> kGuestShellDestinations = [
  NavDestination(icon: Icons.home_outlined, label: 'Home', route: '/home'),
  NavDestination(
    icon: Icons.download_done_outlined,
    label: 'Downloaded',
    route: '/offline',
  ),
];

/// The section name shown in the unified title bar (app.dart) for a given
/// router [location]. Off the shell (login, detail, gallery) it falls back to
/// the app name. Pure + dependency-free so the title-bar text stays unit
/// testable without the window-manager chrome.
String shellSectionTitle(String location) {
  for (final d in kShellDestinations) {
    if (location.startsWith(d.route)) return d.label;
  }
  return 'Watchparty';
}

/// The persistent shell (nav rail + content area) that wraps the primary
/// destinations. Below [_compactBreakpoint] the rail collapses to icons only
/// so the window stays usable when snapped narrow; there is no separate
/// mobile layout in scope for v1 (desktop-first, PLAN §0).
///
/// The title bar (section name + command palette + sign out + window controls)
/// no longer lives here — it was consolidated into the single app-wide bar in
/// `app.dart`, above this shell. The shell now owns only the rail + content and
/// the app-wide keyboard layer ([AppShortcuts]).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  static const _compactBreakpoint = 720.0;

  String _currentOf(List<NavDestination> destinations) {
    for (final d in destinations) {
      if (location.startsWith(d.route)) return d.route;
    }
    return '/home';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    final destinations = isAuthenticated
        ? kShellDestinations
        : kGuestShellDestinations;
    return Scaffold(
      body: AppShortcuts(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _compactBreakpoint;
            return Stack(
              children: [
                Row(
                  children: [
                    _collapsibleRail(context, compact, destinations),
                    const VerticalDivider(width: 1, color: AppColors.line),
                    Expanded(child: child),
                  ],
                ),
                Positioned(
                  top: 16,
                  right: 20,
                  child: isAuthenticated
                      ? _ProfileButton(ref: ref)
                      : const _LoginButton(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Animates the 720px collapse at the shell level (per PLAN — `nav_rail.dart`
  /// stays untouched): [AnimatedSize] morphs the rail width (240 ⇄ 72) while
  /// [AnimatedSwitcher] cross-fades the swapped-in variant (opacity). Keying on
  /// `compact` triggers both when the breakpoint is crossed.
  Widget _collapsibleRail(
    BuildContext context,
    bool compact,
    List<NavDestination> destinations,
  ) {
    return AnimatedSize(
      duration: AppMotion.reveal,
      curve: AppMotion.emphasized,
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: AppMotion.reveal,
        switchInCurve: AppMotion.emphasized,
        // Size to the incoming rail only, so AnimatedSize animates straight to
        // the new width instead of first ballooning to the union of both.
        layoutBuilder: (currentChild, _) =>
            currentChild ?? const SizedBox.shrink(),
        child: NavRail(
          key: ValueKey(compact),
          destinations: destinations,
          currentRoute: _currentOf(destinations),
          compact: compact,
          onSelect: (route) => context.go(route),
        ),
      ),
    );
  }
}

/// Top-right chrome for a logged-out guest, replacing [_ProfileButton]: no
/// session to sign out of, so this just routes to `/login` (PLAN
/// guest-browse §D).
class _LoginButton extends StatelessWidget {
  const _LoginButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Login',
      child: Material(
        color: AppColors.bg,
        shape: const CircleBorder(side: BorderSide(color: AppColors.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          // A literal path, not `Routes.login`, to avoid importing
          // `router.dart` back into a screen it already imports this one from.
          onTap: () => context.go('/login'),
          child: const SizedBox.square(
            dimension: 40,
            child: Icon(Icons.login, size: 20, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.ref});

  final WidgetRef ref;

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showConfirm(
      context,
      title: 'Sign out?',
      body: 'You will need to pick your server and sign in again.',
      confirmLabel: 'Sign out',
    );
    if (confirmed) await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(
      authProvider.select((state) => state.user?.name ?? 'Profile'),
    );
    return Tooltip(
      message: '$name · Sign out',
      child: Material(
        color: AppColors.bg,
        shape: const CircleBorder(side: BorderSide(color: AppColors.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _signOut(context),
          child: const SizedBox.square(
            dimension: 40,
            child: Icon(Icons.person_outline, size: 20, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}
