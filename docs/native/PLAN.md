# Watchparty Native Desktop App — Execution Plan (for Sonnet agents)

**Goal:** a desktop app that plays *any* codec directly (no server transcode),
caches what you stream, downloads titles for offline, and stays in perfect
watch-party sync with web guests — reusing the existing React UI and backend.

**Stack:** Tauri v2 (Rust + system webview) hosting the existing `app/client`
React app, with **libmpv** for playback.

This document is the single source of truth. Every agent reads §1–§5, then
executes exactly one Agent Card. The IPC/adapter/backend **contracts in §4 are
frozen in Phase 0** — agents build against them in parallel, mocking the other
side where needed.

---

## 0. Decisions (locked with the product owner)

1. **Targets:** desktop only (macOS / Windows / Linux via Tauri). Mobile stays
   the existing web PWA — do NOT build native mobile. (Mobile browsers already
   hardware-decode HEVC; the codec pain is desktop-browser-only.)
2. **Relationship to web:** the native app is an **optional upgrade**, not a
   replacement. The web app remains the default (guests join by link, zero
   install). Native and web share ONE backend and ONE React codebase. A web
   guest and a native host must be able to sit in the same party.
3. **v1 scope (all four):** all-codec direct playback (mpv), progressive
   on-disk watch cache, explicit offline downloads (resumable), and full
   watch-party **sync preserved** in native.
4. **Dev/verify platform:** Linux (this is the dev box). Linux is the Phase-0
   spike + integration target. macOS/Windows packaging is a CI/later concern —
   write cross-platform-safe code, but only Linux must be proven in this plan.
5. **Downloads:** **multi-part** (parallel chunked byte-range connections per
   title, reassembled to one file). **Background via close-to-tray:** closing
   the window does NOT quit — the app keeps running in the system tray and
   downloads keep going; an explicit "Quit" exits. Partial downloads are
   persisted and **resume automatically** after any exit/crash. (True headless
   post-Quit downloading via a separate daemon is out of scope for v1 — the tray
   keeps the process alive, which covers "keeps going if I close the window".)

---

## 1. Architecture overview

```
┌──────────────────────────── Tauri window ─────────────────────────────┐
│  System webview (transparent where video shows)                        │
│    → existing React app (app/client)                                    │
│    → detects native via window.__TAURI__                                │
│    → renders the SAME redesigned minimal controls + party overlays      │
│      (camera tiles, chat) as DOM, over a transparent "video hole"       │
│    → useSyncPlay drives an MpvBackend (HTMLMediaElement duck-type)       │
│                          │ Tauri IPC (commands + events)                 │
│  Rust core (src-tauri)   ▼                                               │
│    → mpv module: libmpv instance rendering into the window BEHIND the    │
│      transparent webview (the "hole"); property-observe → JS events      │
│    → downloader: resumable Range fetch → Offline dir + manifest          │
│    → offline store: manifest of downloaded titles                        │
└─────────────────────────────────────────────────────────────────────────┘
        │ HTTPS (session cookie in webview; signed URL for mpv/downloader)
        ▼
   Existing Node/Express backend (unchanged except one new native endpoint)
        → NEW: signed short-lived URL to the ORIGINAL Jellyfin file
          (static, byte-range), so mpv/downloader can fetch without a cookie
```

**Why this works with minimal churn:**
- `useSyncPlay({ playerRef })` already treats `playerRef.current` as an
  HTMLMediaElement duck-type (`.currentTime` get/set, `.paused`, `.play()`,
  `.pause()`, `.playbackRate`, `.buffered`, `.addEventListener`). An
  **`MpvBackend` class implementing that exact surface over IPC is a drop-in** —
  the entire host-authority sync engine (`syncCore.js`, transport intent,
  buffer-aware seek) is reused verbatim. This is the linchpin.
- The redesigned minimal player controls (Player.jsx) already author transport
  through `requestPlay/Pause/Seek` and read `localPhase`/scrubber state from the
  media backend — they don't care whether the backend is `<HlsVideo>` or mpv.
- Source: instead of the HLS transcode proxy, native fetches a signed URL to the
  **original file** and hands it to mpv (which decodes anything). Zero transcode
  ⇒ zero buffering from CPU. Offline downloader uses the same signed URL.

---

## 2. The crux risk (read before planning any work)

