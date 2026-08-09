# Spec — Ambient rooms and a persistent player

**Date:** 2026-08-09
**Branch:** branches from `feat/youtube-replaces-browser`, merges after it
**Status:** draft, awaiting approval

Turn the app into a single-user streaming app that you can open a room on top of
at any moment, from anywhere, without leaving what you were doing.

## The problem, as found in the tree

Three things are wired as *navigation* that should be *state*:

**1. The room is a place you go.** `/party/:id` is a top-level route **outside**
the `AppShell` (`router.dart:123`). Being in a room means losing the nav rail,
the library and every other surface in the app.

**2. Guests are locked out of their own app.** `app_shell.dart:184` wraps the
whole shell in `IgnorePointer` whenever `party != null && party.hostId != me`. A
guest cannot scroll, switch tabs, or open settings. This is the single largest
cause of "rooms are complicated".

**3. The player is a screen, not a component.** `PlayerView` is mounted in
exactly two places — `DetailScreen:365` (solo) and `PartyScreen:465` (party) —
each inside its own full-window `Scaffold`. Pressing Back does not minimise
playback, it destroys it. Picture-in-picture is not an addition to this; the
player has to stop being a route first.

## The model

Everything that belongs to the room **floats over the app you are already in**.
A movie is a tile in the same sense a person is a tile.

```
┌──────────────────────────────────────┐
│ ░ │  Movies   Shows   Discover  …    │   ░ nav rail — always there
│ ░ │  ┌────┐ ┌────┐ ┌────┐            │
│ ░ │  └────┘ └────┘ └────┘   ┌──────┐ │   the movie, playing,
│ ░ │                         │  ▶   │ │   draggable and resizable
│ ░ │              ●  ●  ●    └──────┘ │   ● people, same treatment
│ ░ │                              🍿  │   popcorn — always there
└───┴──────────────────────────────────┘
```

You keep browsing, change the movie, open a show, change your settings. Nothing
takes over the screen except a movie you deliberately expanded.

## User stories

### US-1 — Start a room from anywhere (P1)

**Independent test:** from the Movies grid, start a room; the grid is still on
screen, still scrollable, and the popcorn shows the room.

- **Given** any screen in the app, **when** I start a room from the popcorn,
  **then** I stay exactly where I am and nothing navigates.
- **Given** I am in a room, **when** I browse to Shows, Discover or Downloads,
  **then** the room is unaffected — nobody is disconnected and nothing pauses.

### US-2 — A guest is not a spectator (P1)

**Independent test:** join a room as a guest; scroll the library, switch tabs,
open settings. All of it works.

- **Given** I am a guest in a room, **when** I use any part of the app, **then**
  it responds normally.
- **Given** I am a guest, **when** the host picks a title, **then** playback
  starts for me without moving me off what I was looking at.

### US-3 — Back minimises, it does not stop (P1)

**Independent test:** play a title full-screen, press Back, browse to another
tab. The movie keeps playing in a floating tile the whole time.

- **Given** a title playing full-screen, **when** I press Back, **then** it
  shrinks to a floating tile and keeps playing at the same position.
- **Given** a floating movie tile, **when** I tap it (or its expand control),
  **then** it returns to full-screen at the position it reached.
- **Given** a floating movie tile, **when** I close it, **then** playback stops
  — and in a room, only for me unless I am the driver ending the title.

### US-4 — The popcorn is the room (P2)

**Independent test:** every room action is reachable from the popcorn with no
other surface open.

- **Given** any screen, **when** I open the popcorn, **then** I can start, join,
  leave or end a room, see who is in it, and answer join requests.
- **Given** somebody asks to join, **when** I am anywhere in the app, **then**
  the request reaches me without navigating me.

## Functional requirements

### The player becomes a component

- **FR-001** Playback MUST be owned above the router, so it survives every
  navigation. Exactly ONE player instance exists per client at a time; solo and
  party playback MUST NOT be two mountings of `PlayerView`.
- **FR-002** The player MUST have two presentations over one instance:
  **expanded** (full-window) and **floating** (a draggable, resizable tile).
  Switching between them MUST NOT reload the media, drop the position, or
  interrupt audio.
- **FR-003** Back / Escape from expanded MUST go to floating, not to stopped.
- **FR-004** The floating player MUST reuse `FloatingTileGeometry` — the same
  clamp, cascade, snap and resize rules the camera tiles already use and test —
  so a movie tile and a person tile behave identically.
- **FR-005** Closing the floating player MUST stop playback for that client only.
  In a room, only a driver ending the title changes it for everyone.
- **FR-006** The expanded player MUST keep everything it has today: transport,
  subtitles, tracks, trickplay, fullscreen, sync chrome.

### The room becomes ambient

- **FR-010** The `/party/:id` route MUST be removed. Joining, creating or being
  pulled into a room MUST NOT navigate.
- **FR-011** The `IgnorePointer` guest lockout in `app_shell.dart` MUST be
  removed. A guest's app MUST be fully interactive at all times.
- **FR-012** A room MUST be startable from any screen, with no title selected,
  and MUST NOT require or imply one.
- **FR-013** Camera tiles, the movie tile, chat and the popcorn MUST render above
  every routed screen, on every screen, including detail pages.
- **FR-014** Room membership MUST survive navigation: no disconnect, no
  re-join, no A/V renegotiation when the user changes tabs.
- **FR-015** Selecting a title in a room MUST start playback for every member
  without navigating any of them.

