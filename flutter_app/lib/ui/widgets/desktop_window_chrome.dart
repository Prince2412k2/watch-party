import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const double integratedDesktopChromeHeight = 32;

double get desktopLeadingControlInset => Platform.isMacOS ? 78 : 0;

/// Transparent desktop window controls layered over edge-to-edge app content.
class DesktopWindowChrome extends StatefulWidget {
  const DesktopWindowChrome({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWindowChrome> createState() => _DesktopWindowChromeState();
}

class _DesktopWindowChromeState extends State<DesktopWindowChrome>
    with WindowListener {
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
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
    if (Platform.isMacOS) {
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
    if (!Platform.isMacOS || _fullscreen) {
      return widget.child;
    }

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
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
