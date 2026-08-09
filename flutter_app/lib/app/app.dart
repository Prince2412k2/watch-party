import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analog/chrome/analog_toast.dart';
import '../party/party_overlay.dart';
import '../player/player_host.dart';
import '../state/state.dart';
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
        // ChatNotifications sits INSIDE the host (it needs an ancestor to raise
        // a notice on) and outside the router (a per-screen listener would miss
        // exactly the messages that arrive while you are on another screen).
        final content = AnalogToastHost(
          // Clear of the caption strip, which is the one layer that outranks
          // the rail (DesktopWindowChrome wraps it).
          topInsetPx: widget.enableWindowFrame
              ? integratedDesktopChromeHeight
              : 0,
          child: ChatNotifications(
            child: Material(
              type: MaterialType.transparency,
              // PlayerHost owns the app's single PlayerView. It is HERE, above
              // the router, because playback has to outlive navigation: the
              // player used to be mounted inside two routes' Scaffolds, so
              // pressing Back destroyed it instead of minimising it.
              //
              // PartyOverlay wraps it rather than the other way round: a room's
              // cameras and chat have to render ON TOP of the movie, including
              // while it is full-window. Both are outside the router for the
              // same reason — a room outlives any one screen.
              //
              // The popcorn is ABOVE both, and mounted exactly once. It was
              // mounted per-screen — the shell had one, the detail screen had
              // another — which meant it blinked out of existence on any screen
              // that had forgotten to add it, and vanished entirely behind a
              // full-window film. It is the room's control surface, so the one
              // moment it must not disappear is while you are watching.
              child: Stack(
                children: [
                  Positioned.fill(
                    child: PartyOverlay(
                      child: PlayerHost(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  // Its own Overlay, because `MaterialApp.builder` wraps the
                  // Navigator rather than living inside it — so there is no
                  // Overlay above this point, and the popcorn's tooltips (and
                  // the dialogs its buttons open) need one. Only the tray
                  // itself is positioned, so the rest of this layer is empty
                  // and takes no hits.
                  Positioned.fill(
                    child: Overlay(
                      initialEntries: [
                        OverlayEntry(
                          builder: (_) => const Positioned(
                            right: 22,
                            bottom: 10,
                            child: _AuthedPopcorn(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return widget.enableWindowFrame
            ? DesktopWindowChrome(child: content)
            : content;
      },
    );
  }
}

/// The popcorn, for a signed-in user only. A logged-out guest has no session to
/// start a room from, and nothing to join one with.
class _AuthedPopcorn extends ConsumerWidget {
  const _AuthedPopcorn();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(authProvider.select((s) => s.isAuthenticated))
      ? const PopcornControl()
      : const SizedBox.shrink();
}
