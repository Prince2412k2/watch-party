# Implementation Plan: Neko Collaborative Browser (v1)

> Spec: `docs/specs/2026-07-20-neko-collab-browser.md`

## Goal
Add a single-global-instance, collaboratively-controlled remote browser activity to
Watchparty parties, backed by the existing `contab` Neko container, with Neko-enforced
auth/isolation/control.

## Architecture decisions

- **Neko admin access via API token + per-user cookie login (multiuser provider).** The
  backend holds `NEKO_API_TOKEN` (admin, `Authorization: Bearer`) and
  `NEKO_USER_PASSWORD` (non-admin). It calls `POST /api/login` with a per-user username
  to mint a viewer session, and relays Neko's `Set-Cookie: NEKO_SESSION` to the browser
  through our own origin. *Rejected:* handing the client Neko credentials or an admin
  token — violates US-6/FR-005 and leaks in SC-004.
- **Container recreation via a narrow forced-command SSH helper on `contab`, never a
  Docker socket.** The backend's `NekoContainer` adapter shells out to
  `ssh neko-recreate@contab` where `authorized_keys` pins
  `command="/usr/local/bin/neko-recreate"` (a fixed script running
  `docker compose up -d --force-recreate neko`). The app process can trigger exactly one
  operation and nothing else, over the existing tailnet path. *Rejected:* bind-mounting
  `/var/run/docker.sock` into the Watchparty container with dockerode — grants
  root-equivalent host control to a public-facing Node process; a single RCE in the app
  becomes host compromise. This complexity is justified: FR-009 requires the backend to
  recreate the container, and the spec (Assumptions) explicitly forbids a raw Docker
  socket. A `docker restart` is insufficient — the writable layer (cookies/profile)
  survives a restart, so `--force-recreate` (new container from image) is required for
  SC-006 isolation.
- **Lease is a single durable row alongside the party store**, reconciled on startup
  against live Neko sessions. Reuses the single-process + SQLite model; no distributed
  lock. *Rejected:* in-memory-only lease — a crash would leave orphaned Neko sessions
  and a dangling lease (fails SC-007).
- **Signaling proxied, media direct (FR-013).** New `/neko` HTTP+WS reverse proxy
  mirrors the existing `/livekit` pattern in `app/server/index.js`; WebRTC UDP (EPR
  range) stays direct over the tailnet.
- **Transition model is strictly `lobby ↔ remote-browser`** (FR-007); no
  jellyfin↔browser switching, no prior-activity preservation.

## Tech constraints
- Backend is plain ES-module JS (`"type": "module"`); existing deps include
  `http-proxy-middleware`, `node-fetch`, `ws`. Tests use `node:test` +
  `node:assert/strict`, run via `node --test <file>`, DB isolated via `PARTY_DB_PATH`
  env (see `app/server/session.test.js`).
- Config is inline `process.env.X` reads (no config file) — match this pattern (FR-014).
- Neko API surface (verified in vendored `neko/server/internal/api/`):
  - `POST /api/login {username,password}` → `Set-Cookie: NEKO_SESSION` (cookie name
    `NEKO_SESSION`, configurable domain/path) or `{token}` body.
  - `GET /api/sessions` (bearer) → `[{id, profile, state:{is_connected,is_watching}}]`.
  - `DELETE /api/sessions/{id}` (admin), `POST /api/sessions/{id}/disconnect` (admin).
  - `GET /api/room/control`, `POST /api/room/control/give/{sessionId}` (host-or-admin),
    `POST /api/room/control/reset` (admin), `POST /api/room/control/take` (admin).
  - `POST /api/room/settings {locked_controls:true}` (admin).
  - Live WS endpoint is `/api/ws`; **legacy** `/ws` must be denied by the proxy.
  - Profile flag for control eligibility is `can_host`.

## Global Constraints
- **Never expose to any client**: Neko admin token, Neko user password, Neko
  admin-capable session, Jellyfin `token`/`accessToken`, `deviceId`, `socketId`.
  (SC-004, US-6, US-7.)
