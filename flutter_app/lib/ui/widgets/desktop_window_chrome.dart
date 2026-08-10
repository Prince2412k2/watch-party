import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const double integratedDesktopChromeHeight = 32;

double get desktopLeadingControlInset => Platform.isMacOS ? 78 : 0;

/// Transparent desktop window controls layered over edge-to-edge app content.
///
/// This wraps the ENTIRE app, the player included, so its build has one hard
/// constraint: the shape of the tree it returns may never change. Everything
/// below it is remounted the moment it does, and what is below it is the film.
class DesktopWindowChrome extends StatefulWidget {
  const DesktopWindowChrome({
    super.key,
    required this.child,
    this.debugIsMacOS,
    this.debugFullscreen,
  });

  final Widget child;

  /// Test seams for the two inputs that decide the caption strip. Both are
  /// platform/window state in production, neither is reachable from a widget
  /// test, and the invariant they gate — that the tree survives a fullscreen
  /// change — is the one thing here worth pinning.
  @visibleForTesting
  final bool? debugIsMacOS;
  @visibleForTesting
  final bool? debugFullscreen;

  @override
  State<DesktopWindowChrome> createState() => _DesktopWindowChromeState();
}

class _DesktopWindowChromeState extends State<DesktopWindowChrome>
    with WindowListener {
  bool _fullscreen = false;

  bool get _isMacOS => widget.debugIsMacOS ?? Platform.isMacOS;
  bool get _isFullscreen => widget.debugFullscreen ?? _fullscreen;

  @override
  void initState() {
    super.initState();
    if (_isMacOS && widget.debugIsMacOS == null) {
      windowManager.addListener(this);
      _readWindowState();
    }
  }

  Future<void> _readWindowState() async {
    final fullscreen = await windowManager.isFullScreen();
    if (mounted) {
      setState(() => _fullscreen = fullscreen);
    }
  }

  @override
  void dispose() {
    if (_isMacOS && widget.debugIsMacOS == null) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() => setState(() => _fullscreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullscreen = false);

  @override
  Widget build(BuildContext context) {
    // ALWAYS this Stack, with the caption strip added or dropped inside it.
    //
    // It used to return `widget.child` bare when fullscreen and a Stack
    // otherwise, and swapping the widget type at this position is a remount of
    // the whole app below it. On macOS that made Cmd+F unusable: entering
    // fullscreen tore down PlayerHost, whose dispose puts the window BACK out of
    // fullscreen, and the replacement mounted with no open title and re-opened
    // the film from the start. Fullscreen appeared to bounce and the movie
    // restarted, every time.
    //
    // A conditional child inside a stable parent changes what is painted without
    // changing whose element is which, which is the whole difference.
    return Stack(
      // The child is the app: it fills this, exactly as the Positioned.fill it
      // replaces did. Not left unpositioned and loose — under loose constraints
      // that would let the app shrink-wrap.
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_isMacOS && !_isFullscreen)
          Positioned(
            top: 0,
            left: desktopLeadingControlInset,
            right: 160,
            height: integratedDesktopChromeHeight,
            child: const DragToMoveArea(child: SizedBox.expand()),
          ),
      ],
    );
  }
}
