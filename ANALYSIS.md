# Watch-Party Codebase Audit

_Read-only audit across **Security**, **Correctness**, **Code Quality**, and **Gaps** (robustness/ops). Every finding was adversarially verified by an independent agent; each carries a **CONFIRMED** (reproduced in real code) or **PLAUSIBLE** (likely, not fully proven) tag. 49 findings survived verification; 2 were rejected (the Jellyfin↔Servarr media-path mismatch — already fixed by the `/servarr-media` read-only mount — and the "host autoplay-kick omits markApplying" claim — that re-authoring is intended host-authority re-sync)._

## Overall health

Functionally the app is in good shape and the sync engine is far more disciplined than a typical first pass. **The dominant risk is not logic bugs — it's that a LAN/dev-grade security posture is being exposed to the public internet via the Tailscale Funnel.** Committed default secrets, unauthenticated internal-service proxies, and no auth rate-limiting are the real exposure. A secondary theme is heavy copy-paste across the three desktop pages that is already drifting into divergent behavior.

### Top 5 to fix first

1. **Rotate the LiveKit keys** — `livekit.yaml` + `.env` ship the public `devkey`/`devsecret…` dev defaults. Anyone can forge room tokens and join/eavesdrop on any party's cameras + mics. **(CRITICAL)**
2. **Rotate `SESSION_SECRET`** — it is the committed literal `changeme`. The session-cookie HMAC key is public knowledge, so cookies can be forged/tampered on a public endpoint. **(HIGH)**
3. **Gate the `/jellyfin` and `/livekit` reverse proxies** — they are registered before any auth and forward everything, exposing the entire internal Jellyfin (login, admin) and LiveKit signaling to the internet. **(HIGH)**
4. **Rate-limit `POST /api/auth/login`** — no throttle/lockout on an internet-facing endpoint = unlimited credential stuffing against every Jellyfin account. **(HIGH)**
5. **Make the host play-start idempotent** — a hopping host is exempt from the control loop, so if the schedule arrives before the media element attaches, the host stays paused forever. **(HIGH, correctness)**

### Counts by severity

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 8 |
| Medium | 16 |
| Low | 20 |
| Info | 4 |

---

## 🔒 Security

### S1 · [CRITICAL · CONFIRMED] LiveKit runs on public default dev keys — anyone can forge room tokens
`livekit.yaml:11`, `.env`, `app/server/livekit.js:16`
`livekit.yaml` sets `keys: devkey: devsecret0000000000000000000000000` (the publicly documented LiveKit dev default) and `.env` matches it; the server signs join JWTs with exactly these values. LiveKit signaling is reachable from the internet (the unauthenticated `/livekit` proxy + the published port), so anyone can mint a valid JWT for any room and join/publish to camera+mic sessions, bypassing the `/api/livekit/token` membership check entirely.
**Fix:** Generate a strong random key/secret (`openssl rand -hex 32`), set it in both `livekit.yaml` `keys:` and `.env`, and rotate — the current pair is in git history. Keep secrets out of committed files.

### S2 · [HIGH · CONFIRMED] `SESSION_SECRET` is the committed default `changeme`
`app/server/index.js:55`, `.env:18`, `.env.example`
`session({ secret: process.env.SESSION_SECRET || 'changeme' })` and the live `.env` sets it to the literal `changeme` (also shipped in `.env.example`). The HMAC key that signs `connect.sid` is public, voiding the cookie's integrity guarantee on a publicly-exposed app (forgeable/tamperable sessions; enables fixation — see S8).
**Fix:** Generate a high-entropy secret per deployment; **fail fast at startup** if `SESSION_SECRET` is unset or equals `changeme`.

### S3 · [HIGH · CONFIRMED] Unauthenticated open reverse proxies expose internal Jellyfin + LiveKit
`app/server/index.js:70`
The `/jellyfin` and `/livekit` http-proxy-middleware instances are registered **before** `cookieParser`/`sessionMiddleware` with no auth, and the SPA fallback deliberately lets these prefixes through. Over the public Funnel this exposes the whole internal Jellyfin server (login page, admin dashboard, API) and LiveKit signaling.
**Fix:** Gate both behind `requireAuth` (and room-membership for `/livekit`), or restrict `/jellyfin` to only the path prefixes the player needs (`Videos/*`, `Items/*/Images`).

### S4 · [HIGH · CONFIRMED] No rate-limiting/brute-force protection on the internet-facing auth endpoint
`app/server/auth.js:4`, `app/server/index.js:95`
`POST /api/auth/login` proxies straight to Jellyfin's `AuthenticateByName` with no throttle, lockout, delay, or CAPTCHA, and no `express-rate-limit`/`helmet` in the deps. Reachable publicly via Funnel ⇒ unlimited credential stuffing against every Jellyfin account.
**Fix:** Add `express-rate-limit` on the login route keyed by IP + username (with backoff/lockout) plus a coarse global limiter. Requires fixing `trust proxy` (S6) first so the limiter sees the real client IP.

