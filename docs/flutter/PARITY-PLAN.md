# Flutter 1:1 Parity Plan — match the redesigned web client

Status: PLAN (pre-implementation). Branch: `redesign-v3-flutter` (fast-forwarded to the
web redesign `ede37b7`, so it carries BOTH the redesigned web reference and the Flutter
client). Companion to `docs/flutter/PLAN.md` (original build) and
`docs/watchparty-design/README.md` (the authoritative design guide).

## Goal

The Flutter desktop client (`flutter_app/`) is functionally complete but was built to the
**old** design (dark-only monochrome, left nav rail, top window bar, 6 destinations, Hanken
Grotesk). The web client was since **redesigned** (`ede37b7`). This plan brings the Flutter
UI to **1:1 parity** with the redesigned web app while **preserving every functional
system** (playback, watch-party sync, LiveKit A/V, chat, downloads, servarr, auth). This is
a UI/layout re-skin, **not** a functional rewrite.

## Source of truth (in order)

1. `docs/watchparty-design/README.md` + its reference images (**design guide wins** on any
   conflict).
2. The redesigned web **code** (`app/client/src/…`) — the behavioral reference.
3. This plan's per-workstream briefs.

## Locked decisions

1. **Navigation:** match the web exactly — 4 bottom tabs **Movies · Shows · Discover ·
   Downloads**. Party → the bottom-right **popcorn** control (not a tab). **Offline** folds
   into Downloads. **Find/Acquire** folds into Discover.
2. **Fonts:** convert the bundled **Circular XX Web** `.woff2` → `.otf` and embed it.
3. **Conflicts:** where the shipped web code deviates from the design guide, the **design
   guide wins** (e.g. centered poster titles, no upward hover-translate).
4. **Branch:** work on `redesign-v3-flutter`.

## Global invariants (must not break — verified per workstream)

- media_kit playback + track selection; **never remount the player/VideoView**.
- Host-authority **sync engine** (drift/authority/applying-guard), Jellyfin ticks units,
  `{baseVersion,commandId}` optimistic concurrency.
- socket.io event names + REST paths stay **byte-identical to the server**.
- LiveKit room + mic/cam/hide-self toggles (guarded so device re-acquire never authors a
  spurious pause).
- Chat over socket; downloads (CacheFillController) + offline playback (on-device cache
  first); servarr request state machine + **release-cancel-exactly-once**.
- Auth: Jellyfin login, session-cookie persistence, auto-login, logout; guest-browse route
  gating.
- Party lifecycle: **Stop Movie (`party:backToLobby`) stays distinct from Stop Stream
  (`party:end`)**; host-only actions gated by `isHost`; collaborative control gated by
  `canControl = isHost || collaborativeControl`. Single app-wide non-autoDispose
  `partyProvider` — never remounted on navigation.
- Theme switching sits **above the shell chrome, below the functional providers** — it must
  not reset playback/party/socket/LiveKit/chat/download state.

## Workstreams (conflict-free file ownership)

Ownership is **disjoint within each wave** so wave-mates can run in parallel without
touching the same file. New files are marked `(new)`. Shared barrels
(`ui/ui.dart`, `state/providers.dart`, `state/state.dart`, `models/models.dart`) are owned
ONLY by W0/W1; W2 tasks import directly rather than editing barrels.

### Wave 0 — Foundation (parallel)

**F1 · Design system & shared widgets** — effort **high**
- Owns: `pubspec.yaml`; `flutter_app/assets/fonts/*`, `assets/popcorn.png`;
  `lib/ui/{tokens,theme,shadcn_theme,ui}.dart`; `lib/ui/palette.dart`(new);
  `lib/ui/theme_mode.dart`(new); `lib/state/theme_provider.dart`(new);
  `lib/ui/widgets/{ambient_wash(new),poster_card,poster_shelf(new),app_button,
  app_text_field,app_dialog,chip,empty_state,error_state,loading_skeleton,section_header,
  scrim}.dart`.
- Delivers: three persisted themes (Light default / Balanced / Dark) as ThemeData +
  `palette.dart`; Circular XX family + brand red; `AmbientWash` (Balanced artwork backdrop
  using the authed Jellyfin image API); `PosterShelf`/`PosterCard` primitives (horizontal,
  centered title, rating, subtle-larger-first, no upward hover-translate); all shared
  widgets theme-scoped. App still compiles and runs (dark remains one of the three modes).

**F2 · Contract coverage** — effort **medium**
- Owns: `lib/net/events.dart`; `lib/data/api_client.dart`.
- Delivers: add the socket event constants + REST methods the redesigned web uses that the
  Flutter client currently lacks (manual `.torrent` upload, `party:resume`, servarr
  enriched/detail endpoints, a body-carrying DELETE for blocklist-on-remove). No change to
  existing call signatures/behavior.

### Wave 1 — Shell (serial gate)