- **Env var names, verbatim**: `NEKO_ENABLED` (FR-014), `NEKO_CONCURRENCY_ENABLED`
  (reserved, defaults off, no impl — FR-015), `NEKO_IDLE_TIMEOUT_MS` (default `300000` =
  5 min, FR-008), `NEKO_API_TOKEN`, `NEKO_USER_PASSWORD`, `NEKO_INTERNAL_URL`
  (server→Neko HTTP base), `NEKO_PUBLIC_WS` (browser-reachable signaling, may be the
  `/neko` proxy).
- **Activity kind literal**: `remote-browser` (FR-001). Stages remain
  `'lobby' | 'watching'`; the new kind is a distinct activity dimension, mutually
  exclusive with `watching`.
- **Busy message copy** (FR-004/US-2), verbatim: `In use by <hostName>`.
- **Flutter unsupported copy** (US-9), verbatim: `remote browser not supported on this client`.
- **Proxy deny/filter list** (FR-012), exact: `/metrics`, `/api/profile`,
  `/api/room/control*` and other admin control APIs, the legacy `/ws` endpoint, and any
  `usr`/`pwd`/`token` query parameters.
- **Neko version**: `>= 3.1.2` (GHSA-2gw9-c2r2-f5qf); pin the image tag, never `:latest`.
- All teardown is idempotent and safe to re-enter (FR-010).

---

## Phase A — Blocking spike (gate for all of Phase C)

### Task A0: Prove the 7 risky Neko assumptions against live `contab`
Files: create `docs/specs/2026-07-20-neko-spike-decision.md` (decision record; throwaway
scripts may live in `scratch/` and are NOT committed as production code).
Interfaces: none (spike). Produces a committed decision record naming the chosen
mechanisms.
Steps: For each item, run a manual/scripted probe against `contab` and record PASS/FAIL
+ the exact mechanism chosen:
  1. **Credential-free iframe auth**: confirm `POST /api/login` returns
     `Set-Cookie: NEKO_SESSION`; verify a same-origin cookie broker can relay it with
     correct domain/path so the embed authenticates with no `usr`/`pwd`/`token` in any
     client-reachable URL or body. Record whether cookie domain rewriting is needed
     behind the `/neko` proxy.
  2. **Two-credential model**: confirm multiuser provider accepts admin password (→
     admin profile) and user password (→ `can_host` non-admin profile), and that
     `NEKO_API_TOKEN` (bearer) authorizes `/api/sessions` + `/api/room/*` admin routes.
  3. **Control enforcement**: set `locked_controls:true` via `POST /api/room/settings`;
     log in two `can_host=true` users; confirm a non-controller's input is rejected, and
     admin `control/give/{sessionId}` + `control/reset` still work while locked.
  4. **Session deletion disconnects WS+WebRTC**: `DELETE /api/sessions/{id}`; confirm
     the target's `/api/ws` closes AND the WebRTC media track stops.
  5. **Viewer detection**: confirm `GET /api/sessions` `state.is_connected` /
     `is_watching` is a reliable "N viewers" signal; record polling interval + field.
  6. **Safe reset via recreate**: seed cookies/login/download/history; run
     `docker compose up -d --force-recreate neko`; confirm the new container has none of
     it. Confirm `docker restart` alone does NOT (justifies force-recreate).
  7. **Version check**: confirm `contab` Neko `>= 3.1.2` (versions ≤ `3.1.1` have
     GHSA-2gw9-c2r2-f5qf); upgrade if not and record the pinned tag.
Verify: `docs/specs/2026-07-20-neko-spike-decision.md` exists with all 7 items marked
PASS and each chosen mechanism named. **Any FAIL is the go/no-go stop point** — Phase C
does not start.

---

## Phase B — Blocking prerequisite (gate for Phase C)

