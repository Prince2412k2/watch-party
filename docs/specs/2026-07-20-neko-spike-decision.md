# A0 Spike Decision Record — Neko Collaborative Browser

> Task A0 of `docs/plans/2026-07-20-neko-collab-browser.md`.
> **Method:** live probes against a local, pinned Neko `3.1.4` container
> (`docker-compose.neko.yml`, image `ghcr.io/m1k1o/neko/firefox:3.1.4`), run in
> isolation (no servarr/app stack). Probes issued from a throwaway curl container
> sharing Neko's network namespace (`--network container:neko-spike`, `localhost:8080`).
> Date: 2026-07-20.

## Result summary

| # | Item | Verdict | Mechanism / evidence |
|---|------|---------|----------------------|
| 1 | Credential-free iframe auth | **PASS** (needs cookie enabled) | `Set-Cookie: NEKO_SESSION=…; HttpOnly; Secure; SameSite=None` when `NEKO_SESSION_COOKIE_ENABLED=true` |
| 2 | Two-credential model | **PASS** | admin pw → `is_admin:true`; user pw → `is_admin:false`; both `can_host:true`. `NEKO_SESSION_API_TOKEN` = synthetic admin bearer |
| 3 | Control enforcement (API) | **PASS** | `POST /api/room/settings {locked_controls:true}` → 204, reflected in GET; `control/reset` → 204; `GET /api/room/control` → 200 |
| 4 | Session deletion | **PASS** | `DELETE /api/sessions/{id}` → 204, session count decremented |
| 5 | Viewer detection | **PASS** | `/api/sessions[].state.{is_connected,is_watching}` present |
| 6 | Clean reset via recreate | **PASS** | `--force-recreate` → new container id, marker GONE; `docker restart` preserves marker (no isolation). ~8–19s wall |
| 7 | Version ≥ 3.1.2 | **PASS** | pinned `3.1.4` (> 3.1.1 CVE floor GHSA-2gw9-c2r2-f5qf) |
| 8 | Path-prefix serving | **PASS** | `NEKO_SERVER_PATH_PREFIX=/neko`: `/neko/`→200, `/`→404, `/neko/api/*` works, assets relative |
| — | WebRTC media render + input rejection | **MANUAL** | Requires a real browser + working ICE; not provable via curl. Deferred to manual live acceptance (see below) |

## Detail

### 1 — Credential-free iframe auth (PASS, requires cookie enabled)
By default Neko returns the session token **in the JSON body** with **no `Set-Cookie`**
(same as observed on `contab`). Setting `NEKO_SESSION_COOKIE_ENABLED=true` makes
`POST …/api/login` emit:
```
Set-Cookie: NEKO_SESSION=<token>; Expires=…; HttpOnly; Secure; SameSite=None
```
- **HttpOnly** → the embedded iframe's JS cannot read/exfiltrate the token. Good.
- **Secure** → cookie only travels over HTTPS ⇒ our same-origin proxy must be HTTPS
  (Caddy already provides this in prod; dev proxy must terminate/allow accordingly).
- **SameSite=None** → survives the cross-context iframe embedding.
- No explicit `Path`/`Domain` in the default cookie ⇒ the backend broker must relay it
  **scoped to `/neko`** (rewrite `Path=/neko` on relay, or set `NEKO_SESSION_COOKIE_*`).
- **Design confirmed:** backend logs in server-side with the shared non-admin password,
  captures the `Set-Cookie`, and relays it on our origin scoped to `/neko`. No
  `usr`/`pwd`/`token` ever appears in a client-visible URL.

### 2 — Two-credential model (PASS)
`/api/login` profile objects: admin password → `is_admin:true, can_host:true`; user
password → `is_admin:false, can_host:true`. **Both roles have `can_host:true`** — so a
global control lock is mandatory (item 3), matching the plan (FR-006/006a).
`NEKO_SESSION_API_TOKEN` authorizes admin REST as a synthetic always-admin bearer.

### 2b — Admin API auth (PASS)
`GET /api/sessions`: session-token bearer → 200, `NEKO_SESSION_API_TOKEN` bearer → 200,
`?token=` query → 200, **no auth → 401**. The server-only `NEKO_SESSION_API_TOKEN` is the
credential the backend uses for admin ops (session/control administration).

### 3 — Control enforcement (PASS at API level)
Real field is **`locked_controls`** (also separate `control_protection`). Setting it via
`POST /api/room/settings` returns 204 and is reflected in `GET /api/room/settings`.
`POST /api/room/control/reset` → 204. Admin give/reset therefore operate while the lock
is on. **Note:** actual rejection of a non-controller's data-channel *input* needs a real
browser — see MANUAL below.

