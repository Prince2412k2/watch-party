# Packaging (E10)

## Identity

| | |
|---|---|
| Product name | Watchparty |
| Bundle/app id | `com.watchparty.desktop` |
| Linux binary name | `watchparty` |
| Version | from `pubspec.yaml` (`version: X.Y.Z+build`) |

Set in `linux/CMakeLists.txt` (`APPLICATION_ID`), `linux/runner/my_application.cc`
(window title), and `macos/Runner/Configs/AppInfo.xcconfig`
(`PRODUCT_NAME` / `PRODUCT_BUNDLE_IDENTIFIER`).

## Linux: build + package

One-time host setup (build machine only — these are *build-time* deps, not
required on the target machine):

```
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev \
  libayatana-appindicator3-dev
```

Then:

```
flutter_app/packaging/build-linux.sh            # AppImage + .deb
flutter_app/packaging/build-linux.sh appimage   # AppImage only
flutter_app/packaging/build-linux.sh deb        # .deb only
```

This runs `flutter build linux --release`, then assembles the package(s) into
`flutter_app/build/dist/`. `linuxdeploy` and `appimagetool` are downloaded on
first run into `packaging/linux/.cache/` (gitignored) and reused after.

### Run it

```
build/dist/Watchparty-<version>-x86_64.AppImage
```

or install the deb: `sudo dpkg -i build/dist/watchparty_<version>_amd64.deb`
(then run `watchparty` from a terminal or the app launcher).

### What's bundled vs what the target machine needs

`flutter build linux` alone links against **system** libmpv (media_kit) and
ships `libwebrtc.so` (livekit_client) directly in `bundle/lib/`. Only the
AppImage is fully self-contained; the .deb leans on apt dependencies instead.

**AppImage** (self-contained — runs on a clean machine with no dev libs
installed): `linuxdeploy` walks the full `ldd` closure of the `watchparty`
binary and copies everything that isn't on its baseline-distro excludelist
into `usr/lib/`, then sets `LD_LIBRARY_PATH` via `AppRun`. In practice that
means it bundles:
- `libmpv.so.1` and its full transitive dependency tree (the ffmpeg/codec
  libs mpv itself needs: libavcodec, libavformat, libx264, libx265, libvpx,
  libdav1d, libass, etc.) — this is exactly the "libmpv bundling for
  AppImage" risk called out in the plan; `linuxdeploy` is the documented
  media_kit-recommended tool for it.
- `libwebrtc.so`'s own runtime deps beyond core GTK/X11 (e.g. `libasound`,
  `libpulse`).
- The Flutter engine + all plugin `.so`s (already produced by `flutter build`).

Still assumed present on the target (true baseline on any Linux desktop —
`linuxdeploy`'s excludelist, glibc/X11/GTK runtime): `libc`, `libgtk-3`,
`libX11` and friends, `libayatana-appindicator3` (present on
Ubuntu/Debian/Fedora desktops with a tray; if genuinely absent, the tray icon
just won't render — the window itself still works).

**`.deb`**: does *not* bundle libmpv or ffmpeg — it declares `Depends:` and
expects apt to install them:
```
libgtk-3-0, libayatana-appindicator3-1, libmpv2 | libmpv1,
gstreamer1.0-plugins-good, gstreamer1.0-plugins-bad, gstreamer1.0-libav
```
(`libwebrtc.so` is still bundled inside `/usr/lib/watchparty/lib/`, same as
the AppImage — Debian doesn't package a system libwebrtc.) If you need a
"never touches apt" Linux artifact, use the AppImage.

### Verifying on a clean machine

```
ldd build/linux/x64/release/bundle/watchparty | grep "not found"   # should be empty on the build host
ldd build/linux/x64/release/AppDir/usr/bin/watchparty              # same binary; libs now resolve from AppDir/usr/lib via AppRun's LD_LIBRARY_PATH
```
The real test is running the `.AppImage` on a machine/container that has
*never* had `libmpv`/ffmpeg-dev installed — nothing here can fully substitute
for that, but the excludelist approach is the same one every other
media_kit-based AppImage packaging guide uses.

## Desktop lifecycle (window state, tray, close-to-tray, single instance)

- **Single instance (Linux)**: handled natively — `linux/runner/main.cc`
  registers the app under `com.watchparty.desktop` via `GApplication`
  without `G_APPLICATION_NON_UNIQUE`. GLib's D-Bus session-bus name grab
  means a second launch never even starts a second Dart engine; its
  `activate` is forwarded over D-Bus to the already-running process, which
  raises its existing `GtkWindow` (see `my_application_activate` in
  `my_application.cc`). macOS gets the same behavior for free from Cocoa
  app activation (no code needed there yet).
- **Window-state persistence, close-to-tray, tray menu**: `lib/app/desktop_lifecycle.dart`
  (`DesktopLifecycle`), using `window_manager` + `tray_manager` +
  `shared_preferences`. Window position/size/maximized state persist across
  restarts; closing the window hides it instead of quitting (so background
  downloads keep running); the tray menu's "Quit" is the only path that
  actually exits. Wired from `lib/main.dart` with a single
  `await DesktopLifecycle.instance.init()` call — see the `// E10:` comment
  there.
- Icons live in `assets/icons/` (`app_icon.png` for the window/app icon,
  `tray_icon.png` — a smaller variant — for the tray).

## Windows / macOS (not built yet — sketch only)

Not implemented in this pass; noted here so a future E10 follow-up doesn't
have to start from scratch.

- **macOS**: `flutter build macos --release`, then `create-dmg` (or
  `hdiutil`) for a `.dmg`. Bundle id/name already set
  (`com.watchparty.desktop` / Watchparty) in `AppInfo.xcconfig`. media_kit
  and livekit_client both publish prebuilt macOS frameworks (no manual
  native-lib bundling needed, unlike Linux) — signing/notarization is the
  main remaining gap (needs an Apple Developer ID + `codesign`/`notarytool`,
  not available in this environment).
- **Windows**: `flutter build windows --release`, then either an NSIS/Inno
  Setup installer or an MSIX package. `window_manager`/`tray_manager` both
  support Windows already (no new packages needed). Single-instance would
  need a Win32-specific approach (named mutex check in `windows/runner/main.cpp`
  before creating the window) since there's no GApplication-equivalent —
  that C++ change is the one piece of native work Windows needs that Linux
  didn't.