The watch party renders **camera tiles, chat, and controls as DOM elements
layered OVER the video**. With mpv playing in a native surface (not an
`<video>` element), those DOM overlays must still composite on top. This is the
single hard problem and it can sink the naive approach.

**Chosen approach:** mpv renders into the Tauri window; the webview is made
**transparent** and sits *in front*; the video shows through a transparent
"hole" (a positioned div whose screen rect the frontend reports to Rust, which
sizes/places the mpv render region to match). DOM overlays over the rest of the
webview composite normally. Pointer events over the hole are handled by the
webview (controls) and only "click-through" when needed.

**Phase 0 MUST prove this on Linux** (WebKitGTK transparency + an mpv render
region behind it, with a DOM element visibly composited on top, resize +
fullscreen working). If transparent-webview compositing proves unworkable on a
target, the documented fallback is a **second always-on-top transparent overlay
webview** for controls/overlays above a full mpv window. Do not fan out Phase 1
until Phase 0 has demonstrated one working compositing path and frozen the
contracts.

Secondary risks to keep in mind: libmpv packaging per-OS (bundle vs system lib),
signed-URL auth for a process outside the cookie jar, and seek latency over IPC
vs the sync engine's timing assumptions (mitigate: the adapter emits
`seeking`/`seeked`/`timeupdate` faithfully from mpv property changes).

---

## 3. Repo layout (new code is mostly greenfield → low conflict)

```
desktop/
  src-tauri/
    Cargo.toml
    tauri.conf.json
    src/
      main.rs            # app bootstrap, window, registers commands
      ipc.rs             # command signatures (the frozen Rust contract)
      mpv.rs             # libmpv lifecycle, control, property-observe (N1)
      window.rs          # video-region bounds / fullscreen / transparency (N1)
      download.rs        # resumable downloader (N2)
      offline.rs         # offline manifest store (N2)
  package.json           # tauri CLI scripts (N7)
app/client/src/native/
  contract.ts            # MediaBackend interface + IPC names + event names (Phase 0)
  env.js                 # IS_NATIVE = !!window.__TAURI__ (Phase 0)
  MpvBackend.js          # HTMLMediaElement duck-type over IPC (N4)
  ipc.js                 # thin invoke()/listen() wrappers per contract (N4)
  offline/               # download button, Offline library view, progress (N6)
app/server/native.js     # signed original-file stream endpoint (N3)
```

Frontend edits to EXISTING files are limited to: `Player.jsx` (native branch,
owned by N5) and `app/server/index.js` (one route mount, owned by N3). Nothing
else shared → parallel worktrees stay conflict-free.

---

## 4. Frozen contracts (authored in Phase 0; do not change in Phase 1)

### 4.1 `app/client/src/native/contract.ts` — MediaBackend (duck-types HTMLMediaElement)

```ts
// The subset useSyncPlay + Player.jsx actually touch. MpvBackend implements
// this; the web path keeps using the real <HlsVideo> element (same surface).
export interface MediaBackend {
  // getters/setters
  currentTime: number          // seconds (get + set === seek)
  readonly duration: number     // seconds (NaN until known)
  readonly paused: boolean
  playbackRate: number
  volume: number                // 0..1
  muted: boolean
  readonly buffered: { length: number; start(i: number): number; end(i: number): number }
  // methods
  play(): Promise<void>
  pause(): void
  load(url: string, opts?: { startSec?: number; paused?: boolean }): void
  destroy(): void
  // events — MUST fire with the same names/semantics as HTMLMediaElement:
  //   'play' 'pause' 'seeking' 'seeked' 'timeupdate' 'waiting' 'playing'
  //   'ended' 'durationchange' 'ratechange' 'volumechange' 'loadedmetadata' 'progress'
  addEventListener(type: string, cb: (e?: any) => void): void
  removeEventListener(type: string, cb: (e?: any) => void): void
}
```

### 4.2 Tauri IPC — Rust `#[tauri::command]` names + payloads (contract in `ipc.rs`)

Playback (N1 implements):
- `mpv_load({ url: string, startSec: number, paused: boolean })`
- `mpv_play()` · `mpv_pause()` · `mpv_seek({ sec: number })`
- `mpv_set_speed({ rate: number })` · `mpv_set_volume({ vol: number })` · `mpv_set_muted({ muted: boolean })`
- `mpv_set_region({ x, y, w, h, dpr })` — position the video "hole" (device px)
- `mpv_set_fullscreen({ on: boolean })`
- `mpv_teardown()`

