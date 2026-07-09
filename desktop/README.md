# Watchparty desktop (Tauri v2)

Native desktop shell for Watchparty — all-codec playback via libmpv, resumable
offline downloads, and full watch-party sync, hosting the existing
`app/client` React app. See `docs/native/PLAN.md` for the full architecture;
this file only covers the dev/build/packaging workflow (Agent Card N7).

## Prerequisites (Linux)

```
sudo apt install libwebkit2gtk-4.1-dev libmpv-dev pkg-config \
  build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
cargo install tauri-cli --version '^2'
```

`mpv`/`libmpv` must be resolvable via `pkg-config --modversion mpv`.

## Dev workflow

```
cd desktop
npm run dev            # == `tauri dev`
```

`tauri.conf.json`'s `build.beforeDevCommand` starts `app/client`'s own Vite
dev server on a dedicated port (`5183`, `--strictPort`) so it never collides
with a Vite instance you might already have running for the plain web app;
`devUrl` points at that same port. If you change the port, update both.

### "The process starts but no window appears" (headless/automated shells)

If you launch `tauri dev`/the built binary from a shell that isn't attached to
the desktop's logind graphical session (common for CI runners or automated
agents — `XDG_SESSION_ID` empty, `tty` reports "not a tty" — even though
`DISPLAY`/`WAYLAND_DISPLAY`/`XAUTHORITY` are inherited), GTK's native Wayland
client creation can fail silently: no crash, no stderr, just no window and no
hit in screenshot tools. Force XWayland instead:

```
GDK_BACKEND=x11 npm run dev
```

A normal interactive launch (double-click, or a real terminal in your actual
desktop session) should not need this — it's specifically a workaround for
running Tauri from a detached/automated process. See
`docs/native/SPIKE-NOTES.md` for how this was diagnosed.

## Production build

```
cd desktop
npm run build           # == `tauri build`
```

This runs `beforeBuildCommand` (`npm run build` in `app/client`, producing
`app/client/dist`, which `frontendDist` points at), then bundles the Rust
binary. On Linux this produces an AppImage and a `.deb` under
`desktop/src-tauri/target/release/bundle/{appimage,deb}/` (see `bundle.targets`
in `tauri.conf.json`).

## libmpv bundling strategy

libmpv is a system library dependency (`libmpv-dev`/`libmpv.so` at build time),
**not** vendored into the Cargo build. What ships depends on the target:

- **`.deb`**: declare `libmpv2` (or the distro's current libmpv package name)
  as a runtime dependency in the bundle config so apt resolves it, rather than
  bundling the `.so`. This is the simplest, most correct option for a
  package-manager install — `tauri.conf.json`'s `bundle.linux.deb.depends`
  is the place to add it once N1's mpv binding crate is in and we know the
  exact `.so` version it links against on the build machine (left as a
  follow-up: add `"depends": ["libmpv2"]` — or whatever `ldd` on the built
  binary reports — under `bundle.linux.deb` in `tauri.conf.json`).
- **AppImage** (no package manager, must be self-contained): follow
  MaxVideoPlayer's `bundle-libmpv-linux.sh` recipe (referenced in
  `docs/native/PLAN.md` §2b) — study the *approach*, not the code (that repo
  is PolyForm Noncommercial-licensed):
  1. `ldd target/release/watchparty-desktop | grep libmpv` to find the exact
     `libmpv.so.N` the binary links against and its full path.
  2. Copy that `.so` (and its own transitive deps not already guaranteed
     present on target systems) into the AppImage's `usr/lib/` alongside the
     binary during the bundle step (a pre/post-bundle script hooked via
     `tauri build`'s `beforeBundleCommand` once N1's binding crate exists, or
     a manual `appimagetool` pass).
  3. `patchelf --set-rpath '$ORIGIN/../lib' target/release/watchparty-desktop`
     (or the AppImage's copy of it) so the binary finds the bundled `.so`
     first instead of relying on the host's system libmpv version — this is
     what makes the AppImage portable across distros with different libmpv
     versions/absence of libmpv entirely.
  4. Verify with `ldd` again post-patch, and by running the AppImage on a
     clean container/VM without `libmpv-dev` installed.
  This step isn't wired into `tauri build` yet — it depends on N1's mpv
  binding crate landing first (nothing links against libmpv yet, so there's
  nothing to bundle). Tracked here so N1/Phase 2 integration doesn't have to
  rediscover the recipe.
- **RPM**: same idea as `.deb` — declare libmpv as a system dependency
  (`Requires:`) rather than bundling, once we add an rpm bundle target.

## Tray / close-to-tray lifecycle (PLAN.md §0.5)

- Closing the main window hides it (`window.hide()`) instead of quitting —
  the process, and any of N2's in-flight downloads, keep running. Wired via
  `on_window_event` + `CloseRequestApi::prevent_close()` in `src/lib.rs`.
- A tray icon (`src/lib.rs`'s `setup` hook) exposes "Show Watchparty" (restores
  + focuses the window) and "Quit" (real exit).
- Both the tray "Quit" item and the frontend-invokable `app_quit` IPC command
  (`src/ipc.rs`) run the *same* body — there is one exit path. It emits
  `app:before-quit` as a documented flush hook: N2's downloader should either
  listen for that event or (once it has real state) call a synchronous flush
  directly from `app_quit` before `app.exit(0)` runs. Today `download.rs` is
  still a stub, so there is nothing to flush yet — this is left as a clearly
  marked `TODO(N2)` in `ipc.rs`.
- `tauri-plugin-single-instance` focuses the existing (possibly
  tray-hidden) window on a second launch instead of starting a competing
  process that would fight the first over on-disk download state.
- `tauri-plugin-window-state` persists window size/position across launches.

## Updater

`tauri-plugin-updater` is registered (`src/lib.rs`) but **not configured with
a real update server/endpoint** — there's nothing to point it at yet. To wire
a real auto-update later: add a `plugins.updater` block to `tauri.conf.json`
with `pubkey` (from `tauri signer generate`) and `endpoints`, and call the
plugin's `check()`/`download_and_install()` from the frontend or a Rust
startup hook. Left as a stub per Agent Card N7 ("updater config stub is fine,
no real update server needed" for v1).

## CI matrix (stub, not required green off-Linux)

Only Linux is proven end-to-end (per `docs/native/PLAN.md` §0.4). A CI matrix
stub for the other two OSes, to be filled in once macOS/Windows packaging is
actually tackled:

```yaml
# .github/workflows/desktop-build.yml (not yet created — sketch only)
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
runs-on: ${{ matrix.os }}
steps:
  - uses: actions/checkout@v4
  - uses: dtolnay/rust-toolchain@stable
  - if: matrix.os == 'ubuntu-latest'
    run: sudo apt-get update && sudo apt-get install -y libwebkit2gtk-4.1-dev libmpv-dev libayatana-appindicator3-dev librsvg2-dev
  # macOS: brew install mpv; Windows: mpv via a package manager or vendored DLL — unproven, flagged in PLAN.md §0.4/§7.
  - run: cd app/client && npm ci && npm run build
  - run: cd desktop && npm ci && npm run build
```

Not committed as a real workflow yet since macOS/Windows toolchains for
libmpv aren't proven (`docs/native/PLAN.md` §7 explicitly defers this).
