# Watch Party for YouTube

<!-- impeccable:product-schema 1 -->

## Scope

This record covers the YouTube browser extension in `app/client/extension/`.
The repository also contains web and Flutter apps; they provide shared services,
components, and behavioral references, but their broader product requirements are
outside this record. The user confirmed this scope during initialization.

## Platform

web

## Users

Friends watching together privately. A host starts a party and shares an invite;
guests join to watch, talk, and react together. The user confirmed this audience.
Guests should not need an account or a technical setup process to participate.

## Product Purpose

Make watching YouTube with friends feel like a shared activity while each person
watches directly on YouTube. Success means friends can join easily, stay on the
same shared page and playback timeline, and communicate without the controls
getting in the way of the video.

## Operating Context

- The extension runs on YouTube pages and connects to a Watch Party server.
  The configured default is `https://watch.sniffkin.tech`.
- Hosts validate an administrator login through extension Settings, create a
  party, and share its invite code. Administrators can also join by code.
- Guests enter an invite code without needing a Jellyfin account or password.
- The host browses YouTube normally. Guests follow the shared page; authorized
  controllers can also change playback and the shared page.
- Chat, voice, and camera feeds accompany the video. Fullscreen viewing and
  hiding a panel should preserve the active party and its communication state.

## Capabilities and Constraints

- Chrome/Edge require version 133 or newer. Safari distribution requires Xcode
  conversion to a Safari Web Extension and browser permission grants.
- Only one tab per extension profile owns the active party connection.
- Shared playback includes play/pause, seeking, speed, page following, and sync
  policies for keeping playback moving or waiting for everyone to recover.
- Hosts can grant or revoke playback control, remove guests, and transfer host
  ownership. The server enforces authority.
- Chat supports text, quoted replies, emoji insertion, a small searchable
  reaction-GIF collection, and HTTPS GIF links. Rich messages require the matching
  backend support; do not describe the collection as a general GIF search engine.
- Guest avatars use the web app's shared, identity-seeded generation. Logged-in
  accounts use their saved profile avatar when available. Identity should remain
  consistent across chat, participant controls, and camera placeholders.
- Panels and floating cameras share the owner's React/Socket.IO/LiveKit state.
  Opening another panel must not create a second room or media connection.
- Ending a party invalidates its invite code. Disconnecting or closing the owning
  tab ends the party for a host and leaves it for a guest. An unrelated tab closing
  must not affect the party. Guest credentials are cleared on departure.
- Save reusable authentication tokens, not passwords. Failed credential validation
  must not overwrite previously saved settings.
- Custom servers require HTTPS, with HTTP exceptions for local development.

## Brand Commitments

- Existing product name: Watch Party; extension name: Watch Party for YouTube.
- The user explicitly requests a minimal, smooth, unobtrusive interface.
- Confirmed idle behavior: after three seconds without pointer movement, extension
  chrome disappears. Open chat and participant feeds remain visible. A closed chat
  with unread messages keeps an icon-only notification launcher visible until read.
- The user rejected the prior interface as clunky and requested a complete overhaul;
  do not treat the v0.5 layout and styling as a binding visual system.
- `/root/watchparty/watch_party_refined.html` was supplied as a reference for
  placement and behavior only, not for visual styling. It is an external local
  reference, not a repository asset or a deployable application.
- Keep interface copy direct and functional. Preserve the existing product mark
  and reuse the shared avatar system rather than creating a separate identity set.

## Product Principles

1. Make joining easy for a friend who has no account or setup knowledge.
2. Keep attention on the shared video; reveal secondary controls when needed.
3. Preserve communication and party continuity through panel and fullscreen changes.
4. Make host authority and guest permissions understandable and enforceable.
5. Keep each person's identity consistent across the shared experience.

## Evidence on Hand

- Extension implementation and installation details: `app/client/extension/README.md`.
- Shared avatar derivation: `app/shared/avatar-derive.js` and
  `app/client/src/lib/avatar.ts`; renderer: `app/client/src/components/Avatar.tsx`.
- Server party behavior: `app/server/index.js` and `app/server/session.js`.
- Extension regressions: `app/client/extension/test/` and extension source tests.
- Server extension integration: `app/server/extension.integration.test.js`.
- Automated browser checks have exercised isolated two-user flows. This does not
  establish manual Safari compatibility or guarantee reliability on real networks.
- No confirmed usage metrics, customer endorsements, pricing, or performance
  benchmarks were supplied. Future work must not invent them.

## Open Decisions and Known Gaps

- Guest disconnect/reconnect behavior has been reported. Earlier investigation
  did not establish a confirmed root cause; do not treat it as resolved.
- A manual macOS Safari end-to-end pass is still needed.
- Public communities, monetization, and large-group product requirements are not
  established by this brief.