### Task B0: Replace `publicSession()` with an allow-listed DTO
Files: modify `app/server/session.js` (`publicSession` at 287-294); modify
`app/server/session.test.js`.
Interfaces:
  - Produces: `publicSession(session) → { id, hostId, hostName, stage, mediaItemId,
    mediaSourceId, playback, subtitlePreferences, collaborativeControl, syncMode,
    browse, schedule, mediaGeneration, guests: {userId,name}[], waiting:
    {userId,name}[], stallFallback: string[] }`.
  - Rebuild by **explicit construction** (allow-list), not destructuring exclusion. Map
    `guests`/`waiting` to `{userId, name}` only — drop `token`, `deviceId`, `socketId`,
    `joinedAt`. Drop `hostToken`, `hostDeviceId`, `hostSocketId`, `originalHostId`,
    `approved`, timers, and all internal scratch.
Steps: failing test asserting a leaky payload has no forbidden keys → verify RED →
rewrite `publicSession` as an allow-list → verify GREEN → commit.
Verify: `node --test app/server/session.test.js` passes, including a new test
`publicSession exposes only allow-listed fields with no auth/device/socket leakage` that
builds a session with host + guest + waiting each carrying token/deviceId/socketId, then
deep-scans the output recursively asserting none of `token`, `hostToken`, `deviceId`,
`hostDeviceId`, `socketId`, `hostSocketId`, `approved`, `originalHostId` appear.
(Satisfies FR-011, US-7, and the `publicSession` half of SC-004.)

---

## Phase C — Feature

### Task C1 [P]: Neko config module + feature gate
Files: create `app/server/neko/config.js`; create `app/server/neko/config.test.js`.
Interfaces: Produces:
  - `nekoConfig() → { enabled:boolean, concurrencyEnabled:boolean, internalUrl:string,
    publicWs:string, apiToken:string, userPassword:string, idleTimeoutMs:number,
    cookieName:'NEKO_SESSION' }` reading `NEKO_ENABLED`, `NEKO_CONCURRENCY_ENABLED`
    (parsed but never acted on — placeholder), `NEKO_INTERNAL_URL`, `NEKO_PUBLIC_WS`,
    `NEKO_API_TOKEN`, `NEKO_USER_PASSWORD`, `NEKO_IDLE_TIMEOUT_MS` (default `300000`).
  - `assertNekoEnabled() → void` throws `Error('neko disabled')` when `!enabled`.
Steps: failing test (default env → `enabled=false`, `idleTimeoutMs=300000`,
`concurrencyEnabled=false`) → RED → implement → GREEN → commit.
Verify: `node --test app/server/neko/config.test.js` — asserts `NEKO_ENABLED=false`/unset
yields `enabled:false`; `NEKO_IDLE_TIMEOUT_MS=1000` overrides default;
`NEKO_CONCURRENCY_ENABLED=true` is parsed but flagged reserved. (FR-014, FR-015, FR-008
default.)

### Task C2 [P]: Neko admin API adapter
Files: create `app/server/neko/admin.js`; create `app/server/neko/admin.test.js`.
Interfaces: all take `{ internalUrl, apiToken, userPassword }` from `nekoConfig()`;
Produces:
  - `loginViewer(username) → Promise<{ sessionId:string, cookie:string }>` — `POST
    /api/login {username, password:userPassword}`, returns the `Set-Cookie` value (raw)
    + parsed session id. Never returns the password.
  - `listSessions() → Promise<{ id, username, isConnected:boolean,
    isWatching:boolean }[]>` — `GET /api/sessions` (bearer).
  - `deleteSession(sessionId) → Promise<void>` — `DELETE /api/sessions/{id}`.
  - `setControlLock(locked:boolean) → Promise<void>` — `POST /api/room/settings
    {locked_controls:locked}`.
  - `giveControl(sessionId) → Promise<void>` — `POST /api/room/control/give/{sessionId}`.
  - `resetControl() → Promise<void>` — `POST /api/room/control/reset`.
  - `controlStatus() → Promise<{ hasHost:boolean, hostId:string|null }>` — `GET
    /api/room/control`.
  All use `node-fetch`; 4xx/5xx throw `Error` with status; **log redaction**: never log
  token/password/cookie.
