#!/usr/bin/env bash
# E10 — Linux packaging: flutter build + AppImage (+ .deb) assembly.
#
# Usage:
#   packaging/build-linux.sh            # builds both AppImage and .deb
#   packaging/build-linux.sh appimage   # AppImage only
#   packaging/build-linux.sh deb        # .deb only
#
# What this does NOT do: it does not install build-time system packages
# (gtk3-dev, patchelf's transitive tooling, etc.) — see packaging/README.md
# for the one-time host setup. Tooling (linuxdeploy, appimagetool) is
# downloaded into packaging/linux/.cache/ on first run and reused after.
set -euo pipefail

TARGET="${1:-all}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/packaging"
CACHE_DIR="$PKG_DIR/linux/.cache"
DIST_DIR="$ROOT_DIR/build/dist"
BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"

APP_NAME="watchparty"
APP_DISPLAY_NAME="Watchparty"
APP_ID="com.watchparty.desktop"
VERSION="${VERSION:-$(grep -m1 '^version:' "$ROOT_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)}"
APP_ICON="$ROOT_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"

mkdir -p "$CACHE_DIR" "$DIST_DIR"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

fetch_tool() {
  local name="$1" url="$2" dest="$CACHE_DIR/$1"
  if [[ ! -x "$dest" ]]; then
    log "Downloading $name"
    curl -sL -o "$dest" "$url"
    chmod +x "$dest"
  fi
}

build_flutter() {
  log "flutter build linux --release"
  (cd "$ROOT_DIR" && flutter pub get && flutter build linux --release)
  test -x "$BUNDLE_DIR/$APP_NAME" || {
    echo "error: build did not produce $BUNDLE_DIR/$APP_NAME" >&2
    exit 1
  }
}

build_appimage() {
  fetch_tool linuxdeploy \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
  fetch_tool appimagetool \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

  local appdir="$ROOT_DIR/build/linux/x64/release/AppDir"
  log "Assembling AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr/bin"
  # Keep the Flutter bundle's own layout (watchparty, data/, lib/) intact —
  # the runner resolves data/ and lib/ relative to its own path ($ORIGIN),
  # so these three must stay siblings inside usr/bin/.
  cp -r "$BUNDLE_DIR/." "$appdir/usr/bin/"

  log "Running linuxdeploy (bundles libmpv + its ffmpeg/codec deps, and any"
  log "webrtc deps not already in usr/bin/lib — everything ldd finds that"
  log "isn't in linuxdeploy's baseline-system excludelist)"
  export PATH="$CACHE_DIR:$PATH"
  export NO_STRIP=1 # keep symbols; native crashes are hard enough to debug already
  "$CACHE_DIR/linuxdeploy" \
    --appdir "$appdir" \
    --executable "$appdir/usr/bin/$APP_NAME" \
    --desktop-file "$PKG_DIR/linux/watchparty.desktop" \
    --icon-file "$APP_ICON" \
    --icon-filename "$APP_ID" \
    --output appimage

  mkdir -p "$DIST_DIR"
  mv "$ROOT_DIR"/Watchparty*.AppImage "$DIST_DIR/Watchparty-$VERSION-x86_64.AppImage" 2>/dev/null \
    || mv "$ROOT_DIR"/watchparty*.AppImage "$DIST_DIR/Watchparty-$VERSION-x86_64.AppImage"
  log "AppImage written to $DIST_DIR/Watchparty-$VERSION-x86_64.AppImage"
}

build_deb() {
  log "Assembling .deb"
  local debroot
  debroot="$(mktemp -d)"
  local pkgdir="$debroot/$APP_NAME"
  local install_dir="$pkgdir/usr/lib/$APP_NAME"

  mkdir -p "$install_dir" "$pkgdir/usr/bin" "$pkgdir/usr/share/applications" \
    "$pkgdir/usr/share/icons/hicolor/512x512/apps" "$pkgdir/DEBIAN"

  cp -r "$BUNDLE_DIR/." "$install_dir/"
  ln -sf "/usr/lib/$APP_NAME/$APP_NAME" "$pkgdir/usr/bin/$APP_NAME"

  sed "s|Exec=watchparty|Exec=/usr/lib/$APP_NAME/$APP_NAME|" \
    "$PKG_DIR/linux/watchparty.desktop" \
    > "$pkgdir/usr/share/applications/$APP_ID.desktop"
  cp "$APP_ICON" \
    "$pkgdir/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  cat > "$pkgdir/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: $VERSION
Section: video
Priority: optional
Architecture: $arch
Maintainer: Watchparty <noreply@watchparty.local>
Description: Watchparty desktop client
 Synchronized watch-party playback, LiveKit audio/video, chat, and
 offline downloads.
Depends: libgtk-3-0, libayatana-appindicator3-1, libmpv2 | libmpv1,
 gstreamer1.0-plugins-good, gstreamer1.0-plugins-bad, gstreamer1.0-libav
EOF

  dpkg-deb --build --root-owner-group "$pkgdir" \
    "$DIST_DIR/${APP_NAME}_${VERSION}_${arch}.deb"
  rm -rf "$debroot"
  log "deb written to $DIST_DIR/${APP_NAME}_${VERSION}_${arch}.deb"
}

build_flutter

case "$TARGET" in
  appimage) build_appimage ;;
  deb) build_deb ;;
  all) build_appimage; build_deb ;;
  *) echo "unknown target: $TARGET (expected appimage|deb|all)" >&2; exit 1 ;;
esac

log "Done. Artifacts in $DIST_DIR"
ls -lh "$DIST_DIR"
