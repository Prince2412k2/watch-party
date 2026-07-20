# Implementation Plan: Neko Collaborative Browser (v1)

> Spec: `docs/specs/2026-07-20-neko-collab-browser.md`
> Revised after cross-review (2026-07-20): end-to-end wiring + lifecycle states.

## Goal
Add a single-global-instance, collaboratively-controlled remote browser activity to
Watchparty parties, backed by the existing `contab` Neko container, with Neko-enforced
auth/isolation/control.

## Architecture decisions

- **Neko admin access via API token + per-user cookie login (multiuser provider).**
  Backend holds `NEKO_API_TOKEN` (admin bearer) and `NEKO_USER_PASSWORD` (non-admin),
  calls `POST /api/login` with a per-user username to mint a viewer session, and relays
  Neko's `Set-Cookie: NEKO_SESSION` through our own origin. *Rejected:* handing the
  client Neko credentials/admin token — violates US-6/FR-005, leaks in SC-004.
- **Container recreation via a narrow forced-command SSH helper on `contab`, never a
  Docker socket.** `authorized_keys` pins `command="/usr/local/bin/neko-recreate"` plus
  `restrict` (implying no-port-forwarding/no-agent-forwarding/no-X11/no-pty). The app can
  trigger exactly one operation. *Rejected:* bind-mounting `/var/run/docker.sock` —
  root-equivalent host control from a public-facing Node process. `docker restart` is
  insufficient (writable layer survives) so `--force-recreate` is required for SC-006.