Steps: failing tests against a stubbed `fetch` (injectable via param default) asserting
correct method/path/headers and that returned objects contain no secrets → RED →
implement → GREEN → commit.
Verify: `node --test app/server/neko/admin.test.js` — mock-fetch tests assert bearer
header present, `loginViewer` output has no password, error mapping works. (Unit layer
for FR-005, FR-005a, FR-006.)

### Task C3 [P]: Neko container controller (recreate helper)
Files: create `app/server/neko/container.js`; create `app/server/neko/container.test.js`;
create `docs/ops/neko-recreate.md` (documents the `contab` forced-command SSH setup +
`neko-recreate` script + pinned image tag).
Interfaces: Produces:
  - `recreateContainer({ runner } = {}) → Promise<void>` — invokes the injected `runner`
    (default: `child_process.execFile('ssh', ['neko-recreate@' + host, ...])`) which
    triggers the fixed remote `neko-recreate` script; rejects on non-zero exit. `runner`
    injection exists so unit tests never shell out.
  - `waitForHealthy({ timeoutMs, poll } = {}) → Promise<void>` — polls `GET /health` on
    `internalUrl` until 200 or timeout (default 30s).
Steps: failing test with a mock `runner` (asserts it is called, and a failing runner
rejects) → RED → implement → GREEN → commit. Document that the helper is argument-less
and cannot pass arbitrary Docker commands.
Verify: `node --test app/server/neko/container.test.js` — asserts recreate calls the
runner once, propagates failure, and `waitForHealthy` resolves on first 200 / rejects on
timeout. Live recreate is proven manually per Task A0 item 6. (FR-009.)

### Task C4: Durable lease store + startup reconciliation
Files: modify `app/server/party-store.js` (add `neko_lease` table + accessors); create
`app/server/neko/lease.js`; create `app/server/neko/lease.test.js`.
Interfaces:
  - party-store Produces: `saveLease({partyId, hostName, sessions, acquiredAt}) → void`,
    `loadLease() → {partyId, hostName, sessions:{userId,nekoSessionId}[], acquiredAt}
    |null`, `clearLease() → void` (single-row table, primary key constant `'global'`).
  - lease.js Consumes: party-store lease accessors, `getSession` from session.js,
    `admin.listSessions`. Produces:
    - `acquireLease({partyId, hostName}) → {ok:true} | {ok:false, hostName}` — atomic
      check-and-set; if held by another party returns the holder's `hostName`
      (FR-002/FR-004).
    - `getLease() → {partyId, hostName}|null`.
    - `recordUserSession(partyId, userId, nekoSessionId) → void` (persists mapping,
      FR-002a).
    - `releaseLease(partyId) → void`.
    - `reconcileLease({listSessions, teardown}) → Promise<void>` — on startup: if a lease
      row exists but its `partyId` has no live Watchparty session, OR its recorded Neko
      sessions don't match `listSessions()`, invoke `teardown` and `clearLease` so state
      is either both-valid or both-clean (SC-007).
Steps: failing tests for acquire-when-free, reject-when-held (returns holder hostName),
reconcile-clears-dangling → RED → implement → GREEN → commit.
Verify: `node --test app/server/neko/lease.test.js` (sets `PARTY_DB_PATH`) — asserts
second acquire returns `{ok:false, hostName}`; reconcile with a persisted lease whose
party is gone calls teardown + clears. (FR-002, FR-002a, SC-007.)

### Task C5: `remote-browser` activity + transition guards in session model
Files: modify `app/server/session.js` (`createSession`, `durableState`, `runtimeState`,
and add helpers); modify `app/server/session.test.js`.
Interfaces:
  - Add field to session shape: `activity: 'none' | 'remote-browser'` (default `'none'`),
    persisted in `durableState`/rehydrated in `runtimeState`. `stage` unchanged.
  - Produces: `canStartBrowser(session) → boolean` (true only when `stage==='lobby'` and
    `activity==='none'`), `setBrowserActivity(session, on:boolean) → void` (sets
    `activity`; when turning on requires lobby, when off resets to `'none'`),
    `isBrowserActive(session) → boolean`.
  - `publicSession` (from Task B0) must additionally allow-list `activity`.
