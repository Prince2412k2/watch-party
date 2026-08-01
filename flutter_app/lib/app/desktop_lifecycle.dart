// E10 — desktop packaging concerns: window-state persistence and an orderly
// shutdown. Kept in its own file so the only touch point in `main.dart` is a
// single `await DesktopLifecycle.instance.init()` call.
//
// Closing the window QUITS. There is no close-to-tray and no tray icon: the
// process used to survive a close so downloads could continue, but it also kept
// the LiveKit room — and therefore the camera and mic — alive behind a window
// the user believed was gone. Nothing is left that needs a resident process, so
// the close request is intercepted only long enough to release devices, pause
// transfers and persist bounds, then the process exits. Downloads resume from
// their byte offsets on the next launch.
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
import 'package:window_manager/window_manager.dart';

const _kWindowX = 'desktop.window.x';
const _kWindowY = 'desktop.window.y';
const _kWindowW = 'desktop.window.w';
const _kWindowH = 'desktop.window.h';
const _kWindowMaximized = 'desktop.window.maximized';

const _defaultSize = Size(1280, 720);
const _minSize = Size(960, 600);

/// Restores persisted window bounds, sets the min-size, and turns a window
/// close into an orderly process exit. Call once during startup, before
/// `runApp`.
class DesktopLifecycle with WindowListener {
  DesktopLifecycle._();
  static final DesktopLifecycle instance = DesktopLifecycle._();

  bool _quitting = false;
  SharedPreferences? _prefs;

  /// Invoked once, before the process exits: release the LiveKit room (the
  /// camera and mic), stop playback, and pause transfers. Set from `main.dart`
  /// once the providers exist.
  Future<void> Function()? onShutdown;

  /// Runs [onShutdown] without letting a failure block the exit. Teardown is
  /// best-effort by nature — a hung provider must not leave the user with a
  /// window that refuses to close.
  Future<void> _releaseResources() async {
    final release = onShutdown;
    if (release == null) return;
    try {
      await release().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Nothing actionable at teardown; the window closes regardless.
    }
  }

  /// Same orderly exit as a window close, for the updater's restart.
  Future<void> quitForUpdate() => _shutdown();

  Future<void> _shutdown() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await _releaseResources();
      await _persistBounds();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } finally {
      exit(0);
    }
  }

  Future<void> init() async {
    await windowManager.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();

    final options = WindowOptions(
      size: _restoredSize(),
      minimumSize: _minSize,
      center: _prefs!.getDouble(_kWindowX) == null,
      title: 'Watchparty',
      titleBarStyle: Platform.isMacOS || Platform.isWindows
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: Platform.isMacOS,
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
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(this);
    // Intercept the close request — not to keep the process alive, but so the
    // teardown in onWindowClose gets to run before the process exits.
    await windowManager.setPreventClose(true);
  }

  Size _restoredSize() {
    final w = _prefs?.getDouble(_kWindowW);
    final h = _prefs?.getDouble(_kWindowH);
    if (w != null && h != null) return Size(w, h);
    return _defaultSize;
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
  void onWindowClose() => _shutdown();

  @override
  void onWindowMoved() => _persistBounds();

  @override
  void onWindowResized() => _persistBounds();
}