Events Rust→JS (Tauri `emit`, N1):
- `mpv:timepos` `{ sec }` (~4–10Hz) · `mpv:pause` `{ paused }` · `mpv:duration` `{ sec }`
- `mpv:seeking` · `mpv:seeked` `{ sec }` · `mpv:buffering` `{ active }` (cache underrun)
- `mpv:eof` · `mpv:loadedmetadata` `{ durationSec }` · `mpv:speed` `{ rate }`
- `mpv:cache` `{ cachedAheadSec, cachedBytes }` (drives `buffered` + `progress`)

Downloader (N2 implements) — multi-part, resumable, tray-backgrounded:
- `dl_start({ itemId, url, title, parts?: number })` → `{ id }` — `parts`
  defaults to a sensible concurrency (e.g. 4–8) when the server reports
  `Accept-Ranges: bytes` + a known length; falls back to a single stream
  otherwise.
- `dl_pause({ id })` · `dl_resume({ id })` · `dl_cancel({ id })`
- `dl_list()` → `[{ id, itemId, title, state, receivedBytes, totalBytes, parts }]`
  — `state ∈ queued|active|paused|done|error`. Survives relaunch (rehydrated
  from on-disk state), so this is the source of truth the UI reconciles to.
- events: `dl:progress` `{ id, receivedBytes, totalBytes, bytesPerSec }` (aggregate
  across parts, coalesced ~2–4Hz) · `dl:done` `{ id, itemId, path }` ·
  `dl:error` `{ id, message }`

App lifecycle (N7 wires; N2 relies on it):
- Closing the window hides to tray (process stays alive → downloads continue).
- `app_quit()` — real exit from the tray menu; flushes part-state to disk first.
- On launch, N2 rehydrates unfinished downloads and auto-resumes `active` ones.

Offline store (N2 implements):
- `offline_list()` → `[{ itemId, title, path, sizeBytes, addedAt }]`
- `offline_path({ itemId })` → `{ path } | null`
- `offline_remove({ itemId })`

### 4.3 Backend endpoint (N3 implements)

- `GET /api/library/native/stream-url/:itemId` (auth: existing session) →
  `{ url, expiresAt }`. `url` is an absolute URL to a **signed** local route
  that streams the ORIGINAL file with HTTP Range support.
- `GET /api/library/native/file?token=<hmac>` → proxies Jellyfin
  `/Videos/{itemId}/stream?static=true&mediaSourceId=…` using the server-held
  API key; validates the HMAC token (item + expiry) so no cookie is needed
  (mpv/downloader can fetch it). Mirrors the auth model of the existing
  `/api/library/hls/*` proxy. Supports `Range`/`206`.

### 4.4 Native detection

`app/client/src/native/env.js`: `export const IS_NATIVE = typeof window !== 'undefined' && !!window.__TAURI__`.

---

## 5. Parallelization model (git worktrees)

Base branch `native-v1` cut from `main`. **Phase 0 is a blocking spike + contract
freeze** — it must merge before Phase 1 fans out. Phase 1 agents branch from the
merged `native-v1`, own disjoint paths, and build against the §4 contracts
(mocking the counterpart side). Phase 2 integrates + verifies end-to-end.

```
git branch native-v1 main
git worktree add ../wt-<id> -b native/<id> native-v1   # per agent
```

### Phase 0 — `spike-contracts` (BLOCKING; likely needs interactive/human help for GUI)
**Owns:** new `desktop/**` scaffold, `app/client/src/native/{contract.ts,env.js,ipc.js-stub}`, an empty `app/server/native.js` stub + its route mount.
**Do:**
1. Scaffold Tauri v2 in `desktop/`, frontend pointed at `app/client` (dev: vite
   dev server; prod: `app/client/dist`). App boots showing the existing React UI.
2. **Prove the crux (§2)** on Linux: libmpv plays a local test file in a region
   behind a transparent WebKitGTK webview, with a visible DOM element composited
   on top, and `mpv_pause`/`mpv_seek` working over IPC. Resize + fullscreen ok.
   Document the working compositing path (or the overlay-webview fallback).
3. Write the FROZEN §4 contracts as code: the TS `MediaBackend` interface + IPC
   name/event constants, the Rust `ipc.rs` command signatures (bodies may be
   `todo!()`/stub), and the backend endpoint signatures (stub 501). 