Steps: failing tests for default `activity:'none'`, persistence round-trip via
`loadParty`, `canStartBrowser` gating → RED → implement → GREEN → commit.
Verify: `node --test app/server/session.test.js` — asserts `activity` persists and
rehydrates, `canStartBrowser` false while `watching`. (FR-001, FR-007 state half.)

### Task C6: Centralized idempotent teardown service
Files: create `app/server/neko/teardown.js`; create `app/server/neko/teardown.test.js`.
Interfaces: Consumes: `admin.{listSessions,deleteSession,resetControl}`,
`container.recreateContainer`, `lease.{getLease,releaseLease}`,
`getSession`/`setBrowserActivity` from session.js. Produces:
  - `teardownBrowser(partyId, { reason }) → Promise<void>` — idempotent, single-flight
    (guarded by an in-module `Map<partyId,Promise>`): (1) delete every recorded per-user
    Neko session (`deleteSession`, ignore 404), (2) `resetControl()`, (3)
    `recreateContainer()` + `waitForHealthy()`, (4) `releaseLease(partyId)`, (5) set
    owning session `activity='none'`, `stage='lobby'` if still present. Retries steps
    1-3 up to 3× on failure; safe to call when no lease is held (no-op). Order fixed:
    sessions → control reset → recreate → lease release (FR-010).
Steps: failing tests: teardown deletes all recorded sessions then recreates then
releases (assert call order via a mock adapter); double-invocation runs once; no-lease
invocation no-ops; a failing recreate retries → RED → implement → GREEN → commit.
Verify: `node --test app/server/neko/teardown.test.js` — mock-adapter assertions on
order, idempotency, retry. (FR-010, FR-005a, FR-009; isolation contract for SC-006.)

### Task C7: Start / stop browser socket events with serialization + rollback
Files: modify `app/server/index.js` (new handlers near `party:selectMedia` ~511 and
`party:backToLobby` ~544; add a per-party serialization queue like the existing
`enqueuePlaybackTrackChange`).
Interfaces: Consumes: `nekoConfig`, `assertNekoEnabled`, `lease.acquireLease`,
`admin.setControlLock`, `container.{recreateContainer,waitForHealthy}`,
`teardownBrowser`, session helpers. New socket events:
  - `party:startBrowser` `(_p, ack)` → member of a lobby party: `assertNekoEnabled()`
    (else `ack({error:'browser disabled'})`); serialize per party; `canStartBrowser`
    guard (else `ack({error:'not allowed'})`); `acquireLease` — if `{ok:false}` →
    `ack({error:'busy', message:'In use by ' + hostName})` and create nothing
    (FR-004/SC-002); else recreate+wait clean container → `setControlLock(true)` →
    `setBrowserActivity(on)` → persist → `io.to(id).emit('party:state', publicSession)`
    → `ack({ok:true})`. **On any step failure after acquire: `teardownBrowser`
    (releases lease) and `ack({error})`** (FR-007 rollback).
  - `party:stopBrowser` `(_p, ack)` → host OR current controller only (FR-007b):
    serialize; `teardownBrowser(id,{reason:'stop'})`; emit `party:state`;
    `ack({ok:true})`.
Steps: harness/integration test (scratch Socket.IO server, `WP_TEST_MODE=1`, mocked neko
adapters via env or module injection): start-when-free transitions to `remote-browser`;
start-when-busy from a second party returns `{error:'busy', message:'In use by
<host>'}` synchronously and creates nothing; recreate-failure rolls back and frees lease
→ RED → implement → GREEN → commit.
Verify: `node --test app/server/neko/browser-flow.test.js` (new integration test using
the mocked adapter). (US-1, US-2, FR-003, FR-004, FR-007, SC-002.)

