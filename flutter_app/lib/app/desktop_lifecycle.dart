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
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Offset, Rect, Size;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Persisted-geometry keys. Public because they are a storage schema — a rename
/// silently drops everyone's window position — and the tests pin them.
const kWindowXPref = 'desktop.window.x';
const kWindowYPref = 'desktop.window.y';
const kWindowWPref = 'desktop.window.w';
const kWindowHPref = 'desktop.window.h';
const kWindowMaximizedPref = 'desktop.window.maximized';

const _defaultSize = Size(1280, 720);
const _minSize = Size(960, 600);

/// How long a move/resize burst may settle before the geometry is written. A
/// drag emits a callback per frame, so without this one gesture across a 4K
/// screen issues hundreds of read-then-write round trips.
const _boundsDebounce = Duration(milliseconds: 400);

/// A snapshot of what to persist about the window.
///
/// [normalBounds] is null while the window is maximized: `getBounds()` then
/// reports the maximized frame, and storing that as the window's size loses the
/// size it unmaximizes back to — the next launch would come up "restored" at
/// full-screen dimensions and the user's real window size would be gone.
class WindowGeometry {
  const WindowGeometry({required this.normalBounds, required this.maximized});

  /// The rule, kept apart from the `window_manager` call that supplies the
  /// arguments so it can be stated and tested on its own: what comes back from
  /// `getBounds()` is only the window's normal geometry when the window is not
  /// maximized.
  factory WindowGeometry.from({required Rect bounds, required bool maximized}) =>
      WindowGeometry(
        normalBounds: maximized ? null : bounds,
        maximized: maximized,
      );

  final Rect? normalBounds;
  final bool maximized;
}

/// Debounced, serialized writer for the window's persisted geometry.
///
/// Its own object because three separate races lived in the callbacks it
/// replaces:
///
///  * `onWindowMoved`/`onWindowResized` fire once per frame, so every drag ran
///    a full read-then-write per frame — [schedule] coalesces a burst into one;
///  * those writes were not serialized. Each callback fired five independent
///    `setDouble` futures and a `setBool`, and two overlapping callbacks could
///    interleave into a stored geometry that was half one window and half
///    another. Every write now queues behind the last one;
///  * a close during a drag dropped the pending geometry entirely. [flush] is
///    what the shutdown path awaits.
class WindowGeometryRecorder {
  WindowGeometryRecorder({
    required Future<WindowGeometry> Function() read,
    required Future<void> Function(WindowGeometry) write,
    Duration debounce = _boundsDebounce,
  }) : _read = read,
       _write = write,
       _debounce = debounce;

  final Future<WindowGeometry> Function() _read;
  final Future<void> Function(WindowGeometry) _write;
  final Duration _debounce;

  Timer? _timer;
  Future<void> _queue = Future<void>.value();

  /// Whether a coalesced write is still waiting on its debounce.
  bool get hasPendingWrite => _timer?.isActive ?? false;

  /// Note that the geometry changed. Cheap enough to call on every frame of a
  /// drag; the write happens once the gesture stops.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      _timer = null;
      _persist();
    });
  }

  /// Write now, and resolve once every queued write has landed. The shutdown
  /// path awaits this so closing the window mid-drag still persists where the
  /// window ended up.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _persist();
  }

  Future<void> _persist() {
    // Chained, not fired: the read and the write are one indivisible step, and
    // an earlier slow write landing on top of a newer one is the interleaving
    // this exists to prevent.
    final next = _queue.then((_) async {
      try {
        await _write(await _read());
      } catch (_) {
        // Window geometry is a convenience. A failed write must neither crash
        // the app from a timer callback nor wedge the queue behind it.
      }
    });
    _queue = next;
    return next;
  }
}

/// Writes [geometry] into [prefs].
///
/// A null [WindowGeometry.normalBounds] leaves the stored position and size
/// alone — that is the maximized case, and the live bounds there describe the
/// maximized frame rather than the window the user will get back.
Future<void> persistWindowGeometry(
  SharedPreferences prefs,
  WindowGeometry geometry,
) async {
  final bounds = geometry.normalBounds;
  if (bounds != null) {
    await prefs.setDouble(kWindowXPref, bounds.left);
    await prefs.setDouble(kWindowYPref, bounds.top);
    await prefs.setDouble(kWindowWPref, bounds.width);
    await prefs.setDouble(kWindowHPref, bounds.height);
  }
  await prefs.setBool(kWindowMaximizedPref, geometry.maximized);
}

/// Restores persisted window bounds, sets the min-size, and turns a window
/// close into an orderly process exit. Call once during startup, before
/// `runApp`.
class DesktopLifecycle with WindowListener {
  DesktopLifecycle._();
  static final DesktopLifecycle instance = DesktopLifecycle._();

  bool _quitting = false;
  SharedPreferences? _prefs;
  WindowGeometryRecorder? _geometry;

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
      // Not schedule(): the process is about to exit, so a pending debounce
      // would never fire and the last drag would be lost.
      await _geometry?.flush();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } finally {
      exit(0);
    }
  }

  Future<void> init() async {
    await windowManager.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _geometry = WindowGeometryRecorder(
      read: _readGeometry,
      write: (geometry) => persistWindowGeometry(prefs, geometry),
    );

    final options = WindowOptions(
      size: _restoredSize(),
      minimumSize: _minSize,
      center: prefs.getDouble(kWindowXPref) == null,
      title: 'Watchparty',
      titleBarStyle: Platform.isMacOS || Platform.isWindows
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: Platform.isMacOS,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      final x = prefs.getDouble(kWindowXPref);
      final y = prefs.getDouble(kWindowYPref);
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      // Sized and positioned to the stored NORMAL bounds first, then maximized:
      // the stored bounds are what unmaximizing has to give back.
      if (prefs.getBool(kWindowMaximizedPref) ?? false) {
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
    final w = _prefs?.getDouble(kWindowWPref);
    final h = _prefs?.getDouble(kWindowHPref);
    if (w != null && h != null) return Size(w, h);
    return _defaultSize;
  }

  static Future<WindowGeometry> _readGeometry() async => WindowGeometry.from(
    bounds: await windowManager.getBounds(),
    maximized: await windowManager.isMaximized(),
  );

  // --- WindowListener ---

  @override
  void onWindowClose() => _shutdown();

  @override
  void onWindowMoved() => _geometry?.schedule();

  @override
  void onWindowResized() => _geometry?.schedule();

  // Maximize state is persisted separately from the bounds, so it needs its own
  // trigger: the accompanying resize would record the flag too, but only these
  // fire when a platform maximizes without a resize callback.
  @override
  void onWindowMaximize() => _geometry?.schedule();

  @override
  void onWindowUnmaximize() => _geometry?.schedule();
}