### S5 · [MEDIUM · CONFIRMED] Per-user Jellyfin access token leaked to the browser
`app/server/jellyfin.js:102`
`/api/library/hls-url` returns a URL with the per-user Jellyfin `api_key` embedded, handing a usable Jellyfin token to client JS (and anywhere the URL is logged/shared).
**Fix:** Proxy playback through the app (server attaches the key), or issue a short-lived scoped token instead of the raw user token.

### S6 · [MEDIUM/LOW · CONFIRMED] Session cookie not `Secure` and `trust proxy` unset behind the HTTPS Funnel
`app/server/index.js` (session config + app setup)
The session cookie is not marked `Secure` and Express `trust proxy` is not set. Behind the Tailscale Funnel (which terminates TLS and forwards over HTTP), `secure` cookies would silently break and the app sees the proxy IP, not the client's — so any IP-based control (rate-limit, logging) is wrong.
**Fix:** `app.set('trust proxy', 1)`, set `cookie.secure` in production, `sameSite:'lax'`, and a sensible `maxAge`.

### S7 · [LOW · CONFIRMED] Test-login bypass + `/api/debug/*` gated only by a single env flag
`app/server/auth.js`, `app/server/index.js`
`/api/auth/test-login` (auth bypass) and `/api/debug/*` (PII/state disclosure) are guarded only by `WP_TEST_MODE`. One misconfigured env var in production fully bypasses auth.
**Fix:** Hard-gate on `NODE_ENV !== 'production'` **and** the flag; refuse to register these routes when `NODE_ENV==='production'`.

### S8 · [LOW · PLAUSIBLE] No session regeneration on login (session fixation)
`app/server/auth.js`
The session id is not regenerated on successful login, so a pre-planted `connect.sid` (feasible given S2) survives authentication — classic fixation.
**Fix:** `req.session.regenerate()` on login before storing the authenticated user.

### S9 · [LOW · CONFIRMED] Unvalidated `type`/`:id` interpolated into the Jellyfin image URL
`app/server/library.js`
Query/path params are interpolated into the internal Jellyfin image URL before `?api_key=`, allowing path/query injection into the internal request.
**Fix:** Whitelist `type` against known image types and validate `:id` as a Jellyfin GUID before building the URL; URL-encode.

### S-INFO · [INFO] Verified-safe (no action)
Server-side secret confinement (Servarr/qBittorrent keys never reach the browser), the image-proxy path-traversal guard (`/MediaCover` only, rejects `..`), and `deploy/connect-servarr.sh` secret handling were audited and found **safe**.

---

## 🎯 Correctness

### C1 · [HIGH · PLAUSIBLE] Hopping host can stay paused forever
`app/client/src/hooks/useSyncPlay.js:188`, `app/client/src/sync/syncCore.js:92`
`decideSyncAction()` short-circuits to `null` for a hopping host, so the 200 ms control loop never touches the host — `onSchedule`'s play-kick is the *only* thing that starts a hopping host's video, and it's edge-triggered on the schedule event and gated on the media element already being attached. If `party:selectMedia` authors a `playing` schedule before the element mounts, the kick is lost and the host never plays.
**Fix:** Make host-start idempotent — re-check `isHost && hopping && schedule.phase==='playing' && video.paused` inside the control loop (or a `canplay`/attach effect) and kick `play()` there.

### C2 · [MEDIUM · CONFIRMED] `sync:seek` force-starts a PLAYING segment, ignoring paused intent
`app/server/index.js:381`
`sync:seek` unconditionally starts a playing segment. A paused host/driver scrubbing the timeline makes the **whole room start playing**.
**Fix:** Preserve `intent.playing` when handling seek — start a paused segment if the timeline was paused.

### C3 · [MEDIUM · CONFIRMED] "Needs attention" silently drops the most severe failures
`app/server/servarr/index.js:122`
`FAILING_STATUSES` omits `trackedDownloadStatus === 'error'`, so error-state downloads (the ones the user most needs to remove) never surface in the Downloads "needs attention" list.
**Fix:** Add `'error'` (and `'warning'` as appropriate) to the allow-list.

### C4 · [MEDIUM · CONFIRMED] grab-or-remove deletes a just-added movie on a transient empty search
`app/server/servarr/index.js:543`
If the interactive release search returns empty due to a transient indexer/VPN outage, the flow deletes the just-requested movie — the exact "never delete on transient failure" guarantee this flow was built to honor.
**Fix:** Distinguish "search failed/empty transiently" from "confirmed no releases"; only remove on an explicit confirmed-empty (and ideally after a retry).

