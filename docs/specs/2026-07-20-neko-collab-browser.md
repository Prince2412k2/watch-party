# Spec: Neko Collaborative Browser (v1 — single global instance)

## Context

Add a shared, collaboratively-controlled remote browser to Watchparty parties, backed
by a self-hosted Neko instance (Docker, WebRTC streaming — see prior session notes).
v1 scope is deliberately narrow: **one global Neko container for the whole deployment**,
usable by exactly one party at a time. Multi-instance concurrency and persistent
per-host browser profiles are explicit non-goals (deferred to a later orchestration
phase — see Out of scope).

This spec was revised twice after architecture review. Three properties must be enforced
**inside Neko**, not merely tracked in Watchparty state:
1. **Auth** — the embedded browser is authenticated without exposing Neko credentials.
2. **Isolation** — successive parties must not inherit each other's browser state.
   Because Neko cannot safely hot-swap/wipe the profile of a running browser, isolation
   in v1 is achieved by **recreating the Neko container** between lease owners (container
   lifecycle is therefore in scope; per-party orchestration is not).
3. **Control** — Watchparty's controller lease is backed by Neko's own control lock +
   admin control API, or it is only advisory.

## Phasing

- **Phase A (spike, blocking):** prove the auth, control, session, isolation, and
  version assumptions against the live Neko instance on `contab` before Phase C
  implementation. See US-0 / FR-000.
- **Phase B (prerequisite refactor, blocking):** replace `publicSession()`
  exclusion-based sanitization with an allow-listed DTO. See US-7 / FR-011.
- **Phase C (feature):** everything else.

## User stories

### US-0 (P1, spike): Prove the risky Neko assumptions
As the implementing engineer, I prove — with a throwaway spike against the live Neko
instance — the assumptions that would otherwise sink the build, before Phase C
implementation is planned in detail.
- **Independent test**: a spike script/page demonstrates each item below against
  `contab`.
- The spike MUST prove all of:
  1. **Credential-free iframe auth** on our own origin (backend brokers session; no
     `usr`/`pwd` in any client-reachable URL/response). Candidate mechanisms: (a)
     same-origin cookie broker relaying Neko's `Set-Cookie` with correct domain/path,
     or (b) token-aware Neko bootstrap. Password-in-URL is rejected.
  2. **Two-credential model**: a server-only admin/API token for administration AND a
     non-admin login credential used to mint one viewer session per user (see FR-005).
  3. **Control enforcement**: users given `can_host=true`, Neko's **global control lock**
     enabled, and admin `control/give` + `control/reset` still function while the lock
     is active; a non-controller's input is rejected.
  4. **Session deletion** disconnects the target's WebSocket AND WebRTC.
  5. **Viewer detection**: a reliable signal for "N connected/watching viewers".
  6. **Safe reset**: container recreation yields a verifiably clean browser (no
     inherited cookies/logins/downloads/history).
  7. **Version check**: `contab` Neko is ≥ `3.1.2` (versions ≤ `3.1.1` have an
     authenticated privilege-escalation advisory, GHSA-2gw9-c2r2-f5qf); upgrade if not.
- Outcome recorded in `docs/native/` or `docs/specs/`; the chosen mechanisms become the
  committed design. Failure of any item is the go/no-go stop point.

### US-1 (P1): Start a shared browser session
As a party member, I can start a "remote browser" activity so everyone in the party
watches the same live browser session together.
- **Independent test**: from lobby, trigger "start browser", see `activity.kind` become
  `remote-browser` and a viewable stream appear for all members.
- Given a party in lobby (no active media) and the global Neko lease free,
  When any party member starts the browser activity,
  Then the lease is acquired, a clean container is ready, its activity becomes
  `remote-browser`, and members can view via an authenticated same-origin embed.

### US-2 (P1): Told when the browser is busy
As a party member, if another party is already using the shared browser, I see a clear
busy message naming the holding party's host, instead of a broken/silent failure.
- Given the global lease is held by Party A,
  When a member of Party B tries to start the browser activity,
  Then Party B is shown "In use by <Party A host's display name>" and no session is
  created for Party B.

