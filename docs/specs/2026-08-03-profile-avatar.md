# Profiles — display name and a drawn avatar

Status: implemented
Surface: web client (`app/client`), Express server (`app/server`)

Implementation: `app/server/profile.js` (validation + routes), `app/server/profile-store.js`
(storage), `publicMember`/`effectiveName` in `app/server/session.js` (sharing),
`app/client/src/lib/avatar.ts` (derived defaults), `app/client/src/components/Avatar.tsx`,
`app/client/src/pages/Profile.tsx` (editor). One deviation from the requirements is
recorded under "Where avatars appear" below.

## Problem

A participant who doesn't turn their camera on is a pair of grey initials. That's the
common case — most people in a party have their camera off most of the time — so the
room reads as a list of placeholders rather than people. There is also no way to be
called anything other than your Jellyfin account name, which is often a login handle
(`root`) rather than a name anyone uses.

Humation renders hand-drawn SVG avatars locally from a seed or explicit part/colour
selections, with no network calls and no image generation. It gives us a way to make
the camera-off state feel populated, and a profile worth having a page for.

## User stories

### US-1 — Nobody is faceless (P1)
As a participant with my camera off, I appear as a distinctive drawn avatar rather than
grey initials, without having configured anything.

*Independent test:* join a party with the camera off from a brand-new account that has
never opened the profile page; a plausible, non-default-looking avatar appears for you
on every other participant's screen.

- **Given** I have never customised anything, **when** I join a party with my camera
  off, **then** I am shown as a drawn avatar derived from my account.
- **Given** two different accounts, **when** both appear with cameras off, **then**
  their avatars differ from each other.
- **Given** the same account on a different device or after a restart, **when** I
  appear, **then** my avatar is identical to before.

### US-2 — Choose how I look (P1)
As a user, I open a profile page and change my avatar's parts and colours, and what I
save is what everyone sees.

*Independent test:* change hair and skin colour, save, and confirm the new avatar
renders on a second participant's screen in the same party.

- **Given** I am on the profile page, **when** I pick a different part for a slot,
  **then** the preview updates immediately.
- **Given** I have made changes, **when** I save, **then** my avatar changes everywhere
  it appears, for everyone.
- **Given** I have made changes, **when** I leave without saving, **then** nothing
  changes.
- **Given** I have customised my avatar, **when** I ask to reset it, **then** it returns
  to the automatic one derived from my account.

### US-3 — Be called what I want (P1)
As a user, I set a display name that replaces my Jellyfin account name wherever people
see me.

*Independent test:* set a display name, and confirm it appears in the participant list
and on the camera tile for another participant, while login still uses the Jellyfin
account.

- **Given** I have set no display name, **when** anyone sees me, **then** my Jellyfin
  account name is used.
- **Given** I set a display name, **when** anyone sees me, **then** the display name is
  used instead.
- **Given** I clear my display name, **when** anyone sees me, **then** it falls back to
  my Jellyfin account name.
- **Given** I set a display name, **when** I sign in again, **then** I still
  authenticate as my Jellyfin account (the display name is not a credential).

### US-4 — Recognise people around the room (P2)
As a participant, the people in the party are represented by their avatars in the places
they're currently represented by initials.

*Independent test:* with three participants (cameras off), the camera-off tiles, the
collapsed camera circles, and the participant list all show each person's avatar.

- **Given** a participant has their camera off, **when** I look at their tile, **then**
  I see their avatar.
- **Given** I have collapsed someone's tile to a circle, **when** I look at it, **then**
  I see their avatar.
- **Given** I open the participant list, **when** I look at a row, **then** I see that
  person's avatar.
- **Given** a participant turns their camera ON, **when** I look at their tile, **then**
  I see live video, not the avatar.

### US-5 — Find my profile (P2)
As a user, I reach my profile from where account things already live, on desktop and on
phone.

*Independent test:* from a cold load on each of desktop and phone, reach the profile
page without typing a URL.

- **Given** I am on any main screen, **when** I open the account menu, **then** it
  offers my profile.
- **Given** I am on the profile page, **when** I go back, **then** I return where I came
  from.

## Functional requirements

**Identity and storage**
- FR-001: A profile MUST consist of an optional display name and an optional avatar
  configuration, stored per user account and surviving restarts.
- FR-002: A profile MUST NOT affect authentication. Jellyfin remains the sole source of
  identity; a display name is presentation only and MUST NOT be usable to sign in or to
  impersonate another account.
- FR-003: The system MUST expose a user's own profile to them for reading and writing.
- FR-004: A user MUST NOT be able to write another user's profile.
- FR-005: Display names MUST be constrained: trimmed, length-limited, single-line, and
  rejected (falling back to the account name) when empty after trimming.
- FR-006: An avatar configuration MUST be validated against the installed asset set on
  write; unknown part identifiers or malformed colours MUST be rejected rather than
  stored.

**Defaults**
- FR-007: Every user MUST have a usable avatar with no configuration, derived
  deterministically from their stable account identifier.
- FR-008: The derived default MUST vary plausibly across users in both parts AND
  colours. The asset set's built-in colour defaults render every avatar with the same
  pure-white skin, so colour MUST be derived rather than left at its defaults.
- FR-009: Derived colours MUST come from a curated set of plausible skin, hair, and
  clothing tones — not arbitrary values from the full colour space.
- FR-010: The same account MUST derive the same default avatar on every client and
  across sessions.
- FR-011: A saved avatar configuration MUST take precedence over the derived default.
- FR-012: A user MUST be able to discard their saved configuration and return to the
  derived default.

**Sharing within a party**
- FR-013: A participant's display name and avatar MUST be visible to everyone in the
  same party.
