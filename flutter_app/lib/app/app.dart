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
              // ONE Overlay wrapping the lot.
              //
              // `MaterialApp.builder` wraps the Navigator rather than living
              // inside it, so nothing mounted here has an Overlay above it —
              // and Tooltip, dialogs, menus and text selection all require one.
              // Every root-mounted piece of chrome needs it, not just the
              // popcorn: the player's own transport bar is full of tooltips,
              // and without this it threw "No Overlay widget found" on the
              // first frame a film appeared and again on every rebuild after.
              //
              // Fixed here, once, rather than per-widget. The popcorn used to
              // carry a private Overlay of its own, which papered over the
              // symptom for exactly the one widget I had tested and left
              // everything else to fail at runtime.
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => Stack(
                      children: [
                        // PlayerHost owns the app's single PlayerView, above
                        // the router, because playback has to outlive
                        // navigation. PartyOverlay wraps it rather than the
                        // other way round: a room's cameras and chat render ON
                        // TOP of the film, including full-window.
                        Positioned.fill(
                          child: PartyOverlay(
                            child: PlayerHost(
                              child: child ?? const SizedBox.shrink(),
                            ),
                          ),
                        ),
                        // The popcorn is above both, and mounted exactly once.
                        // It used to be mounted per-screen, so it blinked out
                        // on any screen that had forgotten it and vanished
                        // entirely behind a full-window film — the one moment
                        // the room's controls must not disappear.
                        const Positioned(
                          right: 22,
                          bottom: 10,
                          child: _AuthedPopcorn(),
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