**Acceptance:** `cargo build` + `tauri dev` launch on Linux; test video visibly
plays with a DOM overlay on top; contracts committed. A short SPIKE-NOTES.md
records the compositing approach and any per-OS caveats.

### Phase 1 — parallel (branch from merged `native-v1`)

**N1 — `rust-mpv`** · owns `desktop/src-tauri/src/mpv.rs`, `window.rs`, and the
mpv parts of `ipc.rs`/`main.rs` registration.
Implement libmpv lifecycle + all `mpv_*` commands + all `mpv:*` events + the
video-region/fullscreen/transparency handling from the Phase-0 approach. Map
mpv `demuxer-cache-state` → `mpv:cache` for `buffered`. Enable disk cache
(`cache=yes`, `cache-on-disk=yes`, `demuxer-cache-dir=<app cache dir>`) — this
delivers the "progressive watch cache" feature for free.
**Acceptance:** `cargo build`; manual smoke via `tauri dev` — load/play/pause/
seek/speed/volume/fullscreen all work; events fire; cache dir fills on playback.

**N2 — `rust-downloader`** · owns `desktop/src-tauri/src/download.rs`, `offline.rs`,
and their `ipc.rs` command registration.
**Multi-part, resumable** Range downloader: split the file into N parts by
byte-range, fetch them concurrently (bounded worker pool), write into a single
preallocated sparse file (or per-part temp files reassembled on completion).
Persist per-part progress to an on-disk state file (e.g. `<dest>.part.json`)
frequently enough that a crash/quit loses at most a few seconds, and resume each
part from its last committed offset. Detect Range support (`Accept-Ranges`,
`Content-Length`) and gracefully fall back to a single-connection stream when
the server won't range. On completion, `fsync`, move into the Offline dir, and
record it in the offline manifest (JSON). Implement all `dl_*`/`offline_*`
commands + `dl:*` events per §4.2. On startup, rehydrate the download set from
disk and auto-resume anything that was `active`. Because the app close-to-trays
(N7), in-flight downloads simply keep running; `app_quit` flushes state first.
**Acceptance:** `cargo build`; a large title downloads via multiple concurrent
parts (verify >1 connection), shows correct aggregate progress; pause/resume
works; killing the process mid-download and relaunching resumes from the
persisted offsets (not from zero); completed file is byte-correct (size + plays
in mpv) and appears in `offline_list`.

**N3 — `backend-stream`** · owns `app/server/native.js` + the single route mount
in `app/server/index.js`.
Implement §4.3: signed URL + the HMAC-validated Range-capable original-file
proxy using the server-held Jellyfin API key. Reuse the existing hls-proxy
auth/streaming patterns. Add `NATIVE_STREAM_SECRET` handling to env (document
it; fail-closed if missing in production). The proxy MUST handle **many
concurrent Range GETs for the same token** (the multi-part downloader opens
several at once) and correctly pass through `Content-Range`/`Content-Length`/
`Accept-Ranges`/`206`. The token embeds a `purpose` claim: `stream` (short TTL,
~a few hours, for playback) vs `download` (longer TTL sized for a full download,
or make `stream-url/:itemId` accept `?purpose=download`); a token near expiry
must be re-fetchable via the same endpoint so a long download can refresh
mid-flight (the Rust downloader re-invokes the frontend/endpoint for a fresh URL
on a 401/403).
**Acceptance:** `node --check`; with a running dev backend, `stream-url/:id`
returns a URL that streams original bytes with `206` on a Range request, serves
several simultaneous non-overlapping Range requests correctly, and returns
`401/403` on a bad/expired token.