### Task C8: Wire teardown into every party-deletion path
Files: modify `app/server/index.js` — `party:end` (~437), failed `party:create` catch
(~321), host-loss expiry in `handleHostDisconnect` (~868), restore-grace expiry in
`session.js` startup timer (~99, call teardown before `deleteSession`), and
`party:backToLobby`/`party:stopBrowser`.
Interfaces: Consumes: `teardownBrowser`, `lease.getLease`. In each path: if the party
being deleted currently holds the lease (`getLease()?.partyId === sess.id`), `await
teardownBrowser(sess.id, {reason})` before/around `deleteSession`. `party:backToLobby`
must call `teardownBrowser` when `activity==='remote-browser'` (FR-007: browser→lobby).
Steps: integration test: a lease-holding party's `party:end` triggers teardown (mock
adapter records session-delete + recreate + lease-release); host-loss expiry likewise →
RED → implement → GREEN → commit.
Verify: `node --test app/server/neko/teardown-wiring.test.js` — asserts each deletion
path invokes teardown exactly once when the lease is held, and not when it isn't.
(FR-010, US-4.)

### Task C9: Idle monitor (zero-viewer auto-release)
Files: create `app/server/neko/idle.js`; create `app/server/neko/idle.test.js`; wire
start/stop into Task C7's start/stop handlers.
Interfaces: Consumes: `admin.listSessions`, `getLease`, `teardownBrowser`,
`nekoConfig().idleTimeoutMs`. Produces:
  - `startIdleMonitor({ intervalMs, now }={}) → handle` — periodically calls
    `listSessions()`; "zero viewers" = no session with `isConnected` (per Task A0 item 5)
    with a reconnect grace = `idleTimeoutMs`. When the lease-holding party has had zero
    connected viewers continuously for `idleTimeoutMs`, calls
    `teardownBrowser(partyId,{reason:'idle'})`. **Not** based on Socket.IO membership
    (FR-008).
  - `stopIdleMonitor(handle) → void`.
Steps: failing test with injected fake clock + mock `listSessions` returning zero
connected across the window → teardown fires; a reconnect within the window resets the
timer → RED → implement → GREEN → commit.
Verify: `node --test app/server/neko/idle.test.js` (fake timers, shortened timeout).
(FR-008, US-4, SC-003.)

### Task C10: Per-user viewer-session broker endpoint
Files: create `app/server/neko/routes.js` (`registerNekoRoutes(app, io)`); register it in
`app/server/index.js` near line 211.
Interfaces: Consumes: `requireAuth`, `getJellyfin`, `getSession`, `isMember`,
`nekoConfig`, `assertNekoEnabled`, `admin.loginViewer`, `lease`, `recordUserSession`.
Produces route:
  - `POST /api/party/:id/browser/session` (`requireAuth`): reject if `!enabled`; 404 if
    party missing; 403 if requester not a member of the party; 409 if that party doesn't
    hold the lease. Derive a stable per-user Neko username `wp-<userId>` (FR-005
    unique-per-user). Call `loginViewer(username)` → set the returned `NEKO_SESSION`
    cookie on **our** response scoped to `/neko` path (relaying Neko's Set-Cookie per
    Task A0 item 1), `recordUserSession(partyId, userId, sessionId)`, and return
    `{ wsUrl: nekoConfig().publicWs }` only. **Never** return password, admin token, or
    the raw Neko session token in the body.
Steps: integration test (supertest-style over the express app with a mocked
`loginViewer`): non-member → 403; member of non-lease party → 409; member of lease party
→ 200 with a `Set-Cookie NEKO_SESSION; Path=/neko` header and a body containing no
secret; `NEKO_ENABLED=false` → rejected → RED → implement → GREEN → commit.
Verify: `node --test app/server/neko/routes.test.js` — asserts authz matrix, cookie
relay, secret-free body, and disabled-gate. (FR-005, FR-005a mapping-record, US-6,
SC-001 backend half, SC-004, SC-005 for this route.)