**S1 · App shell** — effort **xhigh**
- Owns: `lib/app/{app,router,shortcuts}.dart`; `lib/app/screens/app_shell.dart`;
  `lib/ui/widgets/{nav_rail(remove usage),global_party_bar(remove top strip),
  bottom_nav(new),profile_menu(new),popcorn_control(new)}.dart`;
  `lib/ui/widgets/party_widget.dart`(stub — completed by W2c).
- Delivers: edge-to-edge shell (no top bar / no left rail / no outer frame); bottom-centered
  4-tab nav with red active underline; top-right profile menu (Signed-in-as, ThemeSwitch,
  Sign out, notification dot); bottom-right popcorn control opening an expandable container;
  `AmbientWash` mounted behind content; frameless window drag/min/max/close without a top
  bar; full route table incl. new `/detail`, download-detail, servarr-detail routes pointing
  at existing/stub screens; guest gating + `partyProvider` continuity preserved; command
  palette + number shortcuts aligned to the 4-tab IA.
- Consumes F1.

### Wave 2 — Screens (parallel)

**W2a · Library & detail** — effort **high**
- Owns: `lib/app/screens/{home_screen,browse_screen,detail_screen,gallery_screen,
  media_row}.dart`; `lib/app/screens/detail_stage.dart`(new);
  `lib/ui/widgets/{still_card(new),view_card(new)}.dart`; `lib/state/library_provider.dart`.
- Delivers: Movies/Shows/Discover as horizontal shelves (never grids); movie detail =
  fullscreen backdrop + wash, genre eyebrow, Circular-Light title, synopsis, mono metadata
  row, Resume/Play pill + track button, right poster, bottom cast strip; show detail =
  season selector + episode dock + in-place episode selection. Consumes F1 shelf/card + S1.

**W2b · Login** — effort **medium**
- Owns: `lib/app/screens/login_screen.dart`.
- Delivers: theme-aware login matching the redesigned web composition; auth flow untouched.

**W2c · Watch party + in-playback chrome** — effort **xhigh** (sync-sensitive)
- Owns: `lib/app/screens/party_screen.dart`; `lib/state/party_provider.dart`;
  `lib/player/{player_chrome,player_view}.dart`;
  `lib/ui/widgets/{camera_grid,floating_camera_tile,chat_panel}.dart`;
  `lib/ui/widgets/party_widget.dart`(complete); `lib/ui/widgets/party_qr.dart`(new);
  `lib/ui/widgets/join_code_dialog.dart`(new).
- Delivers: popcorn expandable widget (create / join-by-code / QR / approve-reject /
  participant mgmt / host transfer / end); in-playback **right-click** party menu (+ a
  trackpad fallback), top-right AV toggles, camera/chat dock, **one** unified 3s auto-hide;
  **no** duplicate party pill. Preserves sync, `canControl`, StopMovie≠StopStream, and does
  not remount the player. Consumes F1 + S1 popcorn_control.

**W2d · Acquire (Discover/Find) + Downloads/Offline** — effort **high**
- Owns: `lib/app/screens/{servarr_screen,servarr_queue_screen,downloads_screen,
  offline_screen}.dart`; `lib/state/{servarr_provider,downloads_provider,
  offline_provider}.dart`; `lib/ui/widgets/download_button.dart`;
  `lib/ui/widgets/{download_ring(new),download_poster(new)}.dart`;
  `lib/app/screens/{download_detail_screen,servarr_detail_screen,servarr_release_picker,
  servarr_season_chooser,servarr_options_dialog}.dart`(new).
- Delivers: search-free Discover two-rail browse (folds Find/Acquire in); full acquire flow
  (release picker cancels exactly once; manual magnet/torrent; correct request bodies);
  Downloads poster-grid with progress rings + DownloadDetail overlay + needs-attention
  danger cards + delete-with-files; offline library folded into Downloads. Consumes F1 shelf
  + F2 api + S1 routes.

## Execution

- Parallel fan-out via the Workflow tool at **opus / xhigh** for the hard workstreams
  (S1, W2c), high for the rest. Disjoint ownership → same working tree, no worktrees.
- **Between every wave:** `flutter pub get` (after F1) → `dart run build_runner build` (if
  any codegen changed) → `flutter analyze` → fix compile errors → commit the wave. A wave
  does not start until the prior wave analyzes clean.
- Toolchain runs via the `redesign-v3-flutter` tmux session (Flutter lives in the real
  environment, outside the agent sandbox).

## Verification (verify-done gate)

Per `docs/flutter/VISUAL-QA.md`, on a display: login (root/root) → shell (bottom nav, 3
themes, ambient wash, popcorn) → library shelves + detail → player transport + auto-hide →
party (2-client sync, camera, chat, host controls) → downloads/offline → acquire flow. Plus
`flutter analyze` clean and `flutter build linux` succeeds.

## Known open items (non-blocking)

- Font licensing for embedding Circular XX in a desktop binary (assumed permitted).
- Theme persisted locally via shared_preferences (matches web per-device localStorage),
  key `watchparty-theme`, default `light`.
- Series detail has no local Jellyfin fixture — built against the web reference images.
- Ambient wash "selected title" source = library focus/hover (global current-artwork state
  introduced in F1).
