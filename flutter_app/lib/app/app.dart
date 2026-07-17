import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../state/theme_provider.dart';
import '../ui/ui.dart';
import 'router.dart';

/// Root widget. Wires the mode-based theme + router. State DI lives at the
/// [ProviderScope]/[UncontrolledProviderScope] in `main.dart`; by the time this
/// widget builds, boot-time session restore has already resolved, so the
/// router's auth redirect never flashes the wrong screen.
///
/// Desktop controls are integrated over edge-to-edge content rather than living
/// in a separate title bar.
class WatchpartyApp extends ConsumerStatefulWidget {
  const WatchpartyApp({super.key, this.enableWindowFrame = true});

  /// Disabled by widget tests so they do not call desktop platform channels.
  final bool enableWindowFrame;

  @override
  ConsumerState<WatchpartyApp> createState() => _WatchpartyAppState();
}

class _WatchpartyAppState extends ConsumerState<WatchpartyApp> {
  late final _router = buildRouter(ref);

  @override
  Widget build(BuildContext context) {
    // The persisted theme drives BOTH the Material theme and the shadcn layer.
    // Switching modes rebuilds only the theme boundary + ambient wash — it never
    // remounts the functional subtrees (PLAN §global invariants).
    final mode = ref.watch(themeModeProvider);
    final theme = AppTheme.forMode(mode);
    final scTheme = AppShadcnTheme.forMode(mode);
    final isLight = theme.brightness == Brightness.light;

    return MaterialApp.router(
      title: 'Watchparty',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
      localizationsDelegates: sc.ShadcnLocalizations.localizationsDelegates,
      supportedLocales: sc.ShadcnLocalizations.supportedLocales,
      routerConfig: _router,
      builder: (context, child) {
        // ShadcnLayer wraps every route so shadcn components resolve their theme
        // + overlay infrastructure. MaterialType.transparency supplies the
        // Material text/ink plumbing for any chrome that renders above a route's
        // own Scaffold, without painting a background.
        final content = Material(
          type: MaterialType.transparency,
          child: child ?? const SizedBox.shrink(),
        );
        return sc.ShadcnLayer(
          theme: scTheme,
          themeMode: isLight ? sc.ThemeMode.light : sc.ThemeMode.dark,
          child: widget.enableWindowFrame
              ? DesktopWindowChrome(child: content)
              : content,
        );
      },
    );
  }
}