### US-3 (P1): Neko-enforced single-controller lease
As a party member I can request control so I'm the only one whose input reaches the
browser; as host I can reassign/revoke at any time — enforced by Neko, not just UI.
- **Independent test**: two members connected; only the controller's input reaches the
  browser and a non-controller cannot drive it.
- Given member X holds control,
  When member Y requests control,
  Then Y is denied until X releases, UNLESS the host reassigns control to Y (X's control
  is immediately revoked at the Neko level via admin `control/give`).
- Given Neko's global control lock is on and members have `can_host=true`,
  When control changes,
  Then only the backend (admin) assigns/revokes it; members cannot self-seize control.

### US-4 (P2): Session ends, container is recycled and freed
As a host or the current controller, I can stop the browser activity; it also ends when
the party ends or after an idle period with no connected viewers. On release the
container is recreated (clean) and the lease is freed.
- **Independent test**: start a session, log into a site / create a download, stop, then
  start a new session as a different party and confirm prior state is gone.
- Given the browser activity is active,
  When the host or current controller stops it, OR the party ends, OR the idle window
  elapses with zero connected viewers,
  Then all Neko sessions for that party are deleted, the container is recreated (clean
  ephemeral profile), the lease is released, and the party returns to lobby.

### US-6 (P2): No exposed Neko credentials; separated privileges
As a security requirement, clients never see raw Neko credentials or an admin-capable
session; access is gated through the existing Jellyfin-backed session.
- Given a member of the party holding the lease with a valid Jellyfin-backed session,
  When their client requests a browser connection,
  Then the backend uses a **non-admin login credential** to mint a **distinct viewer
  session per user** (username derived per Watchparty user), administered via the
  **server-only admin/API token**, and brokers only that viewer session to the client;
  the Neko password and admin token are never returned to the client.

### US-7 (P1, prerequisite): Fix existing session credential leak
As a security prerequisite, Watchparty stops leaking Jellyfin `token`/`deviceId`/
`socketId` (nested in `guests[]`/`waiting[]`, plus `hostDeviceId`/`hostSocketId`) before
browser session data is added next to it.
- **Independent test**: any `publicSession()`-derived payload contains only allow-listed
  fields.
- Given the current exclusion-based `publicSession()` (`session.js:287-294`),
  When it is replaced with an explicit allow-listed DTO,
  Then no client-facing payload contains any auth token, device id, or socket id (host,
  guests, or waiting).

### US-8 (P3): Feature can be disabled
As an operator, I can disable the feature via config so Watchparty makes zero Neko
interactions and all browser access is unreachable.
- Given `NEKO_ENABLED=false`,
  When any client attempts to start/view/query the browser activity,
  Then it is rejected and no Neko interaction occurs. (Controls Watchparty
  access/interactions only; the independently-managed container's own cost is out of
  Watchparty's control.)

### US-9 (P2): Client compatibility (web + Flutter)
As a user on either client, the app behaves correctly when a party is in
`remote-browser` mode.
- **Independent test**: put a party in `remote-browser`; web renders the browser embed
  (not the Jellyfin player); updated Flutter shows an explicit unsupported state; legacy
  Flutter shows a safe fallback and cannot hijack the activity.
- Given a party in `remote-browser`,
  When the web client renders,
  Then it uses a dedicated remote-browser branch, not the Jellyfin player path.
- Given an **updated** Flutter client,
  When it receives `remote-browser` state,
  Then it shows an explicit "remote browser not supported on this client" state.
- Given a **legacy** Flutter client that only understands `lobby|watching`,
  When the party is in `remote-browser`, the server MUST present a safe fallback (e.g.
  `stage: lobby`) so the old client shows the library harmlessly, AND reject any media
  mutation events it emits so it cannot terminate/replace the browser activity. (A
  legacy client cannot render the new explanatory message; that is accepted.)

## Functional requirements

### Auth & credentials
- **FR-000** (spike): System MUST validate all US-0 spike items against live Neko before
  Phase C implementation. Container recreation is the committed reset mechanism.
- **FR-005**: System MUST expose a backend endpoint (e.g.
  `POST /api/party/:id/browser/session`) that, for an authenticated Jellyfin-session
  member of the lease-holding party, uses a **non-admin login credential** to obtain a
  **distinct viewer session per user** (unique per-user username), with member/session/
  control administration performed via a **separate server-only admin/API token**, and
  brokers only the viewer session to the client via the FR-000 mechanism. The Neko
  password and admin token MUST NOT reach the client.
  - v1 uses the `multiuser` provider: backend holds the admin/API token and the shared
    non-admin password, logging in a unique username per Watchparty user. (`file`
    provider with temporary members is an alternative evaluated in the spike.)
- **FR-005a**: System MUST explicitly delete each per-user Neko session on
  release/teardown (Neko sessions default ~24h; do not rely on expiry).
- **FR-011** (prerequisite): System MUST replace `publicSession()` exclusion-based
  sanitization with an explicit allow-listed DTO. Blocking prerequisite for Phase C.
- **FR-012**: Web client MUST embed the Neko stream via an authenticated same-origin
  proxy (new Neko HTTP + WebSocket proxy routes alongside Jellyfin/LiveKit), with
  party-membership authorization on HTTP requests and WS upgrades, path-prefix/static
  handling, Vite dev-proxy config, and proxy log redaction. The proxy MUST deny/filter
  `/metrics`, `/api/profile`, administrative control APIs, the legacy `/ws` endpoint,
  and any `usr`/`pwd`/token query parameters. WebRTC **media** is NOT proxied (FR-013).
- **FR-013**: ICE topology — Neko signaling goes through the same-origin proxy; WebRTC
  media uses Neko's UDP EPR range reachable directly over the tailnet (current `contab`
  setup) or via TURN. "Hidden from public network" applies to signaling/control, not
  media transport.