### Task C11: Same-origin Neko HTTP + WS proxy with deny-list
Files: modify `app/server/index.js` (add `/neko` proxy near the `/livekit` proxy
~147-158 and the upgrade handler ~156); modify the SPA-fallback exclusion list (~247)
and the SERVE_CLIENT path-prefix list to include `/neko`.
Interfaces: `createProxyMiddleware({ target: nekoConfig().internalUrl,
changeOrigin:true, ws:true, pathRewrite:{'^/neko':''} })` gated by `requireAuth` **and**
a party-membership check on both HTTP requests and WS upgrades (the requester's session
must belong to the lease-holding party). **Deny/filter middleware runs before the
proxy** and returns 403 for: `/metrics`, `/api/profile`, `/api/room/control` (and
subpaths), legacy `/ws`, and strips/rejects any `usr`/`pwd`/`token` query param. WS
upgrade wired into `httpServer.on('upgrade')` alongside `/livekit`. Proxy
`on.proxyReq`/`on.error` logging redacts cookies/tokens. WebRTC media is **not** proxied
(FR-013).
Steps: integration test hitting the proxy paths: `/neko/metrics` → 403;
`/neko/api/room/control/reset` → 403; `/neko/api/ws?token=x` → 403 (stripped/denied);
unauthenticated → 401; member of lease party → forwarded (mock upstream) → RED →
implement → GREEN → commit.
Verify: `node --test app/server/neko/proxy.test.js`. (FR-012, FR-013, FR-006a
defense-in-depth.)

### Task C12: Neko-enforced control endpoints (request / reassign / revoke)
Files: modify `app/server/neko/routes.js`; register socket events in
`app/server/index.js`. Use socket events for parity with existing control UX.
Interfaces: New socket events (Consumes: `admin.giveControl`, `resetControl`,
`controlStatus`, lease + per-user session mapping):
  - `browser:requestControl` `(_p, ack)` — any member of the lease party MAY request
    when none held (FR-007b): check `controlStatus()`; if `!hasHost`,
    `giveControl(requesterNekoSessionId)` → broadcast `browser:control
    {controllerUserId}`; else `ack({error:'held'})`. Members cannot self-seize (lock is
    on; only backend calls give — FR-006a).
  - `browser:assignControl` `({userId}, ack)` — host only: `giveControl
    (targetNekoSessionId)` (immediately revokes prior controller at Neko level),
    broadcast (US-3).
  - `browser:revokeControl` `(_p, ack)` — host only: `resetControl()`, broadcast
    `browser:control {controllerUserId:null}`.
Steps: integration test with mocked admin: request-when-free assigns; request-when-held
denied; host reassign revokes prior; non-host cannot assign → RED → implement → GREEN →
commit.
Verify: `node --test app/server/neko/control.test.js`; live/pinned-container check per
Task A0 item 3. (FR-006, FR-006a, FR-007b, US-3, SC-008.)

### Task C13: Reject media mutation while `remote-browser`; legacy-client fallback
Files: modify `app/server/index.js` — `party:selectMedia` (~511),
`party:setPlaybackTracks` (~558), and the `publicSession` emission path for legacy
clients.
Interfaces:
  - In `party:selectMedia` and any media-mutation handler: if `isBrowserActive(sess)` →
    `ack({error:'browser active'})` and no state change (FR-007). Reject media mutations
    from any client while browser active (US-9 legacy protection).
  - Legacy fallback: add `publicSessionLegacy(session)` in `session.js` that, when
    `activity==='remote-browser'`, presents `stage:'lobby'` and omits browser fields —
    used only for clients that identify as legacy (detect via a client-capability flag on
    the socket handshake, e.g. `socket.handshake.auth.caps?.remoteBrowser !== true`).
    Updated web/Flutter receive the real `activity`.
Steps: failing test: `party:selectMedia` while `remote-browser` returns
`{error:'browser active'}` and leaves `activity` unchanged; legacy-capability socket
receives `stage:'lobby'` with no `activity:'remote-browser'` leak → RED → implement →
GREEN → commit.
Verify: `node --test app/server/neko/legacy-compat.test.js`. (FR-007, US-9 server half.)

