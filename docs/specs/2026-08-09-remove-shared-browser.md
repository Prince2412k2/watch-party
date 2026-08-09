# Spec — Remove the shared browser

**Date:** 2026-08-09
**Branch:** `feat/youtube-replaces-browser`
**Status:** draft, awaiting approval

Delete the containerised shared browser in full — container, server module, both
clients, both compose files, docs and the party stage — with **no replacement**.

## Context

The shared browser is a containerised Chromium that publishes its own screen into
the party's LiveKit room as a publish-only participant. It costs **5,472 lines**
across five surfaces, and re-encodes an entire browser into a video stream to
show what is usually one video.

It was built to answer this, from `docs/specs/2026-08-04-remote-browser.md`:

> A party can only watch what is in the Jellyfin library. Anything else — a
> YouTube video, a clip someone linked in chat, a livestream — means everybody
> opens it separately and tries to press play at the same time.

**That use case is being dropped, deliberately and for now.** A YouTube
replacement was specified and then set aside; the next work is native-to-native
mirroring instead. This spec records the removal only, so the deletion is not
blocked on a replacement that is no longer being built.

## What must survive

The single easiest mistake here is deleting the mirroring channel along with the
browser. They look adjacent and are not.

`mirror.ts`, `browse:navigate`, `browse:view` and `browse:pointer` are the
**library** mirroring system — host-authority browse state replicated to guests
as semantic state, with scroll as a 0..1 fraction and cursor position as
fractions of the shared pane's bounding rect. They have nothing to do with the
container, and they are the foundation of the native-to-native sync work that
follows. They stay.

## User stories

### US-1 — The browser is gone (P1)

**Independent test:** a case-insensitive search for `vbrowser`, `shared.browser`
and `BROWSER_` returns nothing across `app/`, `flutter_app/`, `browser/`, both
compose files and `.env.example`; the app builds and prod deploys clean.

- **Given** a party persisted with `stage: 'browser'`, **when** the server
  restores it, **then** it opens in `lobby` rather than erroring.
- **Given** a client built before this change, **when** it emits a browser socket
  event, **then** the server ignores it without crashing.

### US-2 — Nothing else regressed (P1)

**Independent test:** all four suites at or above baseline; a party can still be
created, joined, and can watch a Jellyfin title with sync, chat and A/V.

- **Given** the library browse surface, **when** the host navigates or scrolls,
  **then** guests still follow — mirroring is untouched.

## Functional requirements

- **FR-001** The `browser/` container directory MUST be deleted in full
  (Dockerfile, `agent.py`, `target_agent.py`, `network.py`, `entrypoint.sh`,
  seccomp profile, `policy.json`, `publisher/`, `extra-ca/`, `test_agent.py`).
- **FR-002** `app/server/browser/` MUST be deleted in full, including
  `service.js`, `service.test.js` and `storage.test.js`, and every import, route,
  socket handler and lease reference removed from the rest of the server.
- **FR-003** `app/client/src/components/SharedBrowser.tsx` and all its call sites
  MUST be deleted, along with any browser-only types, guards and state.
- **FR-004** `flutter_app/lib/models/shared_browser.dart` and
  `state/shared_browser_provider.dart` MUST be deleted, along with their call
  sites in `party_screen.dart`, `party_provider.dart` and `popcorn_control.dart`.
- **FR-005** The browser services, networks and volumes MUST be removed from
  **both** `docker-compose.yml` and `docker-compose.prod.yml`, and every
  `BROWSER_*` variable removed from `.env.example`.
- **FR-006** The `VPS_PUBLIC_IP` local-interface assertion in `deploy/up-prod.sh`
  MUST remain. It was added in the same commit that deployed the browser stack
  (`507f186`) but is unrelated to it — it guards coturn advertising an address
  the host does not own.
- **FR-007** `docs/ops/shared-browser.md`, `docs/specs/2026-08-04-remote-browser.md`
  and `docs/specs/2026-08-04-remote-browser-spike.md` MUST be deleted, and
  `HANDOFF.md` MUST lose its browser sections.
- **FR-008** The `'browser'` party stage MUST be removed from the session model.
  A persisted session carrying `stage: 'browser'` MUST restore as `lobby`; the
  existing mapping at `session.js:95` MUST be kept as the migration path.
- **FR-009** `session.browser` MUST be removed from the session object and from
  every serialised payload sent to clients.
- **FR-010** Browser socket events arriving from an older client MUST be ignored
  without throwing, for the length of one deploy cycle.
- **FR-011** `mirror.ts`, `browse:navigate`, `browse:view`, `browse:pointer`,
  `partyAuthority.ts` and `browseCore.ts` MUST NOT be modified or removed.
- **FR-012** No dead export, unused import, orphaned type or unreferenced env var
  may remain after the deletion.

## Success criteria

- **SC-001** Net deletion of at least 5,000 lines.
- **SC-002** Case-insensitive search for `vbrowser`, `shared.browser`, `BROWSER_`
  and `browser-control` returns no production hits outside `node_modules`,
  `package-lock.json` and unrelated words such as `browserslist`.
- **SC-003** Suites at or above baseline: Flutter 432, server 151, web 430, minus
  only the deleted browser tests; `tsc --noEmit` clean; `flutter analyze` clean
  (run with the pane cwd set, per HANDOFF).
- **SC-004** A party can be created, joined, and can watch a Jellyfin title with
  working sync, chat and A/V.
- **SC-005** Library browse mirroring still works host-to-guest.
- **SC-006** Prod deploys from `main` with no browser services and no orphaned
  networks or volumes left behind.

## Out of scope

- Any replacement for shared external content. YouTube was specified
  (`git show` this file's first revision) and deliberately set aside.
- Native-to-native mirroring, pseudo-cursors and collaborative selection. That is
  the next spec; this one only ensures its foundations survive.
- Removing or refactoring the mirroring channel (FR-011).

## Assumptions

- **A-1** No live party is currently in the `browser` stage; the FR-008 migration
  is a safety net, not an expected path.
- **A-2** The browser's Docker volumes on the VPS may be left in place; removing
  them is an ops step, not a code change, and is listed in the deploy notes
  rather than automated.
- **A-3** Removal ships as a single PR to `main`. `main` auto-deploys, so the
  merge is the deploy.
- **A-4** The `browser` stage was never reachable in production — the stack was
  only added to `docker-compose.prod.yml` on 2026-08-08 (`507f186`) and that
  commit is being unwound here, so no user-facing capability is actually lost in
  prod.
