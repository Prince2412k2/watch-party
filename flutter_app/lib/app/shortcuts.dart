import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/state.dart';
import '../ui/command_palette.dart';
import '../ui/ui.dart' show NavDestination;
import 'screens/app_shell.dart'
    show kGuestShellDestinations, shellDestinationsFor;

/// Jump to the nth primary destination (keys 1–4, the four bottom-nav tabs).
class NavigateToIndexIntent extends Intent {
  const NavigateToIndexIntent(this.index);
  final int index;
}

/// Open the command palette (Ctrl/Cmd-K).
class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

/// Focus search ('/'). With no shell-level search field, this opens the command
/// palette (the app's unified search surface) with its input focused.
class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

/// The app-wide keyboard layer, mounted inside the shell (PLAN PKG-E). It is
/// deliberately scoped to the shell — the immersive detail/party player routes
/// live *outside* it, so these bindings never shadow the player's own keymap.
///
/// Single-key bindings (1–4, '/') are suppressed while a text field is focused
/// so typing digits/slashes into search or chat still works; the modified
/// bindings (Ctrl/Cmd-K, Ctrl/Cmd-W) are always live.
class AppShortcuts extends ConsumerWidget {
  const AppShortcuts({super.key, required this.child});

  final Widget child;

  static bool _isEditing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _openPalette(
    BuildContext context,
    WidgetRef ref,
    List<NavDestination> destinations,
  ) {
    showCommandPalette(
      context: context,
      ref: ref,
      destinations: destinations,
      onNavigate: (route) => context.go(route),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A logged-out guest only gets Movies + Downloaded (PLAN guest-browse), and
    // a member gets everything but Discover — the digit shortcuts, the arrow-key
    // nav action, and the command palette must all stick to whichever subset
    // applies, so nobody can jump to a gated route past the bottom nav.
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    final destinations = isAuthenticated
        ? shellDestinationsFor(isAdmin: ref.watch(isAdminProvider))
        : kGuestShellDestinations;

    final shortcuts = <ShortcutActivator, Intent>{
      for (var i = 0; i < _digitKeys.length && i < destinations.length; i++)
        SingleActivator(_digitKeys[i]): NavigateToIndexIntent(i),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          const OpenCommandPaletteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
          const OpenCommandPaletteIntent(),
      const SingleActivator(LogicalKeyboardKey.slash):
          const FocusSearchIntent(),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          NavigateToIndexIntent: CallbackAction<NavigateToIndexIntent>(
            onInvoke: (intent) {
              if (_isEditing()) return null;
              if (intent.index < destinations.length) {
                context.go(destinations[intent.index].route);
              }
              return null;
            },
          ),
          OpenCommandPaletteIntent: CallbackAction<OpenCommandPaletteIntent>(
            onInvoke: (_) {
              _openPalette(context, ref, destinations);
              return null;
            },
          ),
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) {
              if (_isEditing()) return null;
              _openPalette(context, ref, destinations);
              return null;
            },
          ),
        },
        // Give the layer a focus anchor so the bindings fire before the user
        // has clicked into any particular control.
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