### C5 · [MEDIUM · PLAUSIBLE] Sonarr season-request risks monitoring the whole series
`app/server/servarr/arr.js:238`
The shell-add sends per-season `monitored:true` while relying on `addOptions.monitor:'none'`; a mismatch can cause Sonarr to monitor/pull the entire series instead of the requested season.
**Fix:** Set `monitored:false` on all non-target seasons explicitly and verify the resulting monitored set after add.

### C6 · [MEDIUM · PLAUSIBLE] `fmtRuntime` unit trap (ticks vs minutes)
`app/client/src/components/DownloadDetail.jsx:85`
Two `fmtRuntime` functions share a name but take different units (ticks vs minutes) — a silent 6-orders-of-magnitude display bug waiting to happen.
**Fix:** Rename to unit-explicit helpers (`fmtRuntimeFromTicks`, `fmtRuntimeFromMinutes`) in the shared formatter module (Q2).

### C7 · [LOW · PLAUSIBLE] `handleHostDisconnect` leaves stale schedule state
`app/server/index.js`
Freezes the schedule but leaves `effPlaying`/`intent.playing`/`playT0`/`pos` stale; a reconcile during the host-migration grace window can act on stale values.
**Fix:** Zero/normalize the derived fields when freezing on host disconnect.

### C8 · [LOW · CONFIRMED] `bufferAwareSeek` always calls `play()` after its awaits
`app/client/src/hooks/useSyncPlay.js`
After its awaits, `bufferAwareSeek` calls `play()` even if the timeline was paused/seeked during the wait — resuming playback against intent.
**Fix:** Re-check `scheduleRef.current.phase` after the awaits; only `play()` if still playing.

### C9 · [LOW · CONFIRMED] Buffer-aware seeks near the video end can never satisfy the buffer gate
`app/client/src/sync/bufferSeek.js`
A seek within `BUFFER_AHEAD_SEC` of the end can never accumulate the required look-ahead, so the wait never resolves.
**Fix:** Clamp the required buffer-ahead to `min(BUFFER_AHEAD_SEC, duration - target)`.

### C10 · [LOW · PLAUSIBLE] `getQueueCtx` caches the in-flight promise but never clears it on rejection
`app/server/servarr/index.js`
A single failure poisons the cache — every later call reuses the rejected promise until TTL.
**Fix:** Clear the cached promise in a `.catch`/`finally` on rejection.

### C11 · [LOW · CONFIRMED] `useDownloads`/`useFailingCount` abort guard reads a shared closure controller
`app/client/src/pages/Library.jsx`
A stale response can win the race and overwrite fresher state because the abort guard reads a shared closure `controller`.
**Fix:** Capture the controller per-effect-run (local `const`) and compare identity before committing state.

### C12 · [LOW · CONFIRMED] Two divergent `isPausedState` implementations
`app/client/src/pages/FindDownload.jsx`
Different files disagree on whether `error`/`missingFiles` counts as paused, driving inconsistent pause/resume UI.
**Fix:** Single shared `isPausedState` in the shared lib (Q2).

### C-INFO · [INFO · CONFIRMED] `bufferAwareSeek` doesn't reset `playbackRate` before resuming
`app/client/src/hooks/useSyncPlay.js`
A guest resumes at the prior soft-nudge `playbackRate` instead of 1.0.
**Fix:** Reset `video.playbackRate = 1` before resuming.

---

## 🧹 Code Quality

### Q1 · [HIGH · PLAUSIBLE] The entire desktop nav shell is copy-pasted across 3+ pages and drifting
`app/client/src/pages/{Library,Downloads,FindDownload}.jsx`, `DownloadDetail.jsx`
`C` palette, `SANS`/`MONO`/`glassStyle`, the `Ic` icon set, `Icon`, `viewIcon`, `Sidebar`, `NavRow`, `TopBar`, `GlassBtn`, `Notice`, `Spinner` are each redefined from scratch in every page and already diverging.
**Fix:** Extract one shared layout module and import everywhere. Highest-leverage refactor for this surface.

### Q2 · [MEDIUM · PLAUSIBLE] Download/state formatters reimplemented in 3+ files
`fmtSize`, `fmtSpeed`, `fmtEta`, `fmtRuntime`, `stateInfo` duplicated across the pages (root cause of C6/C12).
**Fix:** One `lib/format.js`.

### Q3 · [MEDIUM · PLAUSIBLE] `glass()` abstraction exists but the 3 pages bypass it with hand-rolled `glassStyle`
`app/client/src/glass.jsx:19`
**Fix:** Use `glass()` everywhere; delete the local `glassStyle` consts.

