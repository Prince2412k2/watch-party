import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/ui.dart';

/// The persistent shell (nav rail + content area) that wraps the primary
/// destinations. E1 finalizes the chrome; Phase 0 gives a working frame so the
/// app boots and routes are navigable.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavRail(
            destinations: _destinations,
            currentRoute: _current,
            onSelect: (route) => context.go(route),
          ),
          const VerticalDivider(width: 1, color: AppColors.line),
          Expanded(child: child),
        ],
      ),
    );
  }
}
