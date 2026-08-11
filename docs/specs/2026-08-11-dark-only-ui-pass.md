# Dark-only UI pass

- **Date:** 2026-08-11
- **Branch:** feat/ambient-rooms
- **Scope:** `flutter_app/` (desktop Flutter client) only
- **Status:** Draft — awaiting approval

## Context

Five UI defects/requests, grouped because they share one root: the theme system.

A fresh Windows install renders the sign-in screen unreadable (`docs/white-mode-issue.png`):
white scaffold behind dark cards, dark text on dark. Root cause is proven:

- `flutter_app/lib/state/theme_provider.dart:16` defaults `AppThemeMode` to `light`.
- `flutter_app/lib/ui/tokens.dart` and `flutter_app/lib/ui/analog_tokens.dart` are
  **dark-only by design** (their own doc comments say so). Every widget still reading
  `AppColors.*` / `AnalogColor.*` instead of `context.wp` stays dark regardless of mode.

So light mode is half-implemented, defaults on, and no one uses it. Removing it is
cheaper and safer than completing it.

## User stories

### US-1 — Readable app on a fresh install (P1)

**As** a user launching a freshly installed build,
**I want** the interface to render in one consistent dark theme,
**so that** text and controls are legible without changing any setting.

*Independent test:* wipe `shared_preferences`, launch, observe the sign-in screen.

- **Given** no persisted theme preference, **when** the app starts, **then** the dark
  palette is applied and all sign-in text meets contrast requirements.
- **Given** a profile with `watchparty-theme` persisted as `light` or `balanced`,
  **when** the app starts, **then** it renders dark and the stale value is discarded.

### US-2 — Legible chat notifications (P1)

**As** a viewer in a watch party,
**I want** incoming chat notifications on a solid background showing who sent them,
**so that** I can read them over bright video without squinting.

*Independent test:* trigger a chat message while a bright scene plays; read the toast.

- **Given** a chat message from another participant, **when** the toast appears,
  **then** it shows the sender's avatar beside their name and message on a fully
  opaque background.
- **Given** any video content behind the toast, **when** the toast is visible,
  **then** no video luminance shows through the toast surface.

### US-3 — Comprehensible subtitle picker (P2)

**As** a viewer choosing subtitles,
**I want** tracks named in plain language,
**so that** I can pick the right one without knowing container codec identifiers.

*Independent test:* open the subtitle menu on media with PGS and SRT tracks.

- **Given** a track whose codec is `HDMV_PGS_SUBTITLE`, **when** the picker lists it,
  **then** the row reads as a language plus a human-readable format, never the raw
  codec identifier.
- **Given** the picker is open, **when** it renders, **then** rows have comfortable
  height and padding and sit on a solid background.

### US-4 — Mute beneath the volume bar (P3)

**As** a viewer adjusting audio,
**I want** the mute button directly under the volume slider,
**so that** the audio controls are one group.

*Independent test:* open the player, look at the right-edge volume control.

- **Given** the player chrome is visible, **when** I look at the volume hairline,
  **then** a mute toggle sits immediately beneath it.
- **Given** mute has moved, **when** I inspect the bottom transport row,
  **then** no second mute control remains.

## Functional requirements

### Theme removal

- **FR-001:** The app MUST support exactly one theme (dark). `AppThemeMode` MUST no
  longer expose `light` or `balanced`.
- **FR-002:** The app MUST NOT present any theme-switching control. The cycling
  `TrayButton` in `lib/ui/widgets/profile_menu.dart:136-145` MUST be removed.
- **FR-003:** On startup, a persisted `watchparty-theme` value of `light` or `balanced`
  MUST resolve to dark without error, and MUST NOT crash on an unknown value.
- **FR-004:** `kLightPalette` and `kBalancedPalette` MUST be deleted from
  `lib/ui/palette.dart`; `WpPalette` MUST remain as the token carrier so `context.wp`
  call sites are unaffected.
- **FR-005:** The ambient artwork wash MUST remain functional; its opacity MUST be
  retuned for dark being the only mode (see Assumptions A-2).
- **FR-006:** `docs/watchparty-design/README.md` MUST be updated so the Themes section
  and the anti-regression checklist describe a single dark theme.

### Notifications

- **FR-007:** The app-wide toast surface MUST render on a fully opaque background
  (alpha = FF), replacing the `LiquidGlass` `BackdropFilter` plate in
  `lib/analog/chrome/analog_toast.dart`.
- **FR-008:** Chat toasts MUST continue to show the sender's `AvatarView`, sender name,
  and message preview in that order.