- **Lease is a single durable row with an explicit state machine**
  `free → starting → active → cleaning → free`, plus a monotonic `generation` counter.
  Proxy, session-broker, and control ops only work in `active`. Release to `free` happens
  only after the owning party is persisted back to lobby (finding #13). Reconciled on
  startup. *Rejected:* boolean/in-memory lease — crash leaves orphans (fails SC-007) and
  a bare boolean races on teardown (finding #13).
- **Single authorization path in all environments.** Vite dev-proxy forwards `/neko` to
  the **Watchparty backend**, which is the only thing that proxies to Neko. No client
  ever reaches Neko directly (finding #3).
- **Proxy is an allow-list**, not a deny-list: only the static asset paths + `/api/ws` +
  the specific bootstrap endpoints the embedded client actually needs (captured in the
  spike) are forwarded; everything else 403s (finding #12).
- **Transition model is strictly `lobby ↔ remote-browser`** (FR-007).

## Tech constraints
- Backend is plain ES-module JS (`"type": "module"`); deps include
  `http-proxy-middleware`, `node-fetch`, `ws`. Tests use `node:test` +
  `node:assert/strict`, run via `node --test <file>`, DB isolated via `PARTY_DB_PATH`.
- Config is inline `process.env.X` reads (no config file) — match this (FR-014).
- Neko API (verified in vendored `neko/server/internal/api/`): `POST /api/login`
  (→ `Set-Cookie: NEKO_SESSION`), `GET /api/sessions` (bearer), `DELETE
  /api/sessions/{id}`, `GET/POST /api/room/control{,/give/{id},/reset}`, `POST
  /api/room/settings {locked_controls}`. Live WS `/api/ws`; legacy `/ws` must be denied.
  Control-eligibility flag is `can_host`. Path-prefix via `server.path_prefix`.

## Global Constraints
- **Never expose to any client**: Neko admin token, Neko user password, admin-capable
  session, Jellyfin `token`/`accessToken`, `deviceId`, `socketId`. (SC-004, US-6, US-7.)
- **Env vars, verbatim**: `NEKO_ENABLED`, `NEKO_CONCURRENCY_ENABLED` (reserved, off, no
  impl), `NEKO_IDLE_TIMEOUT_MS` (default `300000`), `NEKO_API_TOKEN`, `NEKO_USER_PASSWORD`,
  `NEKO_INTERNAL_URL`, `NEKO_PUBLIC_WS`, `NEKO_SSH_HOST`, `NEKO_SSH_KEY_PATH`.
- **Session field**: `activity: 'none' | 'remote-browser'` — a plain string (finding #5),
  matching the spec FR-001. `stage` stays `'lobby'|'watching'`.
- **Client capability flag**: clients that understand remote-browser connect with
  `auth: { caps: { remoteBrowser: true } }`; absence ⇒ legacy (finding #1).
- **Busy copy** (verbatim): `In use by <hostName>`. **Flutter unsupported copy**
  (verbatim): `remote browser not supported on this client`.
- **Neko version** `>= 3.1.2` (GHSA-2gw9-c2r2-f5qf); pin the image tag, never `:latest`.
- All teardown idempotent and safe to re-enter (FR-010).

---

## Phase A — Blocking spike (gate for all of Phase C)

### Task A0: Prove the risky Neko assumptions against live `contab`
Files: create `docs/specs/2026-07-20-neko-spike-decision.md` (decision record; throwaway
scripts in `scratch/`, NOT committed as production code).
Steps — probe each against `contab`, record PASS/FAIL + chosen mechanism:
  1. **Credential-free iframe auth**: `POST /api/login` → `Set-Cookie: NEKO_SESSION`;
     confirm a same-origin cookie broker relays it (correct domain/path) so the embed
     authenticates with no `usr`/`pwd`/`token` client-side. Record whether cookie domain
     rewriting is needed behind `/neko`.
  2. **Two-credential model**: multiuser admin password → admin profile; user password →
     `can_host` non-admin; `NEKO_API_TOKEN` bearer authorizes `/api/sessions`+`/api/room/*`.
  3. **Control enforcement**: `locked_controls:true`; two `can_host` users; non-controller
     input rejected; admin `control/give/{id}` + `control/reset` still work while locked.
  4. **Session deletion** disconnects `/api/ws` AND stops WebRTC media.
  5. **Viewer detection**: which of `state.is_connected`/`is_watching` is the reliable
     "N viewers" signal; record polling interval; note if connected-but-not-watching is
     common (informs finding #10).
  6. **Safe reset via recreate**: seed cookies/login/download/history →
     `docker compose up -d --force-recreate neko` → new container is clean. Confirm
     `docker restart` alone does NOT clean it.
  7. **Version check**: `contab` Neko `>= 3.1.2`; upgrade + record pinned tag if not.
  8. **Path-prefix + client request capture** (findings #8, #12): decide and record
     either (a) Neko configured with `server.path_prefix=/neko` and proxy preserves it,
     or (b) confirmed relative assets + full rewrite for every HTTP+WS request. Capture
     the **exact set of paths** the embedded client requests on load and during a session
     → this becomes the proxy allow-list for C11.
Verify: decision record exists, all 8 items PASS with mechanisms named. **Any FAIL is the
go/no-go stop point.**

---

## Phase B — Blocking prerequisite (gate for Phase C)

### Task B0: Replace `publicSession()` with a per-socket, capability-aware allow-list DTO
Files: modify `app/server/session.js` (`publicSession` at 287-294, add
`publicSessionFor`); audit and update **all ~19 call sites** across
`app/server/index.js` and `app/server/subtitles.js` (finding #1).
Interfaces:
  - `publicSession(session) → {...allow-listed}` — explicit construction (allow-list),
    NOT destructuring exclusion. Includes `id, hostId, hostName, stage, activity,
    mediaItemId, mediaSourceId, playback, subtitlePreferences, collaborativeControl,
    syncMode, browse, schedule, mediaGeneration, guests:{userId,name}[],
    waiting:{userId,name}[], stallFallback:string[]`. Drops every token/deviceId/socketId
    (host, guests, waiting), `hostToken/hostDeviceId/hostSocketId`, `originalHostId`,
    `approved`, timers, scratch.
  - `publicSessionFor(session, { caps }) → payload` — capability-aware wrapper: modern
    (`caps.remoteBrowser`) gets the full DTO incl. `activity`; legacy gets the DTO with
    `activity` omitted and, when `activity==='remote-browser'`, `stage` presented as
    `'lobby'` (finding #1 + Task C13 fallback, unified here).
  - Introduce a **centralized emit helper** `emitPartyState(io, session)` that iterates
    the room's sockets and sends each `publicSessionFor(session, {caps: socket.caps})`
    (per-socket, since one room now needs two snapshots — finding #1). Replace the ~19
    broadcast call sites with it.
Steps: failing test (deep-scan no forbidden keys; modern vs legacy snapshot differs on
`activity`/`stage`) → RED → implement allow-list + `publicSessionFor` + `emitPartyState`,
migrate call sites → GREEN → commit.
Verify: `node --test app/server/session.test.js` incl.
`publicSession exposes only allow-listed fields` and
`publicSessionFor: modern sees activity, legacy sees lobby fallback`. (FR-011, US-7,
US-9 snapshot half, SC-004 publicSession half.)

---

## Phase C — Feature

### Task C1 [P]: Neko config module + feature gate
Files: create `app/server/neko/config.js` + `.test.js`.
Interfaces: `nekoConfig() → { enabled, concurrencyEnabled, internalUrl, publicWs,
apiToken, userPassword, idleTimeoutMs, cookieName:'NEKO_SESSION', sshHost, sshKeyPath }`;
`assertNekoEnabled() → void` throws `Error('neko disabled')` when `!enabled`.
Verify: `node --test app/server/neko/config.test.js` — unset/`false` → `enabled:false`;
`NEKO_IDLE_TIMEOUT_MS=1000` overrides `300000`; `NEKO_CONCURRENCY_ENABLED` parsed but
reserved. (FR-014, FR-015, FR-008 default.)

### Task C2 [P]: Neko admin API adapter
Files: create `app/server/neko/admin.js` + `.test.js`.
Interfaces (all take config-derived `{internalUrl, apiToken, userPassword}`; injectable
`fetch` default for tests; never log token/password/cookie):
  - `loginViewer(username) → {sessionId, cookie}` (`POST /api/login`; no password out)
  - `listSessions() → {id, username, isConnected, isWatching}[]` (`GET /api/sessions`)
  - `deleteSession(sessionId) → void`
  - `setControlLock(locked) → void` (`POST /api/room/settings`)
  - `giveControl(sessionId) → void`, `resetControl() → void`,
    `controlStatus() → {hasHost, hostSessionId}`
Verify: `node --test app/server/neko/admin.test.js` — bearer header present, secret-free
outputs, error mapping. (FR-005, FR-005a, FR-006 unit layer.)

### Task C3 [P]: Neko container controller (recreate helper)
Files: create `app/server/neko/container.js` + `.test.js`.
Interfaces:
  - `recreateContainer({ runner } = {}) → void` — injected `runner` default
    `execFile('ssh', ['-i', sshKeyPath, '-o', 'StrictHostKeyChecking=yes',
    'neko-recreate@' + sshHost])` triggering the fixed remote script; rejects non-zero.
  - `waitForHealthy({ timeoutMs=30000, poll } = {}) → void` — polls `GET /health` on
    `internalUrl`.
Verify: `node --test app/server/neko/container.test.js` — runner called once, failure
propagates, `waitForHealthy` resolves on 200 / rejects on timeout. (FR-009.)

### Task C3b: SSH recreation deployment wiring (finding #6)
Files: modify `app/Dockerfile` (add `RUN apk add --no-cache openssh-client`); modify
`docker-compose.prod.yml` (mount `NEKO_SSH_KEY_PATH` read-only, mount pinned
`known_hosts`, set `NEKO_SSH_HOST`; ensure tailnet reachability from the app container);
create `docs/ops/neko-recreate.md` (the `contab` forced-command setup: `authorized_keys`
line with `restrict,command="/usr/local/bin/neko-recreate"`, the script running
`docker compose up -d --force-recreate neko`, pinned image tag, key generation, secret
handling — key never baked into the image); add a startup preflight in `index.js` that,
when `NEKO_ENABLED`, verifies the ssh binary + key are present and logs a clear error
otherwise.
Verify: manual — from inside a built app container, `recreateContainer()` triggers a real
recreate on `contab` and nothing else (attempt an arbitrary command → refused by
forced-command). Preflight fails loudly when key missing. (FR-009 deployability.)

### Task C4: Durable lease store (state machine) + startup reconciliation
Files: modify `app/server/party-store.js` (add `neko_lease` table: single row keyed
`'global'`, columns `partyId, hostName, state, generation, sessions(JSON), acquiredAt`);
create `app/server/neko/lease.js` + `.test.js`.
Interfaces:
  - store: `saveLease(row) → void`, `loadLease() → row|null`, `clearLease() → void`.
  - lease.js: `acquireLease({partyId, hostName}) → {ok:true, generation} | {ok:false,
    hostName}` — atomic; only succeeds from `free`; sets state `starting`, bumps
    `generation`. `markActive(partyId) → void` (`starting→active`).
    `beginCleaning(partyId) → void` (`active→cleaning`). `releaseLease(partyId) → void`
    (`cleaning→free`, clears row). `getLease() → {partyId, hostName, state, generation}
    |null`. `recordUserSession(partyId, generation, userId, nekoSessionId) → void`
    (persists mapping; ignores stale generation — finding #4). `sessionsFor(partyId) →
    {userId, nekoSessionId}[]`. `controllerUserFor(nekoSessionId) → userId|null` (shared
    authoritative mapping — finding #9). `reconcileLease({listSessions, teardown}) →
    void` (startup: lease row with no live party OR mismatched live sessions → teardown +
    clear; a valid `active` lease is kept and returned so the idle monitor can be
    (re)started — finding #10).
Verify: `node --test app/server/neko/lease.test.js` (sets `PARTY_DB_PATH`) — acquire from
free ok; second acquire `{ok:false, hostName}`; state transitions enforce order; stale
generation `recordUserSession` ignored; reconcile clears dangling / keeps valid.
(FR-002, FR-002a, SC-007, findings #4/#9/#13.)

### Task C5: `remote-browser` activity + transition guards in session model
Files: modify `app/server/session.js` (`createSession`, `durableState`, `runtimeState`,
helpers) + `session.test.js`.
Interfaces: add `activity: 'none'|'remote-browser'` (default `'none'`), persisted +
rehydrated. `canStartBrowser(session) → boolean` (only `stage==='lobby' &&
activity==='none'`); `setBrowserActivity(session, on) → void`; `isBrowserActive(session)
→ boolean`. (`publicSession` already allow-lists `activity` from B0.)
Verify: `node --test app/server/session.test.js` — `activity` round-trips;
`canStartBrowser` false while `watching`. (FR-001, FR-007 state half.)

### Task C5b: Shared controller-authorization helper (finding #9)
Files: create `app/server/neko/controller.js` + `.test.js`.
Interfaces (Consumes `lease.controllerUserFor`, `admin.controlStatus`): 
  - `currentController(partyId) → Promise<{userId, nekoSessionId}|null>` — asks Neko
    (`controlStatus()`) for the authoritative host session, maps it to a Watchparty user
    via the durable lease mapping. Survives restart (no reliance on ephemeral broadcast).
  - `isController(partyId, userId) → Promise<boolean>`.
Verify: `node --test app/server/neko/controller.test.js` — maps Neko host session → user;
returns null when none. This helper is a dependency of C7 (stop authz) and C12.

### Task C6: Centralized idempotent teardown service
Files: create `app/server/neko/teardown.js` + `.test.js`.
Interfaces (Consumes admin, container, lease, session helpers, `emitPartyState`):
  - `teardownBrowser(partyId, { reason }) → void` — idempotent single-flight
    (`Map<partyId,Promise>`). Order (finding #13 — lease released LAST, after party is
    persisted to lobby): (1) `lease.beginCleaning` (state→`cleaning`; blocks new
    acquire/proxy/session), (2) delete every recorded per-user session (ignore 404),
    (3) `resetControl()`, (4) `recreateContainer()`+`waitForHealthy()`, (5) set owning
    session `activity='none'`, `stage='lobby'` + persist, (6) `emitPartyState`,
    (7) `lease.releaseLease` (→`free`). Retries 2-4 up to 3×. No-lease → no-op.
Verify: `node --test app/server/neko/teardown.test.js` — call order (cleaning before
release), idempotency, retry, no-op; a concurrent `acquireLease` during `cleaning` is
rejected. (FR-010, FR-005a, FR-009, SC-006 contract, finding #13.)

### Task C7: Start / stop browser socket events (serialization + rollback + states)
Files: modify `app/server/index.js` (handlers near `party:selectMedia` ~511; per-party
serialization like existing `enqueuePlaybackTrackChange`). Depends on C5b for stop authz.
Interfaces:
  - `party:startBrowser (_p, ack)` — member of a lobby party: `assertNekoEnabled()` else
    `ack({error:'browser disabled'})`; serialize; `canStartBrowser` guard; `acquireLease`
    — `{ok:false}` → `ack({error:'busy', message:'In use by '+hostName})`, create nothing
    (SC-002). Else (state now `starting`): recreate+wait clean container →
    `setControlLock(true)` → `setBrowserActivity(on)` → persist → `lease.markActive` →
    start idle monitor for this party (C9) → `emitPartyState` → `ack({ok:true})`. **Any
    failure after acquire → `teardownBrowser` (rolls back to `free`) + `ack({error})`.**
  - `party:stopBrowser (_p, ack)` — host OR `controller.isController` only (C5b, FR-007b):
    serialize; `teardownBrowser(id,{reason:'stop'})`; `ack({ok:true})`.
Verify: `node --test app/server/neko/browser-flow.test.js` (scratch Socket.IO,
`WP_TEST_MODE=1`, mocked neko adapters) — start-when-free → `active`; start-when-busy from
a 2nd party → synchronous `{error:'busy', message}` and nothing created; recreate-failure
rolls back to `free`; non-host/non-controller stop → denied. (US-1, US-2, FR-003/004/007,
SC-002.)

### Task C8: Wire teardown into every party-deletion path
Files: modify `app/server/index.js` — `party:end` (~437), failed `party:create` (~321),
host-loss expiry (~868), `party:backToLobby` (~544, when `isBrowserActive` — with the
same host/controller authz as C7, finding #9), and `session.js` restore-grace expiry
(~99). Each path: if `getLease()?.partyId === sess.id` → `await teardownBrowser(sess.id,
{reason})` before `deleteSession`.
Verify: `node --test app/server/neko/teardown-wiring.test.js` — each deletion path invokes
teardown exactly once when the lease is held, never otherwise. (FR-010, US-4.)

### Task C9: Process-level idle monitor (finding #10)
Files: create `app/server/neko/idle.js` + `.test.js`; start it once after startup
reconciliation (C4) in `index.js`, and (re)bind it to the active lease from C7.
Interfaces (Consumes `admin.listSessions`, `lease.{getLease,sessionsFor}`,
`teardownBrowser`, `idleTimeoutMs`):
  - `startIdleMonitor({ intervalMs, now } = {}) → handle` — one process-level loop. Each
    tick: if a lease is `active`, count only sessions **recorded for that lease**
    (`sessionsFor`) that are connected (or `is_watching` if the spike shows
    connected-but-idle is common — A0 item 5). Zero for a continuous `idleTimeoutMs`
    window → `teardownBrowser(partyId,{reason:'idle'})`. Reset the timer on any viewer
    reconnect and on lease `generation` change. On `listSessions()` failure: log, skip
    the tick, do NOT count as idle. Runs for a lease restored by reconciliation, not only
    one started via C7 (finding #10).
  - `stopIdleMonitor(handle) → void`.
Verify: `node --test app/server/neko/idle.test.js` (fake clock) — zero-across-window →
teardown; reconnect resets; generation change resets; a restored lease is monitored;
`listSessions` failure doesn't trigger teardown. (FR-008, US-4, SC-003.)

### Task C10: Per-user viewer-session broker endpoint (idempotent)
Files: create `app/server/neko/routes.js` (`registerNekoRoutes(app, io)`); register in
`index.js` ~211.
Interfaces — `POST /api/party/:id/browser/session` (`requireAuth`): reject `!enabled`;
404 missing party; 403 non-member; 409 if lease not `active` for this party. Derive
username `wp-<userId>`. **Idempotency (finding #4):** before minting, delete any prior
recorded Neko session for `(partyId, userId)` (`admin.deleteSession`) then `loginViewer`;
`recordUserSession(partyId, currentGeneration, userId, sessionId)` — the generation
stamp means a session from a previous container generation can never be reused. Set the
returned `NEKO_SESSION` cookie on OUR response scoped to `/neko`; body returns
`{ wsUrl: publicWs }` only — never password/admin token/raw Neko token.
Verify: `node --test app/server/neko/routes.test.js` — authz matrix (403/409/200); double
POST leaves exactly one recorded session; cookie relayed `Path=/neko`; secret-free body;
`NEKO_ENABLED=false` rejected; lease not `active` → 409. (FR-005/005a, US-6, SC-001
backend half, SC-004, SC-005, finding #4.)

### Task C11: Same-origin Neko proxy — allow-list, feature-gated (findings #3/#7/#8/#12)
Files: modify `app/server/index.js` (add `/neko` proxy near `/livekit` ~147-158 + upgrade
handler ~156; add `/neko` to SPA-fallback exclusion ~247 and SERVE_CLIENT prefixes).
Interfaces: middleware chain BEFORE the proxy, in order: (1) `assertNekoEnabled` gate →
403 when disabled (finding #7); (2) `requireAuth` → 401; (3) party-membership + lease
`active`-state check (requester's session must be the `active` lease party) on HTTP AND
WS upgrade; (4) **allow-list** router — forward ONLY the paths captured in A0 item 8
(static assets, `/api/ws`, specific bootstrap endpoints); everything else → 403,
including `/metrics`, `/api/profile`, `/api/room/control*`, legacy `/ws`, and any request
carrying `usr`/`pwd`/`token` query params (finding #12). Then
`createProxyMiddleware({target:internalUrl, changeOrigin:true, ws:true, pathRewrite})`
with path-prefix handling per A0 item 8 (finding #8). WS upgrade wired into
`httpServer.on('upgrade')` alongside `/livekit`. Logging redacts cookies/tokens. Media
NOT proxied (FR-013).
Verify: `node --test app/server/neko/proxy.test.js` — disabled→403; unauth→401;
non-lease-member→403; `/neko/metrics`,`/neko/api/room/control/reset`,`?token=x`,legacy
`/ws`→403; allow-listed path from active-lease member→forwarded (mock upstream).
(FR-006a, FR-012, FR-013, US-8 proxy half.)

### Task C12: Neko-enforced control socket events (request / assign / revoke)
Files: modify `app/server/neko/routes.js`; register socket events in `index.js`. Depends
on C5b (`controller.js`).
Interfaces (Consumes admin control fns + C5b + lease mapping):
  - `browser:requestControl (_p, ack)` — any member of the active-lease party when none
    held: `controlStatus()`; if `!hasHost` → `giveControl(requesterNekoSessionId)` →
    broadcast `browser:control {controllerUserId}`; else `ack({error:'held'})`. Members
    can't self-seize (lock on; only backend gives — FR-006a).
  - `browser:assignControl ({userId}, ack)` — host only: `giveControl(targetNekoSessionId)`
    (revokes prior at Neko level), broadcast.
  - `browser:revokeControl (_p, ack)` — host only: `resetControl()`, broadcast
    `browser:control {controllerUserId:null}`.
Verify: `node --test app/server/neko/control.test.js` (mock admin) — request-when-free
assigns; when-held denied; host reassign revokes prior; non-host cannot assign;
`currentController` reflects Neko truth. Live/pinned-container check per A0 item 3.
(FR-006/006a, FR-007b, US-3, SC-008.)

### Task C13: Reject media mutation while `remote-browser`
Files: modify `app/server/index.js` — `party:selectMedia` (~511), `party:setPlaybackTracks`
(~558) and any media-mutation handler: if `isBrowserActive(sess)` → `ack({error:'browser
active'})`, no state change (rejects any client incl. legacy — US-9 protection). (The
legacy snapshot fallback itself now lives in B0's `publicSessionFor`.)
Verify: `node --test app/server/neko/legacy-compat.test.js` — `selectMedia` while
`remote-browser` returns `{error:'browser active'}`, `activity` unchanged. (FR-007, US-9
server half.)

### Task C14: Web client — capability flag, full flow, render branch (findings #1/#2)
Files: modify `app/client/src/hooks/useSocket.ts:6-12` (add `auth:{caps:{remoteBrowser:
true}}` — finding #1); modify `app/client/src/types.ts` (add `activity?: 'none'|
'remote-browser'` to `PartySession`; add `startBrowser/stopBrowser/requestControl/
assignControl/revokeControl` to `PartyContextValue`); modify
`app/client/src/context/PartyContext.tsx` (implement those methods as socket emits with
ack handling — finding #2); modify `app/client/src/pages/Party.tsx` (lobby: add a
"Start shared browser" button emitting `party:startBrowser`, surfacing
busy/disabled/error acks; add a branch before `stage==='lobby'` ~136 that renders
`RemoteBrowser` when `activity==='remote-browser'`); create
`app/client/src/pages/RemoteBrowser.tsx` (on mount POST the session endpoint with
loading + error states; `<iframe src="/neko/">`; controller display; request-control
button; host assign/revoke UI; stop button gated to host/controller).
Verify: `cd app/client && npm run build` + `npm run lint`; manual live on `contab`:
lobby→start→embed renders (not the player), busy message shows for a 2nd party, control
request/assign/revoke reflect, stop returns to lobby. (US-1/3/4, FR-012 client, US-9 web,
SC-001 client half, findings #1/#2.)

### Task C15: Flutter — capability flag + explicit unsupported state (finding #1)
Files: modify `flutter_app/lib/net/socket_client.dart:123-140` (`socketOptionsFor()`
add `.setAuth({'caps': {'remoteBrowser': true}})` — finding #1); modify
`flutter_app/lib/models/party_state.dart` (add `@Default('none') String activity;`,
regenerate freezed); modify the party screen that switches on `stage` to show the verbatim
`remote browser not supported on this client` when `activity=='remote-browser'`.
Verify: `cd flutter_app && flutter analyze`; manual: updated Flutter shows the unsupported
message; a truly legacy build (no caps) receives `stage:'lobby'` (B0 fallback) and shows
the library harmlessly. (US-9 Flutter, finding #1.)

### Task C16: Vite dev-proxy `/neko` → backend (finding #3)
Files: modify `app/client/vite.config.ts` — add `/neko` to `server.proxy` targeting the
**Watchparty backend** (`http://localhost:3000`, `ws:true`, `changeOrigin:true`), NOT
Neko directly, so C11's single authorization path applies in dev too.
Verify: `cd app/client && npm run build`; manual dev: `/neko` requests carry the session
cookie to the backend and are authorized there before reaching Neko; an unauthenticated
`/neko/api/...` is rejected by the backend. (FR-012 dev-proxy, finding #3.)

### Task C17: Pinned Neko integration fixture (finding #11)
Files: create `app/server/neko/fixture/docker-compose.test.yml` (version-pinned Neko
image, ephemeral ports) + `docs/ops/neko-test-fixture.md`; create
`app/server/neko/integration.test.js` (guarded by env `NEKO_IT=1`, skipped in default
`node --test`).
Interfaces: the integration test stands up the pinned container and asserts against a
REAL Neko: session deletion closes WS/WebRTC (A0#4), control lock + admin give/reset
(A0#3, SC-008), container recreate isolation (A0#6, SC-006), cookie/path-prefix behavior
where practical (A0#8).
Verify: `NEKO_IT=1 node --test app/server/neko/integration.test.js` passes locally/CI
runner with Docker. **Default CI and the mocked unit suites never touch production
`contab`** (spec Test strategy). (SC-006, SC-008 real proof; finding #11.)

---

## Success-criteria coverage
- SC-001 → C7+C10+C14 (+manual live). SC-002 → C7. SC-003 → C9. SC-004 → B0+C10.
  SC-005 → C1+C7+C10+C11. SC-006 → C3/C6 + **C17 real proof**. SC-007 → C4 reconciliation.
  SC-008 → C12 + **C17 real proof**.

## FR coverage
FR-000→A0; FR-001→C5; FR-002/002a→C4; FR-003/004→C7; FR-005/005a→C10(+C2);
FR-006/006a→C12(+C11); FR-007/007b→C5/C7/C12/C13(+C5b authz); FR-008→C9; FR-009→C3/C3b/C6;
FR-010→C6/C8; FR-011→B0; FR-012→C11/C14/C16; FR-013→C11; FR-014/015→C1.

## Dependency / ordering
- Phase A (A0) and Phase B (B0) precede all Phase C.
- `[P]` parallel: C1, C2, C3. C3b after C3. 
- C4, C5, C5b, C6 precede C7/C8/C9. C5b precedes C7 (stop authz) and C12.
- C10, C11 precede C12/C14. C14 depends on C10/C11/C12 events; C16 pairs with C11.
- C17 (fixture) can be built in parallel once A0 fixes the pinned version; it gates the
  *real* verification of SC-006/SC-008 (C6/C12).

## CI note
A0 needs live `contab`. C17 provides the pinned-container fixture for SC-006/SC-008.
**CI must never point at production `contab`.**