**N4 — `mpv-adapter`** · owns `app/client/src/native/MpvBackend.js`, `ipc.js`.
Implement `MediaBackend` (§4.1) over the §4.2 IPC: getters/setters map to
commands, events map from `mpv:*`, `buffered` synthesized from `mpv:cache`,
`load()` fetches the signed URL (via N3's endpoint) then `mpv_load`. Build
against a mock `invoke`/`listen` so it's testable without Rust. Add unit tests
that feed synthetic `mpv:*` events and assert HTMLMediaElement-equivalent
behavior (e.g. a `mpv:seeked` fires a `seeked` event and updates `currentTime`).
**Acceptance:** `vite build`; `node --test` on the adapter's tests passes.

**N5 — `player-native-branch`** · owns `app/client/src/components/Player.jsx`.
When `IS_NATIVE`: render a transparent "video hole" stage (report its rect to
`mpv_set_region` on layout/resize/scroll) instead of `<HlsVideo>`, and pass an
`MpvBackend` instance as the `playerRef` to `useSyncPlay`. Keep the redesigned
minimal controls, party overlays, transport authoring, and prop signature
**identical** — the web (`<HlsVideo>`) path stays byte-compatible when not
native. Do NOT alter the sync/transport wiring. Build against N4's `MpvBackend`
public API (frozen in contract).
**Acceptance:** `vite build`; web mode renders exactly as today (no behavior
change when `!IS_NATIVE`); native branch is structurally wired (full runtime
verify happens in Phase 2 with real Rust).

**N6 — `offline-ui`** · owns `app/client/src/native/offline/**` + a small hook.
"Download" affordance on a title (native only), an Offline library view listing
`offline_list()`, live progress from `dl:*` events, remove action. Playback
prefers `offline_path(itemId)` over the stream URL. Match the redesigned
monochrome system. Build against mock IPC.
**Acceptance:** `vite build`; UI renders with mocked data; download states
(queued/active/paused/done/error) all represented.

**N7 — `tauri-packaging`** · owns `desktop/tauri.conf.json`, `desktop/package.json`,
build scripts, icons, updater config, CI stubs, and the **system-tray + window
lifecycle** wiring in `main.rs` (tray icon, menu with Quit, and the
window-close handler that hides-to-tray instead of exiting).
Dev workflow (`tauri dev` against vite), prod build (`tauri build` bundling
`app/client/dist`), libmpv bundling strategy per-OS (documented; Linux proven),
app metadata/icons, auto-update config stub, CI matrix stub for mac/win/linux
(not required green off-Linux). Tray behavior: window "close" → `hide()` +
tray-resident (process stays alive so N2's downloads continue); tray menu
"Quit" → real exit (fires `app_quit` so N2 flushes part-state); if any download
is `active` at Quit, show a confirm ("Downloads in progress will pause and
resume next launch — quit anyway?"). Coordinate the exact `app_quit`/close-hook
names with N2 via §4.2 (already frozen) — N7 owns the window/tray code, N2 owns
what runs on those hooks.
**Acceptance:** `tauri dev` + `tauri build` succeed on Linux producing an
AppImage/deb; closing the window keeps the app in the tray (verify a download
keeps progressing after window close); tray Quit exits cleanly; config
documented.

### Phase 2 — `integration` (BLOCKING, last)
1. Merge N1–N7 into `native-v1`.
2. Replace all mocks with real IPC/endpoints; wire N3's route; set the stream
   secret in the dev env.
3. **End-to-end verify on Linux:** (a) play an HEVC/x265 title with zero server
   transcode (confirm via backend logs no ffmpeg spawned); (b) seek back into
   already-watched region loads from disk cache, not network; (c) download a
   title and confirm it uses **multiple concurrent connections**, then **close
   the window and confirm the download keeps progressing from the tray**, then
   kill the process mid-download and relaunch to confirm it **resumes from the
   persisted offsets**; go offline and play the completed file; (d) **sync
   check** — a native host and a web guest in one party stay in sync through
   play/pause/seek (drive both, observe).
4. Run existing web regression: `cd app && node --test client/src/sync/*.test.js`
   (adapter must not have regressed the shared sync core) — all pass.
5. Confirm web-only users are completely unaffected (`IS_NATIVE` false path).
6. Package a Linux build; open PR `native-v1 → main`.

---

## 6. Definition of done (v1)
- Desktop app launches, shows the existing (redesigned) UI, logs in via the
  same session.
- Plays any codec directly (HEVC/AV1/etc) with no server transcode; seeking
  back reuses the on-disk cache.
- Download-for-offline is multi-part (parallel connections), continues while
  the window is closed (tray-resident), and resumes from persisted offsets after
  a full quit/crash; offline titles play with the backend unreachable.
- A native host and a web guest stay in sync in the same party.
- Web app + mobile PWA behavior is unchanged (shared codebase, `IS_NATIVE`
  guards the native-only paths).
- `vite build`, `cargo build`, `tauri build` (Linux) all pass; sync unit tests
  green; one PR to `main`.

## 7. Explicitly out of scope for v1
Native mobile (iOS/Android); macOS/Windows *signed* release builds (CI can come
later); in-app codec/settings beyond what mpv defaults give; P2P/local-network
transfer of downloaded files between devices.
