# Plan — Ambient rooms and a persistent player

Spec: `docs/specs/2026-08-09-ambient-rooms.md`
Branch: `feat/ambient-rooms`, off `feat/youtube-replaces-browser`

## What the tree already gives us

Three facts found before planning, each of which shrinks the work:

1. **`playerControllerProvider` is already a global singleton**
   (`state/player_provider.dart:9`). Media, audio and position already survive
   navigation. What kills playback is `DetailScreen.dispose()` →
   `_stopPlayback()` → `pause()` + `seek(0)` — an explicit choice, with a
   `_handoffToParty` flag that already opts out of it.
2. **`MaterialApp.builder` already hosts chrome above the router**
   (`app/app.dart:55`): `AnalogToastHost` and `ChatNotifications` live there
   because the party socket outlives every screen. The player layer mounts in
   the same place for the same reason.
3. **`FloatingTileGeometry`** (`ui/widgets/floating_camera_tile.dart:17`) is a
   pure, unit-tested clamp/cascade/snap/resize model. The movie tile reuses it
   rather than inventing a second one.

So this is mostly a **re-housing**: move ownership of the video surface and the
party chrome from routes to a root layer. Very little new behaviour.

## Global constraints

- **Playback must not restart.** Any change that reloads the media, drops the
  position or gaps the audio is a failure, not a detail.
- **One `PlayerView` mount.** Two mounts is the bug being fixed; do not add a
  third "mini player" widget.
- **`browseCore.ts` / `surface.ts` / `focus_memory.dart` are untouchable**
  (FR-027). They are the shared interaction core, not mirroring.
- **Teardown is the risk.** `_leaveLocal` guards each step because a
  half-finished teardown once left the camera live. Anything moved out of a
  route's lifecycle needs its teardown re-verified.
- Baseline to hold: Flutter 432, web 428, server 111, `tsc` clean.

## Tasks

Ordered so each lands independently and the app works after every one.

### T1 — Remove host-view mirroring (FR-025..FR-028)

Self-contained deletion across all three surfaces, same shape as the browser
removal.

- Server: `browse:navigate`, `browse:view`, `browse:pointer`, `browse:state`
  handlers; `session.browse`; the contract fixture entries.
- Web: `mirror.ts`, `MirrorPoint`, `PartyBrowse`, `isMirrorPoint`,
  `canDriveBrowse`/`browseAuthority`, `navigateBrowse`/`shareView`/`sendPointer`
  on the context, and every `partyBrowsing` branch in the stages.
- Flutter: the `browse*` event constants; `BrowseState` on `PartyState`.
- **Not** `browseCore.ts`, `surface.ts`, `focus_memory.dart`, or the rail /
  stepped-scroll parity tests.

**Verify:** all suites at baseline minus deleted tests; no `browse:` string
outside `browseCore`-family files.

### T2 — Unlock the guest's app (FR-011)

Delete the `IgnorePointer` / `sharedHostView` block in `app_shell.dart:166-186`.

**Verify:** a widget test that a guest-party shell renders no `IgnorePointer`
with `ignoring: true`.

### T3 — `nowPlayingProvider`: playback becomes state

New `state/now_playing_provider.dart`:

```dart
enum PlayerPresentation { hidden, floating, expanded }

class NowPlaying {
  final String? itemId, mediaSourceId, title;
  final int? audioStreamIndex, subtitleStreamIndex;
  final PlayerPresentation presentation;
  final bool fromParty;
}
```

Notifier API: `open(...)`, `expand()`, `minimise()`, `close()`. `close()` is the
ONLY thing that pauses and seeks to zero. Nothing else stops playback.

**Verify:** unit tests — `minimise()` never touches the controller; `close()`
pauses and seeks; `open()` on a new item supersedes the old.

### T4 — `PlayerHost`: one mount, above the router

New `player/player_host.dart`, mounted in `app.dart`'s builder inside
`AnalogToastHost` and outside the router. Renders nothing when `hidden`; renders
the single `PlayerView` inside an `AnimatedPositioned` that interpolates between
the full-window rect (`expanded`) and a `FloatingTileGeometry` tile
(`floating`).

**Verify:** widget test that the `PlayerView` element identity is preserved
across an expand↔minimise transition (the assertion that proves the media does
not reload).

### T5 — `DetailScreen` delegates instead of mounting

Play calls `nowPlaying.open(..., expanded)` rather than swapping to its own
player `Scaffold`. `dispose()` no longer stops playback. `PopScope` minimises.
Removes the local `_isFullscreen`/`_stopPlayback`/`_exit` machinery.

**Verify:** navigate away mid-playback → position keeps advancing.

### T6 — Delete `/party/:id`, re-home its chrome (FR-010, FR-013) — DONE

Landed in two commits, in the order the risk demanded.

**First**, `PartyOverlay` (`lib/party/party_overlay.dart`), mounted at the root
beside `PlayerHost` and wrapping it, so a room's cameras and chat render on top
of the film including while it is full-window. It carries the floating camera
layer, the join-request notification, the LiveKit error banner and the chat
drawer, and renders nothing at all without a party — which is what makes it safe
to wrap every screen in the app. Chat's open state moved to
`chatDrawerOpenProvider` outright, since the drawer and the screen no longer
share a tree. This had to land BEFORE the route went, or a room would have spent
a commit with no cameras and no chat.

**Then** the route and the 1,921-line screen. `partyPlayerRoute` became
`partyWatchingItemId`: it names a title instead of a route, and `AppShell` opens
it into `nowPlayingProvider` over whatever screen you are on. `partyMinimizedProvider`
is gone — minimising is a property of the player now, so "minimized away from the
party surface" is not a state that can exist. The guard that remains ignores the
room repeating its current title on every heartbeat while letting a genuinely new
title take the screen.

Survivors moved to `lib/party/party_controls.dart`: `HostControlsDialog`, the
media picker + `pickAndSwitchPartyMedia`, `DeviceRail`. The panel opened on a
right-click over the party stage and would have gone unreachable with it, so it
hangs off the popcorn now. Ending a party no longer navigates to `/home` — there
is nowhere to leave, so the film stops and you stay where you were.

Deleted outright: `_LobbyStage`, `_WaitingRoom`, `_PartyEntry`, `_Connecting`,
the docked camera column, `_RoomCodePill`, and the icon scrim that existed for a
Back button on a screen that is gone. `party_minimize_test.dart` tested the
navigation latch and had nothing left to assert; its subject — Back must not end
the room — is structural now.

### T7 — Popcorn mounted once (FR-020..FR-023) — DONE

Mounted in `app.dart`'s builder above both `PartyOverlay` and `PlayerHost`, and
deleted from `app_shell.dart` and `detail_screen.dart`. It carries its own
`Overlay`: `MaterialApp.builder` wraps the Navigator rather than living inside
it, so nothing above that point has one, and the tray's tooltips and dialogs
need it. The Watch Party panel is wired in as a tray button.

**Verified:** SC-006 asserted in `widget_test.dart` — exactly one `PopcornControl`
on boot and after navigating.

## Ordering rationale

T1 and T2 are pure deletions that stand alone and de-risk the rest. T3–T5 make
playback survive navigation without touching the router. T6 is the big one and
depends on all of them. T7 is cleanup that only makes sense once T6 has freed
the chrome.

## Not in this plan

Web re-housing (spec: "Web parity — decided"). T1 touches web because the
protocol changes; nothing else does.