### Task C14 [P]: Web client — dedicated remote-browser render branch
Files: modify `app/client/src/types.ts` (extend `PartySession` with `activity?: 'none' |
'remote-browser'`; add `startBrowser`/`stopBrowser`/`requestControl` to
`PartyContextValue`); modify `app/client/src/pages/Party.tsx` (add a branch before the
`stage === 'lobby'` block ~136); create `app/client/src/pages/RemoteBrowser.tsx`.
Interfaces: `RemoteBrowser` component: on mount `POST /api/party/:id/browser/session`
(sets the `/neko` cookie), then renders an `<iframe src="/neko/">` (same-origin,
authenticated by cookie); shows control-request UI wired to `browser:requestControl`.
When `session.activity === 'remote-browser'`, `Party.tsx` renders `RemoteBrowser`,
**not** the Jellyfin player path (US-9).
Steps: add a component + branch; because the client has no JS unit-test harness for
pages, verify via type-check/build and manual live acceptance on `contab`.
Verify: `cd app/client && npm run build` succeeds; manual: a party in `remote-browser`
renders the embed (not the player). (FR-012 client, US-9 web, SC-001 client half.)

### Task C15 [P]: Flutter — explicit unsupported state
Files: modify `flutter_app/lib/models/party_state.dart` (add `@Default('none') String
activity;` and regenerate freezed); modify the party screen widget that switches on
`stage` to show, when `activity == 'remote-browser'`, the verbatim message `remote
browser not supported on this client`.
Interfaces: `PartyState.activity` field; a new branch in the party view.
Steps: add field, run `dart run build_runner build`, add UI branch.
Verify: `cd flutter_app && flutter analyze` passes; manual: updated Flutter shows the
unsupported message; legacy Flutter (no `activity`) sees `stage:'lobby'` (from Task C13)
and shows the library harmlessly. (US-9 Flutter.)

### Task C16 [P]: Vite dev-proxy config for `/neko`
Files: modify `app/client/vite.config.ts` (add `/neko` to `server.proxy` mirroring
`/livekit`: target `NEKO_INTERNAL_URL || 'http://localhost:8080'`, `ws:true`,
`changeOrigin:true`, rewrite strip `^/neko`).
Steps: add the proxy entry.
Verify: `cd app/client && npm run build` succeeds; manual dev: `/neko` reaches Neko
through Vite. (FR-012 dev-proxy requirement.)

---

## Success-criteria coverage
- SC-001 → C7 + C10 + C14 (+ manual live). SC-002 → C7. SC-003 → C9. SC-004 → B0 + C10
  (secret-free body/cookie). SC-005 → C1 + C7 + C10 (disabled gate). SC-006 → C3 + C6
  (isolation; live proof in A0/pinned-container integration). SC-007 → C4
  reconciliation. SC-008 → C12 (+ A0 live).

## FR coverage
FR-000→A0; FR-001→C5; FR-002/002a→C4; FR-003/004→C7; FR-005/005a→C10 (+C2);
FR-006/006a→C12 (+C11 deny); FR-007/007b→C5/C7/C12/C13; FR-008→C9; FR-009→C3/C6;
FR-010→C6/C8; FR-011→B0; FR-012→C11/C14/C16; FR-013→C11; FR-014/015→C1.

## Dependency / ordering
- Phase A (A0 spike) and Phase B (B0 DTO) precede all Phase C tasks.
- C1, C2, C3 are independent `[P]` and can run in parallel.
- C4, C5, C6 precede C7/C8/C9. C10/C11 precede C12/C14. C14, C15, C16 are `[P]`.

## CI note
The spike (A0) requires live `contab` access, and the pinned-container integration
fixture for SC-006/SC-008 must be stood up before C6/C12 can be truly verified in CI —
**CI must not point at production `contab`** (spec Test strategy).
