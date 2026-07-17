import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const double integratedDesktopChromeHeight = 32;

double get desktopLeadingControlInset => Platform.isMacOS ? 78 : 0;
double get desktopTrailingControlInset => Platform.isWindows ? 138 : 0;

/// Transparent desktop window controls layered over edge-to-edge app content.
class DesktopWindowChrome extends StatefulWidget {
  const DesktopWindowChrome({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWindowChrome> createState() => _DesktopWindowChromeState();
}

class _DesktopWindowChromeState extends State<DesktopWindowChrome>
    with WindowListener {
  bool _maximized = false;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isWindows) {
      windowManager.addListener(this);
      _readWindowState();
    }
  }

  Future<void> _readWindowState() async {
    final maximized = await windowManager.isMaximized();
    final fullscreen = await windowManager.isFullScreen();
    if (mounted) {
      setState(() {
        _maximized = maximized;
        _fullscreen = fullscreen;
      });
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS || Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowEnterFullScreen() => setState(() => _fullscreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullscreen = false);

  @override
  Widget build(BuildContext context) {
    if ((!Platform.isMacOS && !Platform.isWindows) || _fullscreen) {
      return widget.child;
    }

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          top: 0,
          left: Platform.isMacOS ? desktopLeadingControlInset : 0,
          right: Platform.isWindows ? desktopTrailingControlInset : 160,
          height: integratedDesktopChromeHeight,
          child: const DragToMoveArea(child: SizedBox.expand()),
        ),
        if (Platform.isWindows)
          Positioned(
            top: 0,
            right: 0,
            height: integratedDesktopChromeHeight,
            child: Row(
              children: [
                WindowCaptionButton.minimize(
                  brightness: Theme.of(context).brightness,
                  onPressed: windowManager.minimize,
                ),
                _maximized
                    ? WindowCaptionButton.unmaximize(
                        brightness: Theme.of(context).brightness,
                        onPressed: windowManager.unmaximize,
                      )
                    : WindowCaptionButton.maximize(
                        brightness: Theme.of(context).brightness,
                        onPressed: windowManager.maximize,
                      ),
                WindowCaptionButton.close(
                  brightness: Theme.of(context).brightness,
                  onPressed: windowManager.close,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
