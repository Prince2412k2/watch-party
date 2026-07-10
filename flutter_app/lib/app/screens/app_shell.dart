import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/state.dart';
import '../../ui/ui.dart';

/// The persistent shell (nav rail + content area) that wraps the primary
/// destinations. Below `_compactBreakpoint` the rail collapses to icons only
/// so the window stays usable when snapped narrow; there is no separate
/// mobile layout in scope for v1 (desktop-first, PLAN §0).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  static const _compactBreakpoint = 720.0;

  static const _destinations = [
    NavDestination(icon: Icons.home_outlined, label: 'Home', route: '/home'),
    NavDestination(icon: Icons.explore_outlined, label: 'Browse', route: '/browse'),
    NavDestination(icon: Icons.groups_outlined, label: 'Party', route: '/party'),
    NavDestination(icon: Icons.download_outlined, label: 'Downloads', route: '/downloads'),
    NavDestination(icon: Icons.wifi_off_outlined, label: 'Offline', route: '/offline'),
    NavDestination(icon: Icons.cloud_download_outlined, label: 'Find', route: '/servarr'),
  ];

  String get _current {
    for (final d in _destinations) {
      if (location.startsWith(d.route)) return d.route;
    }
    return '/home';
  }

  String get _title {
    for (final d in _destinations) {
      if (d.route == _current) return d.label;
    }
    return 'Watchparty';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _WindowChrome(title: _title),
          const Divider(height: 1, color: AppColors.line),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < _compactBreakpoint;
                return Row(
                  children: [
                    NavRail(
                      destinations: _destinations,
                      currentRoute: _current,
                      compact: compact,
                      onSelect: (route) => context.go(route),
                    ),
                    const VerticalDivider(width: 1, color: AppColors.line),
                    Expanded(child: child),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A flat, chrome-only title bar: it doesn't own real OS window controls (no
/// window-manager package is wired yet — that's E10 packaging), but gives the
/// shell a desktop-app top edge with the current section name, matching the
/// "content is the interface" rule — no gradient, no elevation shadow.
class _WindowChrome extends ConsumerWidget {
  const _WindowChrome({required this.title});
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 44,
      color: AppColors.bg,
      padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dim)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _confirmLogout(context, ref),
            icon: const Icon(Icons.logout, size: 15, color: AppColors.dim),
            label: const Text('Sign out',
                style: TextStyle(color: AppColors.dim, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirm(
      context,
      title: 'Sign out?',
      body: 'You will need to pick your server and sign in again.',
      confirmLabel: 'Sign out',
    );
    if (ok) await ref.read(authProvider.notifier).logout();
  }
}