- **FR-009:** The in-player toast stack (`lib/analog/player/analog_toast_stack.dart`)
  MUST also render on a solid background and MUST show the sender avatar, matching the
  app-wide rail.
- **FR-010:** Toast tone colours (info/success/warning/danger) MUST remain
  distinguishable against the new solid surface.

### Subtitle picker

- **FR-011:** Subtitle rows MUST NOT display raw codec identifiers. `_trackDetail`
  (`lib/player/player_chrome.dart:2189-2199`) MUST map known codecs to readable format
  names and omit the detail entirely when it carries no information.
- **FR-012:** `_trackName` (`player_chrome.dart:2166-2187`) MUST fall back to a
  human-readable string (e.g. "Track 2") rather than a raw track id.
- **FR-013:** Picker rows MUST have increased height and padding relative to the
  current `_ChoiceRow`, and the popup MUST render on a solid background.
- **FR-014:** The "Off" option and the subtitle-file upload affordance MUST both remain
  reachable, with the upload action labelled rather than icon-only.

### Volume controls

- **FR-015:** The mute toggle MUST render directly beneath the volume track
  (`AnalogVolume`, `showMuteButton: true`).
- **FR-016:** The duplicate mute `_ChromeIconButton` in `_TransportBar`
  (`player_chrome.dart:1590-1594`) MUST be removed.
- **FR-017:** Existing mute keyboard shortcuts and semantics labels MUST keep working.

### Transparency

- **FR-018:** UI surfaces that carry text or controls MUST be opaque: menus, popovers,
  dialogs, toasts, the subtitle picker, settings popovers, and the chat drawer.
- **FR-019:** Deliberate cinematic transparency MUST be preserved: artwork scrims,
  backdrop gradients, the bottom navigation, player-chrome auto-hide fades, and
  animation opacity transitions.
- **FR-020:** `Colors.transparent` used as a no-op sentinel (ripple suppression,
  `surfaceTintColor`, unselected-state fills) MUST be left alone — it is not a
  readability defect.

## Success criteria

- **SC-001:** A fresh install with cleared preferences renders a dark, fully legible
  sign-in screen; all text/background pairs meet WCAG AA (4.5:1 body, 3:1 large).
- **SC-002:** No theme-selection control exists anywhere in the UI.
- **SC-003:** A profile carrying `watchparty-theme=light` launches dark without error.
- **SC-004:** Every text-bearing overlay surface listed in FR-018 has alpha = FF.
- **SC-005:** The subtitle picker shows no string matching `/_?(PGS|SUBRIP|ASS|SSA|
  DVD)_?SUBTITLE/i` for any track.
- **SC-006:** Exactly one mute control exists in the player, positioned beneath the
  volume track.
- **SC-007:** `flutter analyze` reports no new issues; existing widget tests pass.
- **SC-008:** The analog-token parity test still passes (generated file byte-identical
  to generator output).

## Out of scope

- The web client (`app/client/`) — keeps its three themes; no CSS changes.
- Completing the `AppColors`/`AnalogColor` → `context.wp` migration beyond what
  FR-018 requires.
- Refactoring the four duplicated backdrop-gradient implementations into a shared
  helper.
- Merging the app-wide toast rail and the in-player toast stack into one system —
  they stay separate paths per the existing design note.
- OS-level system notifications.
- Any change to playback, sync, party, or Jellyfin behaviour.

## Assumptions

- **A-1:** "Remove white mode" means dark-only, dropping Balanced as well as Light —
  confirmed with the user. The design guide is updated to match rather than left stale.
- **A-2:** Dropping Balanced would lose the mode where ambient artwork is strongest
  (`ambientOpacity: 1.0` vs dark's `0.42`), undercutting the in-flight `feat/ambient-rooms`
  work. Assumption: dark's `ambientOpacity` is raised toward the Balanced value so the
  ambient feature keeps its intended presence. Exact value tuned visually during
  implementation.
- **A-3:** Notifications are in-app Flutter overlays, not OS notifications — confirmed.
  The existing `AnalogToastHost` already carries avatar + name + message, so this is a
  surface-material change, not a new system.
- **A-4:** "Every component that uses transparent color" is read as "every component
  whose transparency hurts readability", not a literal sweep — confirmed. A literal
  sweep would remove artwork scrims and the bottom nav that the design guide requires.
- **A-5:** `lib/ui/analog_tokens.dart` is generated from
  `app/shared/design/analog-tokens.json`; token changes go to the JSON and the
  generator is re-run, never hand-edited.
- **A-6:** Persisted `watchparty-theme` keys are left in storage rather than actively
  migrated; the loader ignores unknown/removed values and returns dark.
