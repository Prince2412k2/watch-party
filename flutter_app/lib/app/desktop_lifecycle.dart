// E10 — desktop packaging concerns: window-state persistence and
// close-to-tray. Kept in its own file so the only touch point in `main.dart`
// is a single `await DesktopLifecycle.instance.init()` call.
//
// Single-instance enforcement is NOT handled here: on Linux it's done
// natively (linux/runner/my_application.cc uses GApplication's D-Bus
// activation, so a second launch never reaches Dart at all — see the
// comment there). macOS gets the same behavior for free from Cocoa's app
// activation. Windows single-instance is a packaging TODO (see
// packaging/README.md).
//
// Not wired on web/mobile: callers should only invoke this on
// Platform.isLinux/isMacOS/isWindows.
import 'dart:io';

import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

const _kWindowX = 'desktop.window.x';
const _kWindowY = 'desktop.window.y';
const _kWindowW = 'desktop.window.w';
const _kWindowH = 'desktop.window.h';
const _kWindowMaximized = 'desktop.window.maximized';

const _defaultSize = Size(1280, 720);
const _minSize = Size(960, 600);

/// Restores persisted window bounds, sets the min-size, and installs a
/// close-to-tray handler + a Show/Quit tray menu. Call once during startup,
/// before `runApp`.
class DesktopLifecycle with WindowListener, TrayListener {
  DesktopLifecycle._();
  static final DesktopLifecycle instance = DesktopLifecycle._();

  bool _quitting = false;
  SharedPreferences? _prefs;

  /// Invoked just before the window hides to the tray. The process (and libmpv)
  /// keeps running when close-to-tray hides the window, so callers use this to
  /// pause media playback — otherwise audio keeps playing from a window the
  /// user believes they closed. Set from `main.dart` once the providers exist.
  void Function()? onBeforeHide;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();

    final options = WindowOptions(
      size: _restoredSize(),
      minimumSize: _minSize,
      center: _prefs!.getDouble(_kWindowX) == null,
      title: 'Watchparty',
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      final x = _prefs!.getDouble(_kWindowX);
      final y = _prefs!.getDouble(_kWindowY);
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      if (_prefs!.getBool(_kWindowMaximized) ?? false) {
        await windowManager.maximize();
      }
      // Close-to-tray: we intercept the window-close request ourselves
      // instead of letting it quit the process (see onWindowClose below).
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(this);
    await _initTray();
  }

  Size _restoredSize() {
    final w = _prefs?.getDouble(_kWindowW);
    final h = _prefs?.getDouble(_kWindowH);
    if (w != null && h != null) return Size(w, h);
    return _defaultSize;
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    // The app must still launch when a platform package omits the optional tray
    // icon. Previously this threw before runApp(), leaving a black window.
    try {
      await trayManager.setIcon('assets/icons/tray_icon.png');
    } catch (_) {
      return;
    }
    if (!Platform.isLinux) {
      // tray_manager's Linux (libayatana-appindicator) backend doesn't
      // implement setToolTip — only setIcon/setTitle/setContextMenu/destroy.
      await trayManager.setToolTip('Watchparty');
    }
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show Watchparty'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  Future<void> _persistBounds() async {
    final bounds = await windowManager.getBounds();
    final maximized = await windowManager.isMaximized();
    await _prefs?.setDouble(_kWindowX, bounds.left);
    await _prefs?.setDouble(_kWindowY, bounds.top);
    await _prefs?.setDouble(_kWindowW, bounds.width);
    await _prefs?.setDouble(_kWindowH, bounds.height);
    await _prefs?.setBool(_kWindowMaximized, maximized);
  }

  // --- WindowListener ---

  @override
  void onWindowClose() async {
    if (_quitting) {
      await windowManager.destroy();
      return;
    }
    // Hide instead of exiting: the process (and any in-flight downloads)
    // keeps running in the tray until "Quit" is chosen explicitly. Pause
    // playback first so audio doesn't keep going in the hidden window.
    onBeforeHide?.call();
    await _persistBounds();
    await windowManager.hide();
  }

  @override
  void onWindowMoved() => _persistBounds();

  @override
  void onWindowResized() => _persistBounds();

  // --- TrayListener ---

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'quit':
        _quitting = true;
        await _persistBounds();
        await trayManager.destroy();
        await windowManager.destroy();
        exit(0);
    }
  }
}
