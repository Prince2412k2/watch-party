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

### T6 — Delete `/party/:id`, re-home its chrome (FR-010, FR-013) — IN PROGRESS

**Done:** the keystone. `PlayerHost` now carries every party prop the party's
own `PlayerView` carried (canControl, canManagePartyMedia, partyPlayback,
subtitle preferences, track selection, PTT, chat toasts, sync-authored seeks),
plus the auto-hide controller. There is no longer a second player to delete.

**Remaining, in this order — each step must land before the next:**

1. Extract `_JoinRequestsLayer`, `_ChatSlideOver` and the camera layer out of
   `party_screen.dart` into a `PartyOverlay` widget, mounted at the root beside
   `PlayerHost`. **Do this BEFORE removing the route**: today they render only
   inside `PartyScreen`, so removing the route first would leave a room with no
   cameras and no chat.
2. Remove `_openParty` / `partyPlayerRoute` forced navigation from
   `app_shell.dart` (it drags the user onto `/party/:id` whenever a room starts
   watching) and `partyMinimizedProvider`, which only exists to fight it.
3. Remove the `/party/:id` route from `router.dart` and delete
   `party_screen.dart`.
4. `_HostControlsDialog` and `_DeviceRail` move to the popcorn (folds into T7).
5. `party_minimize_test.dart` tests the navigation latch being removed and will
   need rewriting against the new model.

`_LobbyStage`, `_WaitingRoom`, `_PartyEntry` and `_Connecting` are deleted
outright: a room with no title selected shows nothing but its tiles.


`PartyScreen` is ~2,500 lines. Its parts, and where each goes:

| Part | New home |
|---|---|
| `PlayerView` mount | gone — T4 owns it |
| `FloatingCameraLayer` | root layer, beside `PlayerHost` |
| `_ChatSlideOver` | root layer |
| `_HostControlsDialog` | opened from the popcorn |
| `_JoinRequestsLayer` | root layer (already an overlay) |
| `_DeviceRail` | popcorn |
| `_WatchChrome`, `_autoHide` | into `PlayerHost` — it is player chrome |
| `_LobbyStage`, `_WaitingRoom`, `_PartyEntry`, `_Connecting` | deleted; a room with no title shows nothing but its tiles |
| `_MediaPickerSheet`, `pickAndSwitchPartyMedia` | keep, called from the popcorn |

Also removes `createFromCurrentPlayback`'s `context.go('/party/$id')` and the
forced-navigation path in `party_provider`.

**Verify:** create, join, pick a title, chat, A/V — all without navigating.

### T7 — Popcorn mounted once (FR-020..FR-023)

Currently three mounts (`app_shell.dart:207`, `detail_screen.dart:80`, party
screen). Move to the root layer; delete the others. Add the control panel,
device rail and sync-mode entries.

**Verify:** SC-006 — no route renders it twice or zero times.

## Ordering rationale

T1 and T2 are pure deletions that stand alone and de-risk the rest. T3–T5 make
playback survive navigation without touching the router. T6 is the big one and
depends on all of them. T7 is cleanup that only makes sense once T6 has freed
the chrome.

## Not in this plan

Web re-housing (spec: "Web parity — decided"). T1 touches web because the
protocol changes; nothing else does.
