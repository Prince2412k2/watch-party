import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/command_palette.dart';
import 'screens/app_shell.dart' show kShellDestinations;

/// Jump to the nth primary destination (keys 1–6).
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

/// Hide the window to the tray (Ctrl/Cmd-W) — close-to-tray, not quit.
class HideToTrayIntent extends Intent {
  const HideToTrayIntent();
}

const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];

/// The app-wide keyboard layer, mounted inside the shell (PLAN PKG-E). It is
/// deliberately scoped to the shell — the immersive detail/party player routes
/// live *outside* it, so these bindings never shadow the player's own keymap.
///
/// Single-key bindings (1–6, '/') are suppressed while a text field is focused
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

  void _openPalette(BuildContext context, WidgetRef ref) {
    showCommandPalette(
      context: context,
      ref: ref,
      destinations: kShellDestinations,
      onNavigate: (route) => context.go(route),
    );
  }

  void _hideToTray() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.hide();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = <ShortcutActivator, Intent>{
      for (
        var i = 0;
        i < _digitKeys.length && i < kShellDestinations.length;
        i++
      )
        SingleActivator(_digitKeys[i]): NavigateToIndexIntent(i),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          const OpenCommandPaletteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
          const OpenCommandPaletteIntent(),
      const SingleActivator(LogicalKeyboardKey.slash):
          const FocusSearchIntent(),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true):
          const HideToTrayIntent(),
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
          const HideToTrayIntent(),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          NavigateToIndexIntent: CallbackAction<NavigateToIndexIntent>(
            onInvoke: (intent) {
              if (_isEditing()) return null;
              if (intent.index < kShellDestinations.length) {
                context.go(kShellDestinations[intent.index].route);
              }
              return null;
            },
          ),
          OpenCommandPaletteIntent: CallbackAction<OpenCommandPaletteIntent>(
            onInvoke: (_) {
              _openPalette(context, ref);
              return null;
            },
          ),
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) {
              if (_isEditing()) return null;
              _openPalette(context, ref);
              return null;
            },
          ),
          HideToTrayIntent: CallbackAction<HideToTrayIntent>(
            onInvoke: (_) {
              _hideToTray();
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
