import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analog/chrome/analog_toast.dart';
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
    // The persisted theme drives the Material theme. Switching modes rebuilds
    // only the theme boundary + ambient wash — it never remounts the functional
    // subtrees (PLAN §global invariants).
    final mode = ref.watch(themeModeProvider);
    final theme = AppTheme.forMode(mode);
    final isLight = theme.brightness == Brightness.light;

    return MaterialApp.router(
      title: 'Watchparty',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
      // Supplied directly now that no component library is contributing its own
      // delegates. The app ships one locale; these are the framework strings
      // (semantics, text selection, the date pickers Material builds).
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      routerConfig: _router,
      builder: (context, child) {
        // MaterialType.transparency supplies the Material text/ink plumbing for
        // any chrome that renders above a route's own Scaffold, without painting
        // a background.
        //
        // AnalogToastHost sits *above* the router, which is the whole point:
        // the party socket's handlers outlive every screen and have nothing but
        // the root navigator's context to raise a notice from.
        final content = AnalogToastHost(
          child: Material(
            type: MaterialType.transparency,
            child: child ?? const SizedBox.shrink(),
          ),
        );
        return widget.enableWindowFrame
            ? DesktopWindowChrome(child: content)
            : content;
      },
    );
  }
}
