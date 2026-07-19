import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const double integratedDesktopChromeHeight = 32;
const double windowsCaptionControlWidth = 36;

double get desktopLeadingControlInset => Platform.isMacOS ? 78 : 0;
double get desktopTrailingControlInset =>
    Platform.isWindows ? windowsCaptionControlWidth * 3 : 0;

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
            child: WindowsCaptionControls(
              maximized: _maximized,
              onMinimize: windowManager.minimize,
              onToggleMaximize: _maximized
                  ? windowManager.unmaximize
                  : windowManager.maximize,
              onClose: windowManager.close,
            ),
          ),
      ],
    );
  }
}

/// Compact Windows controls that keep the edge-to-edge title bar transparent.
class WindowsCaptionControls extends StatelessWidget {
  const WindowsCaptionControls({
    super.key,
    required this.maximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final bool maximized;
  final FutureOr<void> Function() onMinimize;
  final FutureOr<void> Function() onToggleMaximize;
  final FutureOr<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final yellow = dark ? const Color(0xFFF2C14E) : const Color(0xFF805500);
    final green = dark ? const Color(0xFF6DD6A0) : const Color(0xFF147447);
    final red = dark ? const Color(0xFFFF746D) : const Color(0xFFB4232E);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionControl(
          key: const ValueKey('windows-minimize'),
          tooltip: 'Minimize',
          icon: Icons.remove,
          color: yellow,
          onPressed: onMinimize,
        ),
        _CaptionControl(
          key: const ValueKey('windows-maximize'),
          tooltip: maximized ? 'Restore' : 'Maximize',
          icon: maximized ? Icons.filter_none : Icons.crop_square,
          color: green,
          onPressed: onToggleMaximize,
        ),
        _CaptionControl(
          key: const ValueKey('windows-close'),
          tooltip: 'Close',
          icon: Icons.close,
          color: red,
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _CaptionControl extends StatefulWidget {
  const _CaptionControl({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final FutureOr<void> Function() onPressed;

  @override
  State<_CaptionControl> createState() => _CaptionControlState();
}

class _CaptionControlState extends State<_CaptionControl> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _activate() {
    setState(() {
      _hovered = false;
      _pressed = false;
    });
    unawaited(Future<void>.sync(widget.onPressed));
  }

  @override
  Widget build(BuildContext context) {
    final opacity = _pressed ? 0.52 : (_hovered ? 1.0 : 0.78);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) {
          _setHovered(false);
          _setPressed(false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: _activate,
          child: Semantics(
            button: true,
            label: widget.tooltip,
            child: SizedBox(
              key: ValueKey('windows-${widget.tooltip.toLowerCase()}-surface'),
              width: windowsCaptionControlWidth,
              height: integratedDesktopChromeHeight,
              child: ColoredBox(
                color: Colors.transparent,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: opacity,
                    duration: const Duration(milliseconds: 90),
                    child: Icon(widget.icon, size: 15, color: widget.color),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