### Q4 · [MEDIUM · PLAUSIBLE] `FindDownload.jsx` is a 1695-line god-file
~30 components, 38 `useState`, confusingly-named export.
**Fix:** Split into subcomponents + hooks; rename the export to match its role.

### Q5 · [MEDIUM · PLAUSIBLE] `servarr/index.js` is a 1042-line route monolith
Near-duplicate radarr/sonarr handler pairs.
**Fix:** Factor a generic arr-router parameterized by service; split resolver/enrichment into modules.

### Q6 · [MEDIUM · PLAUSIBLE] Three separate pollers hit the same *arr queue endpoints
`useTorrents`, `useDownloads`, `useFailingDownloads` — different intervals/shapes.
**Fix:** One shared polling hook/source of truth.

### Q7 · [LOW · CONFIRMED] Downloads "N active" header and the sidebar badge use different "active" definitions
`app/client/src/pages/Downloads.jsx`
**Fix:** Single shared `activeCount` selector.

### Q8 · [LOW · PLAUSIBLE] `jget`/`jpost` fetch helpers duplicated across 6+ files with drifted signatures
**Fix:** One `lib/api.js`.

### Q9 · [LOW · PLAUSIBLE] Deployment-specific Tailscale origin hardcoded in server source
`app/server/index.js`
Hardcoded alongside the env-driven allowlist.
**Fix:** Move fully to env (`PUBLIC_ORIGIN`).

---

## 🕳️ Gaps (robustness / operational)

### G1 · [MEDIUM · CONFIRMED] All sessions + party state are in-memory
`app/server/index.js:54`
`MemoryStore` + module-level `Map`: every restart logs everyone out and destroys every live party; also single-process only and unbounded growth (no cookie expiry) = a slow memory-DoS vector.
**Fix (decision):** For persistence/multi-process, move sessions to Redis/SQLite and party state to a shared store. At minimum set a cookie `maxAge` to bound growth. _(Architectural — flagged for your call, not auto-changed.)_

### G2 · [HIGH · CONFIRMED] No TURN/coturn — WebRTC media fails for every off-tailnet guest
`livekit.yaml:8`, `docker-compose.yml:41`
LiveKit advertises a Tailscale CGNAT `node_ip` with `use_external_ip:false`, the TURN block + coturn service are commented out, and the client builds the room with no ICE config. Any guest not on your tailnet cannot publish/subscribe camera or mic.
**Fix (infra):** Deploy coturn/embedded TURN with a public IP + TLS, wire credentials into LiveKit, set a reachable external IP. _(Needs your public IP + deploy decision — flagged, not auto-changed.)_

### G3 · [MEDIUM · CONFIRMED] qBittorrent egresses on the host's real IP; indexer path depends on a free-tier VPN
`docker-compose.yml:268`
qBittorrent is not on the VPN (real-IP P2P exposure), and the whole indexer path depends on the free-tier Proton tunnel staying up.
**Status:** Previously discussed — you chose to leave downloads for now (Proton free disallows P2P). Flagged, deferred.

### G4 · [MEDIUM · CONFIRMED] No process-level error handling
`app/server/index.js:36`
One unhandled rejection/exception crashes the only process and wipes all in-memory state.
**Fix:** Add `process.on('unhandledRejection'|'uncaughtException')` handlers that log and keep the process alive (or exit cleanly under a supervisor).

### G5 · [LOW · CONFIRMED] `chat:message` has no server-side length cap or rate limit
`app/server/index.js`
A single client can broadcast/retain arbitrarily long messages at any rate.
**Fix:** Cap message length server-side and add a per-socket rate limit.

### G6 · [LOW · CONFIRMED] Deploy fragility
`docker-compose.yml`
`depends_on` ignores healthchecks (app can start before Jellyfin/Servarr are ready) and host-specific values are hardcoded.
**Fix:** `depends_on: { <svc>: { condition: service_healthy } }`; move host-specifics to env.

### G7 · [LOW · CONFIRMED] Absent automated test coverage
`app/package.json`
No client/server tests (the sync harness aside).
**Fix (decision):** Add a minimal test setup + smoke tests for auth, sync-schedule math, and the servarr grab-or-remove guard. _(Scoped separately — flagged, not auto-changed in this pass.)_

### G-INFO · [INFO] Unreferenced mobile scaffolding
`app/client/src/mobile/screens/_Placeholder.jsx` — provisional (mobile under active dev). Remove if unused.

---

_Generated by the code-analysis workflow (58 agents, adversarial verification). Findings whose verifier hit the session limit are tagged **PLAUSIBLE** and carry their scan-stage severity._
