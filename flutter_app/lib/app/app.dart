import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/ui.dart';
import 'router.dart';

/// Root widget. Wires the frozen theme + router. State DI lives at the
/// [ProviderScope]/[UncontrolledProviderScope] in `main.dart`; by the time this
/// widget builds, boot-time session restore has already resolved, so the
/// router's auth redirect (E2) never flashes the wrong screen.
///
/// The window is frameless + rounded (see `desktop_lifecycle.dart` +
/// `linux/runner/my_application.cc`): [VirtualWindowFrame] paints the rounded
/// corners, border, and shadow and provides edge-resize, while [_WindowBar]
/// draws the drag region + min/maximize/close controls the OS frame no longer
/// provides.
class WatchpartyApp extends ConsumerStatefulWidget {
  const WatchpartyApp({super.key, this.enableWindowFrame = true});

  /// The custom frameless window chrome (drag bar + rounded [VirtualWindowFrame])
  /// drives window_manager platform channels, which aren't available under
  /// `flutter test` — widget tests pass `false` to skip it.
  final bool enableWindowFrame;

  @override
  ConsumerState<WatchpartyApp> createState() => _WatchpartyAppState();
}

class _WatchpartyAppState extends ConsumerState<WatchpartyApp> {
  late final _router = buildRouter(ref);

  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Watchparty',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (!_isDesktop || !widget.enableWindowFrame) return content;
        return VirtualWindowFrame(
          child: Column(
            children: [
              const _WindowBar(),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

/// The custom, frameless title bar: a thin draggable strip with window controls
/// on the right. Flat near-black, no gradient — matches the cinematic-minimal
/// system. Double-click toggles maximize, like a native title bar.
class _WindowBar extends StatelessWidget {
  const _WindowBar();

  static const double height = 32;

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: AppColors.bg,
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _toggleMaximize,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            _WindowButton(
              icon: Icons.remove,
              tooltip: 'Minimize',
              onPressed: windowManager.minimize,
            ),
            _WindowButton(
              icon: Icons.crop_square,
              tooltip: 'Maximize',
              iconSize: 13,
              onPressed: _toggleMaximize,
            ),
            _WindowButton(
              icon: Icons.close,
              tooltip: 'Close',
              hoverColor: AppColors.red,
              onPressed: windowManager.close,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor,
    this.iconSize = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final double iconSize;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover
        ? (widget.hoverColor ?? const Color(0x14FFFFFF))
        : Colors.transparent;
    final fg = (_hover && widget.hoverColor != null)
        ? Colors.white
        : (_hover ? AppColors.text : AppColors.dim);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: _WindowBar.height,
            color: bg,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