### Lease, activity & isolation
- **FR-001**: System MUST add `remote-browser` as a new party activity kind, mutually
  exclusive with Jellyfin playback.
- **FR-002**: System MUST track a single global lease (which party, if any, holds the
  shared Neko instance).
- **FR-002a**: The lease MUST be stored durably (alongside the SQLite party store) and
  MUST persist a **per-user Neko session mapping / correlation metadata** so startup
  reconciliation can attribute live Neko sessions to the owning party; reconcile on
  startup against persisted party state and live Neko sessions so a restart/crash cannot
  leave a dangling lease, orphaned sessions, or double ownership.
- **FR-003**: When a party requests start from lobby and the lease is free, system MUST
  acquire it, ensure a clean container, and transition that party to `remote-browser`.
- **FR-004**: When the lease is held by a different party, system MUST reject the request
  identifying the holding party's host display name.
- **FR-007** (transition model): v1 supports only `lobby/none ↔ remote-browser`.
  - Allowed: `none/lobby → remote-browser`, `remote-browser → lobby`.
  - A party MUST explicitly stop the browser activity before selecting Jellyfin media,
    and MUST be in lobby before starting the browser. Direct `jellyfin ↔ remote-browser`
    switching is NOT supported (no "prior activity" preservation).
  - Server MUST reject `party:selectMedia` while `remote-browser` is active, and reject
    browser start while `stage: watching`.
  - Starting browser = acquire lease → ensure clean container → provision Neko access →
    set activity; failure at any step rolls back prior steps (release lease if a later
    step fails). Concurrent start/stop/media-selection requests for a party MUST be
    serialized.

### Control
- **FR-006**: System MUST enforce a single active controller (or none) via Neko's global
  control lock + admin `control/give`/`control/reset`, backed by distinct per-user
  sessions with `can_host=true`; Neko's active controller is authoritative.
- **FR-006a**: With the global control lock enabled, members cannot self-seize control;
  only the backend (admin) assigns/revokes. The proxy MUST additionally block direct
  Neko control endpoints from clients as defense in depth.
- **FR-007b**: Any member MAY request control when none is held; the host MAY
  reassign/revoke at any time. Stopping the whole browser activity is allowed for the
  host OR the current controller only.

### Isolation & lifecycle
- **FR-008** (idle signal): System MUST define "zero viewers" using an actual Neko
  connection signal (session polling and/or proxied-WebSocket lifecycle) with a
  reconnect grace period — NOT Socket.IO party membership. Default idle window 5 min,
  configurable (`NEKO_IDLE_TIMEOUT_MS`).
