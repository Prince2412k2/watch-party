# Phase 0 spike notes (Linux)

## Environment
- Ubuntu, GNOME on Wayland (`mutter`), XWayland available.
- Installed: `libwebkit2gtk-4.1-dev`, `libmpv-dev`, `pkg-config`, plus the
  standard Tauri Linux build deps. `cargo install tauri-cli` (v2.11.4) works
  with no sudo (installs to `~/.cargo/bin`).
- `mpv` 0.34.1 present as a system binary; `pkg-config --modversion mpv` → 1.109.0.

## What's proven
1. **`cargo check`/`cargo build` succeed** for a Tauri v2 app (`tray-icon`
   feature enabled) against this system's webkit2gtk/gtk stack. ~430 crates,
   clean build in dev profile (~30s incremental, longer cold).
2. **The app actually launches and renders the real React UI.** `cargo tauri
   dev` (pointed at a plain `vite` dev server, no `beforeDevCommand` wired yet)
   produced a live window showing the redesigned Login screen pixel-for-pixel
   as expected (monochrome, flat, near-white primary pill) — see the screenshot
   captured during this session. This confirms the whole toolchain
   (Rust/Tauri/webkit2gtk ↔ Vite/React) works end to end on this box.
3. **Icon requirements**: Tauri's `generate_context!()` panics at compile time
   if `bundle.icon` files are missing OR not RGBA. Fixed by generating
   placeholder RGBA PNGs (`convert ... PNG32:...`) — real icons are a later,
   non-blocking task (not gating any Phase 1 agent).

## Environment gotcha (fixed, worth documenting for future runs)
- **GTK/Wayland client creation silently failed** when launched from this
  agent's shell: the process started, no crash, no error in stdout/stderr, but
  no window appeared under the native Wayland path (`xdotool`/screenshot tools
  found nothing, and GNOME's D-Bus screenshot portal returned
  `AccessDenied`). Root cause: the shell this ran from is not attached to the
  logind graphical session (`XDG_SESSION_ID` empty, `tty` reports "not a tty")
  even though `DISPLAY`/`WAYLAND_DISPLAY`/`XAUTHORITY` env vars were inherited.
  **Fix: force `GDK_BACKEND=x11`** — this makes GTK create an XWayland window
  instead, which *is* visible/screenshottable from a detached shell in this
  environment. A normal interactive desktop launch (double-clicking the app,
  or running from a real terminal in the session) should not need this
  workaround — it's specific to running Tauri from an automated/detached
  process. Worth keeping `GDK_BACKEND=x11` as a documented fallback in
  `desktop/README.md` for anyone hitting the same "app runs, no window" symptom.

## What's NOT yet proven — the real crux (§2 of PLAN.md)
The compositing test above only exercised the **opaque** Login screen. The
actual hard problem — mpv rendering into a region **behind** a transparent
webview, with DOM overlays (camera tiles, chat, minimal controls) compositing
**on top** of the video — has NOT been tested yet, because:
- `mpv.rs`/`window.rs` are still stub modules (owned by agent N1); there is no
  libmpv embed code yet, only the frozen IPC command signatures in `ipc.rs`.
- Reaching a watch-party screen (where a `<video>`/mpv region would even
  appear) also requires the backend running + a logged-in session + a
  Jellyfin library, which is a full app-level integration test, not a
  15-minute spike.

**Recommendation:** treat "prove the compositing" as the FIRST task inside
agent N1's Phase-1 work (it already owns `mpv.rs`/`window.rs`), rather than
blocking Phase-1 fan-out entirely on it. The frozen contracts in
`app/client/src/native/contract.ts` and `desktop/src-tauri/src/ipc.rs` do not
depend on which compositing approach wins (transparent-webview-in-front vs. the
overlay-webview fallback from §2) — both approaches are called the same way
from JS (`mpv_set_region`, etc.), so N2–N9-equivalent agents (N3/N4/N5/N6/N7 in
this plan) can safely start in parallel now. N1 should spend its first
work-block on a minimal standalone libmpv-in-transparent-window test (no React,
just a Rust binary + a colored HTML overlay div) before wiring the full
production `mpv.rs`, and report back if the fallback is needed — that's a
half-day risk-reduction step, not a multi-day one.

## Scaffold committed in this Phase 0
- `desktop/src-tauri/{Cargo.toml,build.rs,tauri.conf.json,capabilities/default.json}`
- `desktop/src-tauri/src/{main.rs,lib.rs,ipc.rs,mpv.rs,window.rs,download.rs,offline.rs}`
  — `ipc.rs` has all commands from PLAN.md §4.2 with real signatures and
  `todo!()` bodies; the other four are empty module stubs with ownership doc
  comments.
- `desktop/package.json` (tauri CLI dev/build scripts)
- `app/client/src/native/{contract.ts,env.js,ipc.js}` — the frozen JS-side
  contract (§4.1) plus a mockable IPC transport.
- `app/server/native.js` + one route mount in `app/server/index.js` — the
  signed-URL endpoint shape from §4.3, HMAC sign/verify implemented for real,
  the actual Jellyfin proxy body stubbed `501` for agent N3.
- Placeholder RGBA app icons.

## Known follow-ups for Phase 1 agents (not blockers, just flagged)
- `desktop/tauri.conf.json`'s `devUrl` assumes the app/client Vite dev server
  runs on port 5173 (Vite's default). If port 5173 is taken by something else
  on your machine, Vite silently moves to 5174+ and you must edit `devUrl` to
  match, or wire a proper `beforeDevCommand`/`beforeDevCommand.cwd` pointing at
  `../../app/client` so `tauri dev` starts Vite itself — left to N7
  (Agent Card N7 already owns `tauri.conf.json`).
- `capabilities/default.json`'s permission list is a first guess (window
  show/hide/close/fullscreen + `core:default`); Tauri v2's ACL system applies
  to plugin commands, not necessarily custom `#[tauri::command]`s registered
  via `invoke_handler` — confirm this empirically once N1/N2 wire real command
  bodies, and add explicit allow entries if the frontend gets a permission
  denial calling `mpv_*`/`dl_*`.