- FR-014: Party membership data sent to clients MUST continue to expose only the fields
  clients need. Adding profile fields MUST NOT widen it to anything else, and MUST NOT
  expose authentication tokens, socket or device identifiers, or any other internal
  member state.
- FR-015: A profile change MUST reach the other participants of a party the user is
  currently in, without them reloading.
- FR-016: Profiles MUST NOT be readable by users who share no party with the subject,
  beyond the account name already visible to them today.

**Where avatars appear**
- FR-017: Where a participant is currently represented by initials, they MUST be
  represented by their avatar instead: the camera tile for a participant with no video,
  the collapsed camera circle, and the participant list.
- FR-018: A live camera feed MUST take precedence over the avatar.
- FR-019: The signed-in user's own account control MUST show their own avatar.
- FR-020: Avatars MUST render without network requests, so they still appear when the
  connection is degraded.
- FR-021: An avatar used to convey who someone is MUST carry that person's name as its
  accessible label.

> **Deviation, FR-017 (camera tiles).** The floating camera grid deliberately renders a
> tile only for a participant whose camera is actually on (`CameraGrid.tsx`, "Bug 5" —
> camera-off participants used to leave blank placeholder tiles on screen). A camera-off
> participant is therefore represented by their avatar in the participant list, the
> collapsed circle, and any tile that loses its video while mounted — but no tile is
> created for someone who simply never turned their camera on. Resurrecting placeholder
> tiles would undo that earlier fix, so it was left alone; US-1's independent test reads
> on the participant list rather than the grid. Revisit together if camera-off tiles are
> wanted after all.

**The profile page**
- FR-022: The profile page MUST offer a live preview, per-slot part selection for every
  slot the asset set defines, colour selection for every colour slot it defines, an
  explicit save, and a reset to the derived default.
- FR-023: The page MUST read the available parts and slots from the installed asset set
  rather than a hardcoded list, so an asset-set update does not silently drop options.
- FR-024: Saving MUST report success or failure; a failed save MUST NOT silently appear
  to have worked.
- FR-025: The page MUST be usable at phone width.

## Success criteria

- SC-001: A brand-new account that has never opened the profile page appears as a drawn
  avatar, not initials, with no setup.
- SC-002: Across ten different account identifiers, the derived avatars differ from one
  another and none renders with the asset set's default pure-white skin.
- SC-003: The same account identifier produces a byte-identical avatar on two different
  clients.
- SC-004: A saved avatar and display name are visible to another participant in the same
  party without that participant reloading.
- SC-005: A saved profile survives a full server restart.
- SC-006: The data a client receives about other party members contains no field beyond
  those required to render them — specifically no tokens or internal identifiers.
- SC-007: One user cannot alter another user's profile.
- SC-008: A display name never becomes a way to authenticate.
- SC-009: Turning a camera on replaces that participant's avatar with live video, and
  turning it off restores the avatar.
- SC-010: Avatars still render with the network offline after first load.
- SC-011: Every part slot and colour slot the installed asset set defines is reachable
  in the editor.
- SC-012: An invalid avatar configuration submitted directly to the server is rejected,
  not stored.

## Out of scope

- **The Flutter desktop/mobile app.** Humation is a JS/React renderer with embedded SVG
  artwork; Flutter cannot consume it directly. Flutter clients keep showing names and
  initials. Accepted consequence: a party mixing web and Flutter clients shows avatars to
  the web users and initials to the Flutter users for the same participant. This is
  cosmetic and only visible in mixed parties. A server-side SVG endpoint (Humation runs
  in Node) was considered and rejected for now — it adds an endpoint plus caching, needs
  Flutter work, and re-introduces a network dependency for something otherwise entirely
  local. Display names, unlike avatars, ride along on existing party membership data, so
  Flutter picks those up for free.
- Uploaded or photographic profile pictures. The avatar is drawn from the asset set only.
- Avatars on chat messages. Chat currently renders names; adding avatars there is a
  follow-up, not part of making the camera-off state feel populated.
- Profile fields beyond a display name and avatar (bio, pronouns, links, status).
- A user directory, profile browsing, or viewing the profile of someone you share no
  party with.
- Moderation of display names beyond mechanical constraints (length, whitespace,
  single-line).
- Retroactively rewriting a display name into already-sent chat messages.
- Per-party nicknames. The display name is one global value per account.
- Any change to how authentication works.

## Assumptions

- The stable account identifier already shared with other party members is a suitable
  avatar seed, so the default avatar needs no stored state and no server write — every
  client can derive the same avatar for anyone it can already see. Only customisation
  needs storing.
- Storing profiles alongside the existing party persistence is appropriate; this is a
  small amount of durable per-user data, not a new subsystem.
- "Plausible skin tones" means a small curated range spanning light to deep, chosen so
  no user is assigned an implausible colour by default. Users who want something else
  customise; the default aims to be unremarkable rather than expressive.
- Deriving default colours from the same identifier that drives part selection is
  acceptable, and preferable to asking every new user to pick a skin tone before they
  can appear (which would block "nobody is faceless" and add onboarding friction to a
  purely aesthetic feature).
- A display name limit of roughly 32 characters is enough for real names and short
  handles while keeping participant lists and camera-tile name rows legible.
- The participant list and camera tiles are the surfaces that matter; the join-request
  rows in the host's approval sidebar can adopt avatars if it falls out cheaply, but the
  requester's profile may not be loaded at that point and it is not required.
- The asset set version is pinned by the lockfile, so "same seed, same avatar" holds in
  practice; an intentional asset-set upgrade may change everyone's derived default, which
  is acceptable for an aesthetic feature.
- No migration is needed: users with no stored profile are exactly the default case.

## Open questions

None — the Flutter/cross-client scope question was resolved in the Phase 1 interview
(web only; see Out of scope). Everything else is recorded as an assumption.