- **FR-009** (clean reset via recreate): On lease release, system MUST perform a verified
  clean reset by recreating the Neko container so the next party gets a clean ephemeral
  profile (no inherited cookies/logins/downloads/history). Per-user Neko sessions are
  deleted and control reset as part of this.
- **FR-010** (centralized teardown): System MUST route all browser teardown through a
  single idempotent service invoked from every party-deletion path (`party:end`, failed
  create, host-loss expiry, restore expiry, idle expiry, explicit stop). It MUST
  perform: Neko session revocation → control reset → container recreation → lease
  release, with retry on failure and safe re-entry.

### Config
- **FR-014**: System MUST gate the feature behind `NEKO_ENABLED` (env var, matching the
  inline `process.env.X` pattern); when false all browser endpoints/socket events
  reject/no-op with no Neko contact.
- **FR-015**: `NEKO_CONCURRENCY_ENABLED` name is reserved, defaults off, no
  implementation in v1 (documented placeholder only).

## Success criteria

- **SC-001**: A party starts, uses, and stops a shared browser end-to-end with zero
  manual Neko credential handling.
- **SC-002**: A second party attempting to start while busy receives a busy response in
  the same request/response cycle naming the holding host (no hang/crash).
- **SC-003**: A stale/abandoned session (idle, no Neko viewers) auto-releases within the
  configured idle window; verified with fake timers / shortened timeout.
- **SC-004**: No browser-related endpoint response — and no `publicSession()`-derived
  payload — contains a raw Neko password, Neko admin token, Jellyfin token, device id,
  or socket id.
- **SC-005**: `NEKO_ENABLED=false` makes all browser endpoints unreachable (automated
  test asserts rejection).
- **SC-006** (isolation): After a session is released and the container recreated, a new
  session observes a clean browser (no inherited cookies/logins, empty downloads,
  cleared history); verified by an integration test that seeds state then re-acquires.
- **SC-007** (restart recovery): After a simulated restart with a persisted
  `remote-browser` party, startup reconciliation leaves consistent state (lease and Neko
  sessions either both valid or both cleaned); verified by test.
- **SC-008** (control enforcement): A non-controller member cannot drive the browser via
  Neko's own controls; verified against the Neko control API.

## Test strategy

- **Unit**: mocked Neko adapter for lease/transition/teardown/config logic (runs in CI).
- **Integration**: against a **pinned Neko container** fixture (version-locked) for
  SC-006/SC-008 and session/control behavior. CI MUST NOT depend on the mutable
  production `contab` instance.
- **Manual/live acceptance**: on `contab` for real ICE and iframe rendering behavior.

## Out of scope

- Multi-instance concurrency (`NEKO_CONCURRENCY_ENABLED`) — reserved flag, no impl.
- **Persistent per-host browser profiles** (the earlier "persist flag") — deferred to
  the later orchestration phase; requires mounted profile volumes + ownership/quota/
  host-transfer semantics not justified for v1.
- Per-party Neko container provisioning/orchestration (multiple simultaneous rooms).
- Flutter **native Neko client** (separate future effort). v1 Flutter only gets the
  compatibility behavior (US-9).
- DRM/streaming-site compatibility testing.
- Rotating/short-lived Neko instance passwords (v1 uses the static admin credential
  server-side; per-user sessions are the client-facing scoping mechanism).
- FIFO control-request queue UI (only immediate request + host override).
- New Neko deployment beyond container recreation of the existing `contab` instance.

## Assumptions

- The running Neko instance on `contab` (`NEKO_WEBRTC_NAT1TO1` fixed, verified) is the
  v1 target; its `multiuser` admin password becomes the server-only credential and its
  user password the non-admin login credential. Version ≥ 3.1.2 confirmed in the spike.
- Container recreation is available to the backend (Watchparty can invoke a controlled
  recreate of the single Neko container — mechanism decided in the plan, e.g. a narrow
  helper, never a raw Docker socket exposed to the public app).
- "Party name" in the busy message is the current host's display name (Watchparty has no
  stable party title). [A generic "browser is in use" message is an accepted
  alternative if host-identity disclosure is later deemed undesirable.]
- Lease/reconciliation reuses the single-process + SQLite durability model; no
  distributed lock needed.
- Idle default 5 min lives in config and is tunable without code changes.