### 4 — Session deletion (PASS)
`DELETE /api/sessions/{id}` → 204; session disappears from the list. Sessions
**accumulate** across logins, so teardown/detach must explicitly delete each recorded
session (matches plan FR-005a / C6 / C8b).

### 5 — Viewer detection (PASS)
`/api/sessions` returns `state.is_connected` and `state.is_watching` per session. Use
`is_watching` as the "active viewer" signal; poll 2–5s (plan C9 idle monitor).

### 6 — Clean reset via recreate (PASS — the isolation crux)
- Marker written into the container's writable layer **survives `docker restart`** ⇒
  restart alone does NOT isolate.
- `docker compose … up -d --force-recreate` yields a **new container id** and the marker
  is **GONE** ⇒ clean ephemeral browser for the next party. Wall time ~8–19s (incl.
  health wait). This validates the plan's container-recreate reset (FR-009) and the SSH
  forced-command that wraps exactly this command (C3/C3b).

### 7 — Version (PASS)
Pinned `ghcr.io/m1k1o/neko/firefox:3.1.4` ≥ 3.1.2. The plan's "never `:latest`, pin ≥
3.1.2" is satisfied by this tag.

### 8 — Path-prefix (PASS)
`NEKO_SERVER_PATH_PREFIX=/neko`: `/neko/` → 200, `/` → 404, `/neko/api/login` → 200, and
the client's asset refs are **relative** (`js/app.*`, `css/app.*`) so they resolve
correctly under the prefix. **Design confirmed:** run Neko with `path_prefix=/neko` and
the same-origin proxy forwards `/neko/*` — no fragile absolute-path rewriting needed.
Allow-list (C11) = `/neko/` + hashed `js/*`,`css/*` + icons/manifest + `/neko/api/ws` +
the specific bootstrap `/neko/api/*` calls (exact hashed bundle names captured live:
`js/app.4919abb0.js`, `js/chunk-vendors.025e045d.js`, plus `-legacy` variants — these
change per build, so allow-list by directory prefix, not exact filename).

## GO / NO-GO

**GO.** Every source-inspectable and curl-testable assumption passed live against a
pinned 3.1.4 instance. No structural blocker. The container-recreate isolation (the
highest-risk item) works.

## Confirmed plan amendments (fold into the plan / deploy config)

- **Deploy env (required when `NEKO_ENABLED=true`)**: `NEKO_SESSION_API_TOKEN`,
  `NEKO_SESSION_COOKIE_ENABLED=true`, `NEKO_SERVER_PATH_PREFIX=/neko`, plus the existing
  `NEKO_WEBRTC_*`, `NEKO_MEMBER_MULTIUSER_*`. (C1 `validateNekoConfig` should require
  these.)
- **Cookie relay (C10)**: relay `NEKO_SESSION` scoped to `Path=/neko`; the cookie is
  `Secure` ⇒ the `/neko` proxy path must be served over HTTPS (prod Caddy ✓; dev must
  account for `Secure`).
- **Proxy (C11)**: serve Neko under `path_prefix=/neko`; allow-list by directory prefix
  (`/neko/js/`, `/neko/css/`, icons, `/neko/api/ws`, specific `/neko/api/*` bootstrap),
  not exact hashed filenames.
- **Isolation (C3/C6)**: reset = `docker compose up -d --force-recreate` (NOT
  `docker restart`); budget ~8–20s for the health-ready gap.
- **Control (C6/C12)**: field is `locked_controls`; set it true on session start.

## Remaining MANUAL live acceptance (not curl-testable)

Run once against a real browser (local `docker-compose.neko.yml` at `http://localhost:9876`
with `NAT1TO1=127.0.0.1`, or the tailnet instance):
1. Video/audio actually renders in a browser (WebRTC media path over ICE).
2. With `locked_controls:true` + two logged-in `can_host` users, a **non-controller's
   mouse/keyboard input is actually rejected** (SC-008 input half).
3. `DELETE /api/sessions/{id}` tears down that peer's live WS **and** WebRTC media.

## Repro
- Bring up: `docker compose -f docker-compose.neko.yml up -d`
- Probe harness pattern: `docker run --rm --network container:neko-spike curlimages/curl -s http://localhost:8080/...`
- Tear down: `docker compose -f docker-compose.neko.yml down`
