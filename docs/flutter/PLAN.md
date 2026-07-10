# Watchparty — Flutter Desktop App: Full Build Plan

Status: PLAN (pre-implementation). Supersedes the Tauri native effort
(`docs/native/PLAN.md`) for the desktop client. The **backend is unchanged and
fully reused**.

---

## 0. Decisions (locked)

- **Stack:** Flutter (Dart) desktop app.
  - **`media_kit`** (+ `media_kit_video`, `media_kit_libs_video`) — libmpv-based
    all-codec playback rendered into the Flutter widget tree via GPU texture.
    This retires the entire Tauri embedding problem (X11 child window / EGL /
    `set_region` / z-order) — the package owns it, cross-platform.
  - **`livekit_client`** — native `libwebrtc` (via flutter-webrtc), so camera/mic
    WebRTC **works** (the WebKitGTK dead-end that killed Tauri A/V is gone).
  - **`socket_io_client`** — same sync signaling protocol as today.
- **Backend: reused as-is.** Node/Express (`app/server`), the signed native
  stream proxy (`native.js`), Jellyfin, LiveKit server, servarr stack, socket.io.
  No server rewrite. New server work is additive only (a LiveKit-token endpoint
  if one isn't already exposed for native, and confirming `NATIVE_STREAM_SECRET`).
- **Why not Tauri/Electron:** Tauri = no WebRTC on WebKitGTK. Electron keeps the
  React UI but still needs a player embed and ships Chromium. Flutter solves BOTH
  hard problems (all-codec + WebRTC) with mature packages; cost is a Dart UI
  rewrite, accepted.
- **State management:** Riverpod. **Routing:** go_router. **HTTP:** dio (+
  cookie jar for the session cookie). **Downloads:** `background_downloader`
  (resumable, background, survives restart). **Storage:** shared_preferences +
  flutter_secure_storage.
- **Design language:** the shipped cinematic-minimal system — monochrome
  (near-black `#0a0a0b` → near-white `#F4F4F5`), single muted red `#E0655E` for
  danger/live only, no gradients, no glass. Ported to Flutter `ThemeData`.
- **Scope v1:** desktop (Linux first, then Win/macOS). Feature parity with the
  web app EXCEPT nothing is dropped — all-codec direct play, watch-party sync,
  LiveKit A/V, chat, offline downloads, servarr management.
- **Platform target order:** Linux → Windows → macOS. Mobile (Flutter) is a
  future unification, out of v1 scope.

---

## 1. Architecture

```
┌────────────────────────── Flutter app (Dart) ──────────────────────────┐
│  UI (widgets, screens)  ── Riverpod providers ── go_router              │
│        │                        │                                       │
│   Design system         ┌───────┴─────────┬──────────────┬───────────┐  │
│                         │                 │              │           │  │
│                    PlayerController   SyncEngine    LiveKitRoom  Downloader│
│                    (media_kit)        (host-auth)   (livekit)   (bg_dl)  │
│                         │                 │              │           │  │
│                    ApiClient (dio) ── SocketClient (socket_io_client)    │
└─────────────────────────────┬──────────────────────────────────────────┘
                              │ HTTPS + WSS  (Tailscale / prod origin)
┌─────────────────────────────┴────────────────────────────────────────┐
│  EXISTING backend (unchanged): Express /api, native stream proxy,      │
│  socket.io sync, LiveKit token, servarr proxy · Jellyfin · LiveKit srv │
└────────────────────────────────────────────────────────────────────────┘
```

- **All-codec direct play:** media_kit opens the signed
  `/api/library/native/stream-url/:itemId` → absolute `…/native/file?token=`
  URL. Original file, Range, **no transcode** (server side already verified).
- **Sync:** `SyncEngine` drives `PlayerController` from socket.io events using
  the same host-authority algorithm as the web `useSyncPlay`.
- **A/V:** `livekit_client` joins the room with a backend-issued token.
- **Offline:** `background_downloader` pulls `purpose=download` signed URLs in
  resumable parts; media_kit opens the local file when present.

---

## 2. De-risk spike (GATE — do this before any epic work)

A 1–2 day spike on THIS Linux box that must go green before the plan proceeds:

- **S1 — playback:** bare Flutter Linux app, media_kit opens a signed
  `native/stream-url` for a real Jellyfin title, renders video in a widget,
  seek works, and server logs show **Range requests to `/native/file`, no
  transcode**.
- **S2 — A/V:** same app joins the existing LiveKit room with a backend token,
  publishes camera+mic, and shows/【hears】a second (web) participant.

If S1+S2 pass, embedding + WebRTC risk is retired and the rest is "just" UI +
integration. Owner: **Opus** (single spike task). Everything below is gated on it.

---

## 3. Frozen contracts (Phase 0 output — the parallelization backbone)

Agents build against these interfaces + mock implementations, so epics run in
parallel without colliding. Phase 0 delivers them as **compiling Dart with mock
impls**; concrete impls are filled by the owning epics.

1. **Models** (`lib/models/`, freezed + json): `User`, `LibraryItem`,
   `MediaSource`, `MediaStream`, `PartyState`, `Participant`, `ChatMessage`,
   `DownloadRecord`, `OfflineRecord`, `StreamUrl{url,expiresAt}`.
2. **`ApiClient`** (`lib/data/api_client.dart`, abstract): `login`, `me`,
   `logout`, `home`, `items`, `item`, `search`, `imageUrl`,
   `nativeStreamUrl(itemId, {purpose})`, `livekitToken(room)`, servarr calls.
   Concrete `DioApiClient` handles the session cookie.
3. **`PlayerController`** (`lib/player/player_controller.dart`, abstract):
   `open(url,{startAt,autoplay})`, `play`, `pause`, `seek`, `setRate`,
   `setVolume`, `setAudioTrack`, `setSubtitle`, `dispose`; streams: `position`,
   `duration`, `buffering`, `playing`, `completed`, `tracks`. (Mirrors the
   HTMLMediaElement duck-type the sync engine needs.) media_kit impl in E4.
4. **`SyncEngine`** (`lib/sync/sync_engine.dart`, abstract): consumes a
   `PlayerController` + `SocketClient`; host-authority. E5 implements.
5. **`SocketClient`** (`lib/net/socket_client.dart`): typed wrappers over the
   **existing** socket.io event names (reuse `app/server` event contract
   verbatim — document the event list in `lib/net/events.dart`).
6. **Design tokens + core widgets** (`lib/ui/`): `AppTheme`, color/space/type
   tokens, `AppButton`, `AppTextField`, `PosterCard`, `NavRail`, `Scrim`,
   `LoadingSkeleton`, `AppDialog`. E1 fills; others consume the API.
7. **Router** (`lib/app/router.dart`): route names + go_router config with
   placeholder screens.
8. **Providers** (`lib/state/`): `authProvider`, `libraryProvider`,
   `partyProvider`, `playerProvider`, `downloadsProvider`, `livekitProvider`,
   `chatProvider` — interfaces + mock state, real logic filled by epics.

Rule: an epic may only change files it owns + append to shared barrels; contract
signatures are frozen after Phase 0 (change = update the contract + both sides).

---

## 4. Epics

Each epic is independently testable. Tasks within an epic run in parallel.
**Model: Sonnet unless marked `[OPUS]`** (reserved for timing/embedding-critical).

### Phase 0 — Foundation `[OPUS]` (gate)
One focused task: scaffold the Flutter project, pubspec deps, DI/Riverpod root,
router skeleton, **all frozen contracts + mocks** (§3), theme skeleton, and a
`DioApiClient` with working session-cookie auth against the backend.
**Test:** app boots to a mock home; `flutter test` green; `flutter build linux`
succeeds. Everything else depends on this.

### E1 — Design System & App Shell
- **T1.1** Theme: port cinematic-minimal tokens → `ThemeData` (dark, monochrome,
  no gradients), text styles, danger/live red.
- **T1.2** Core widget library (buttons, inputs, cards, dialogs, skeletons,
  poster) + a `/gallery` dev screen.
- **T1.3** App shell: nav (Home/Browse/Downloads), window chrome, responsive
  layout, route transitions.
**Test:** gallery renders all components in golden tests; navigate between shells.

### E2 — Auth & Session
- **T2.1** Login screen + `authProvider` (Jellyfin login, session persist,
  auto-login, logout) on `DioApiClient`.
- **T2.2** Route guards / redirects, error + loading states.
**Test:** log in `root/root` against backend, session survives restart, logout.

### E3 — Library & Browse
- **T3.1** Home (sections, latest, continue-watching).
- **T3.2** Search + browse grid + filters.
- **T3.3** Title detail (metadata, poster, Play, Download hook).
- **T3.4** Image loading/caching via `/api/library/image`.
**Test:** browse real Jellyfin library, search, open detail.

### E4 — Video Playback (core)
- **T4.1 `[OPUS]`** `MediaKitPlayerController`: implement the `PlayerController`
  contract on media_kit; video widget; open signed `native/stream-url`
  (no transcode); audio/subtitle track selection; buffering/error states.
- **T4.2** Player chrome: minimal transport bar, scrubber, volume, fullscreen,
  track menus — matching the redesign's minimal player.
- **T4.3** Quality/track UI, keyboard shortcuts, error recovery.
**Test:** play a title, seek, switch audio/subs, fullscreen; server logs confirm
Range/no-transcode.

### E5 — Watch Party Sync
- **T5.1 `[OPUS]`** Port host-authority sync (`useSyncPlay` → Dart `SyncEngine`)
  over `PlayerController` + `SocketClient`; drift correction, applying-guard,
  play/pause/seek authority. Timing-critical.
- **T5.2** `SocketClient` + party create/join, participant list, host controls,
  `canControl` permission gating, "Stop Movie" vs "Stop Stream".
- **T5.3** Party screen layout: player + docked (non-overlapping) side panels.
**Test:** native client + web guest stay in sync (play/pause/seek); host
authority holds; a no-control guest can't disrupt playback.

### E6 — LiveKit A/V
- **T6.1** `livekit_client` room: join with backend token, publish camera/mic,
  subscribe remote tracks, device selection, mute/cam/hide-self toggles.
- **T6.2** Camera tile grid UI (participant tiles, talking indicator, layout
  modes), docked beside the player.
**Test:** join room, see+hear a second participant, toggle mic/cam — the exact
thing Tauri could not do.

### E7 — Chat
- **T7.1** Chat over socket.io (send/receive, rate-limit UX) + chat panel UI.
**Test:** send/receive messages in a party.

### E8 — Downloads & Offline
- **T8.1** Resumable multi-part downloader (`background_downloader`) on
  `purpose=download` signed URLs; pause/resume/cancel; survives app restart;
  background.
- **T8.2** Offline library + download button + progress UI.
- **T8.3** Offline playback: media_kit opens the local file when present.
**Test:** download a title, kill+reopen app → resumes, play offline with network
off.

### E9 — Servarr Management
- **T9.1** Find/Download screen: search sources, list releases, grab — via
  `/api/servarr/*`.
- **T9.2** Downloads/queue monitor (radarr/sonarr queue + active).
**Test:** search a movie → see sources → request → appears in queue/library.

### E10 — Packaging & Distribution
- **T10.1** Linux AppImage/deb/flatpak; bundle libmpv + webrtc native libs.
- **T10.2** Single-instance, window-state persistence, close-to-tray, updater.
- **T10.3** Windows + macOS build matrix (after Linux is solid).
**Test:** install on a clean machine → launches → plays a title + joins a party.

---

## 5. Execution waves (parallelism)

- **Wave 0:** Spike (§2) → **Phase 0 Foundation** `[OPUS]`. Serial gate.
- **Wave 1 (parallel):** E1 (T1.1–1.3), E2, **E4.1 `[OPUS]`**, **E5.1 `[OPUS]`**,
  E8.1, concrete `DioApiClient` hardening. Build against Phase-0 mocks.
- **Wave 2 (parallel):** E3, E4.2/4.3, E5.2/5.3, E6, E7, E8.2/8.3, E9. The bulk
  of the UI — all Sonnet, all against frozen contracts.
- **Wave 3:** E10 packaging + full integration + E2E (native host ↔ web guest,
  offline, servarr) via the tauri-mcp-equivalent Flutter driver / manual.

Worktree strategy: same as before — one git worktree per task, disjoint file
ownership, frozen contracts as the seam. Integrate wave-by-wave into `flutter-v1`.

---

## 6. Model assignment summary

**Opus (dire only — 4 tasks):**
- Spike (media_kit + livekit proof).
- Phase 0 Foundation (contracts + arch + DI + cookie auth).
- E4.1 media_kit `PlayerController`.
- E5.1 host-authority sync engine port.

**Sonnet:** everything else (all UI, auth, library, player chrome, LiveKit tiles,
chat, downloads, servarr, packaging) — ~20 tasks.

---

## 7. Risks

- **media_kit Linux packaging** — libmpv bundling for AppImage (known, has docs).
- **livekit_client desktop native libs** — bundle webrtc `.so`; verify on clean box.
- **Sync-engine fidelity** — the web `useSyncPlay` is subtle; port must preserve
  drift/authority behavior (that's why E5.1 is Opus + has a 2-client test).
- **Dart UI rewrite volume** — the cost we accepted; mitigated by frozen widget
  contracts + parallel Sonnet fan-out.
- **Backend gaps** — confirm a native LiveKit-token endpoint exists (add if not);
  `NATIVE_STREAM_SECRET` must be set in the deployed container.