### The popcorn is the room's surface

- **FR-020** The popcorn MUST be present on every authenticated screen, mounted
  once above the router rather than per-screen (it is currently mounted three
  times: `app_shell.dart:207`, `detail_screen.dart:80`, and the party screen).
- **FR-021** Every room action MUST be reachable from it: create, join by code,
  leave, end, roster, approve/reject, invite link, sync mode, collaborative
  control, A/V reconnect.
- **FR-022** Join requests MUST reach the host wherever they are, without
  navigation.
- **FR-023** Host-only actions MUST NOT be offered to a guest, on any client.

### Host-view mirroring is removed

- **FR-025** `browse:navigate`, `browse:view`, `browse:pointer` and
  `browse:state` MUST be removed from the server, both clients and the shared
  socket contract.
- **FR-026** `app/client/src/mirror.ts`, `MirrorPoint`, `PartyBrowse`,
  `session.browse` and `canDriveBrowse` / `browseAuthority` MUST be removed,
  along with every `partyBrowsing` branch in the web stages.
- **FR-027** **`browseCore.ts` MUST NOT be touched.** It is the shared browse
  *interaction* core — rail window geometry, stepped scroll, season artwork,
  focus memory — pinned by cross-language parity tests against Dart. It reads as
  mirroring-adjacent and is not. The same applies to `analog/surface.ts` and
  `focus_memory.dart`.
- **FR-028** After removal, every member of a room browses their own app freely.
  A room shares playback, chat and A/V, and nothing else.

### What stays personal

- **FR-030** Offline downloads, profile, and app settings are personal. A
  download saves to my device only and is never mirrored, announced, or driven
  by anyone else.
- **FR-031** Whether my player is floating or expanded is personal. Nobody
  else's window changes because I minimised mine.

## Success criteria

- **SC-001** From any screen, starting a room leaves the current screen visible
  and interactive.
- **SC-002** A guest can use every part of the app while in a room. No pointer
  blocking anywhere, on either client.
- **SC-002b** No `browse:*` event, `mirror.ts` import or `canDriveBrowse` call
  remains; `browseCore.ts` and its parity tests are untouched and still pass.
- **SC-003** A title plays continuously across at least three navigations,
  including into and out of a detail page, with no reload and no position loss.
- **SC-004** Back from expanded reaches floating in under 300 ms with no audio
  gap.
- **SC-005** Every room action is reachable from the popcorn with nothing else
  open.
- **SC-006** No route in the app renders the popcorn twice or zero times.
- **SC-007** Suites at or above baseline: Flutter 432, web 428, server 111,
  `tsc --noEmit` clean.
- **SC-008** Playback sync, chat and A/V behave exactly as they do today. This
  is a re-housing, not a protocol change.

## Out of scope

- **Building any screen mirroring** — pseudo-cursors, collaborative selection,
  following the host's navigation. Dropped after discussion, and the existing
  machinery is deleted rather than left dormant (FR-025..FR-028).
- Shared external content. The browser was removed; YouTube was set aside.
- Changing the sync engine, the schedule model, or the socket protocol beyond
  what removing the party route requires.
- Re-housing the web client's player and party route. Flutter first; see
  "Web parity" below.

## Assumptions

- **A-1** The server's `lobby` / `watching` stages stay as they are. With no
  lobby screen, `lobby` simply means "no title selected" — it still drives the
  sync engine correctly, and changing it would touch the protocol for no gain.
- **A-2** Removing the `browse:*` channel is a web-visible behaviour change:
  guests there currently follow the host's library navigation and will stop. That
  is the intent, not a regression.
- **A-3** `FloatingTileGeometry` is correct as built and needs generalising to a
  second tile kind, not redesigning. Its rules are already unit-tested.
- **A-4** Mounting persistent chrome in `MaterialApp.builder` puts it above the
  Navigator — which is what makes it survive navigation, and also means it
  paints above dialogs and menus. The player and camera tiles want that; the
  popcorn's own menus need checking against it (known trap, HANDOFF §4).
- **A-5** One player instance means solo and party playback share a controller.
  The party path already drives `PlayerView` through a shared controller
  provider, so this is a consolidation rather than a new mechanism.
- **A-6** Removing `/party/:id` removes `_syncBrowserSurface`-style forced
  navigation entirely; nothing else in the app pulls a user to a route.

## Web parity — decided

Split by layer, not by client:

- **Protocol changes go everywhere.** Removing `browse:*` (FR-025..FR-028)
  touches the server, so the web client loses host-view following in this work
  too. There is one server; it cannot be half-migrated.
- **The re-housing is Flutter-first.** The persistent player, PiP and the
  ambient room are Flutter only. `Party.tsx` and `WatchView` keep their current
  shape for now and get the same treatment in a later spec, once this one has
  proven the shape.

Rejected: doing both clients at once. It roughly doubles the work and risks the
live web client on a design that has not been used yet.

## Risks

- This moves the two most stateful things in the app (playback, LiveKit) out of
  the widgets that currently own their lifecycle. Teardown is where this will
  break: `_leaveLocal` guards each step precisely because a half-completed
  teardown once left cameras live. Every one of those paths needs re-verifying
  against an owner that no longer disappears with a route.
- `PartyScreen` is ~2,500 lines and holds the auto-hide controller, the chat
  slide-over, the control panel, join requests and the device rail. Deleting the
  route means finding a home for each, and some of them are genuinely screen
  chrome with no obvious new owner.
