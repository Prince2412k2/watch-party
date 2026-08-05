# Spec — Harden production deployment, dependencies, and CI release gates

- **Issue:** [#60](https://github.com/Prince2412k2/watch-party/issues/60) (`priority:high`, `target:dev`, `audit`)
- **Branch:** `audit/i60-deploy-hardening` (from `dev` @ `a02842f`)
- **Wave:** 2 of the `dev` audit remediation tracker ([#65](https://github.com/Prince2412k2/watch-party/issues/65))

## Problem

Production exposes every administrative service on `0.0.0.0`, runs a root, non-reproducible
app image built with `npm install`, resolves a `socket.io-parser` version carrying a
high-severity advisory, and deploys on every push to `main` with no test gate, no
post-deploy verification, and no defined recovery path. Mutable image and action tags mean
a deploy is not reproducible from its commit alone.

## User stories

### US-1 — Operator deploys a broken commit (P1)

**Independent test:** push a commit whose server tests fail; observe production unchanged.

- **Given** a commit whose server or client checks fail
  **When** it is pushed to `main`
  **Then** the deploy job does not run and the workflow reports failure.
- **Given** a commit that passes all checks but is unhealthy once running
  **When** the deploy completes
  **Then** the post-deploy health check fails the run nonzero and prints the exact
  rollback command including the previous commit SHA.

### US-2 — Attacker scans the VPS public interface (P1)

**Independent test:** from off-Tailscale, connect to each admin port; expect no service.

- **Given** the firewall script has been applied
  **When** an off-Tailscale host connects to 8096/8989/7878/6767/9696/8080/3001
  **Then** the connection is dropped.
- **Given** the VPS has rebooted or Docker has restarted
  **When** the same probe runs
  **Then** the connection is still dropped (rules persisted).

### US-3 — Reviewer audits what production is running (P2)

**Independent test:** check out the deployed SHA; confirm every external version is pinned.

- **Given** a deployed commit
  **When** a reviewer reads the compose file and workflow
  **Then** every image and action resolves to a reviewed, immutable-or-exact version, with
  no bare `latest` or floating major tag.

### US-4 — A secret is about to be committed (P2)

**Independent test:** stage a file containing a credential-shaped string; push; expect red.

- **Given** a commit containing a credential-shaped string
  **When** it is pushed or proposed via PR
  **Then** the secret-scanning gate fails and blocks the deploy.

## Functional requirements

### Admin exposure (decision: packet-filter enforcement, bindings unchanged)

- **FR-001:** A committed `deploy/firewall.sh` MUST drop traffic to admin ports
  8096, 8989, 7878, 6767, 9696, 8080, 3001 from any interface other than the Tailscale
  interface and loopback, using `DOCKER-USER` chain rules (Docker's NAT rules bypass ufw's
  `INPUT` chain, so ufw alone does not hold).
- **FR-001a:** The script MUST detect the Tailscale interface at runtime rather than
  hard-coding `tailscale0`, and MUST abort nonzero without writing any rule if it cannot
  find one. An `ADMIN_IFACE` env var MUST override detection. Rationale: a hard-coded name
  that does not match the host produces rules that match nothing and protect nothing, while
  appearing to have succeeded.
- **FR-002:** The script MUST allow 80/443 from anywhere, and the LiveKit/coturn media
  ports (7881/tcp, 7882/udp, 3478/udp, 5349/tcp) from anywhere, since remote party
  members need them.
- **FR-003:** The rules MUST survive a reboot and a Docker daemon restart via a persistence
  mechanism installed by the same script.
- **FR-004:** The script MUST be idempotent — re-running it MUST NOT duplicate rules.
- **FR-005:** A `deploy/firewall.sh --verify` mode MUST report, nonzero on failure, whether
  the expected rules are currently present.
- **FR-006:** `docker-compose.prod.yml` MUST document that admin exposure is enforced by
  `deploy/firewall.sh`, not by bind addresses, and that the script is mandatory.

### Dependencies

Baseline measured on `audit/i60-deploy-hardening` via `npm audit --package-lock-only`:

| Tree | Package | Vulnerable | Severity | Advisory |
| --- | --- | --- | --- | --- |
| server | `socket.io-parser` | `4.0.0 - 4.2.6` | **high** | GHSA-2m8v-j782-fhvr — zero-attachment memory exhaustion |
| server | `body-parser` | `<1.20.6` | low | GHSA-v422-hmwv-36x6 — DoS when an invalid limit silently disables size enforcement |
| client | `socket.io-parser` | `4.0.0 - 4.2.6` | **high** | GHSA-2m8v-j782-fhvr — as above |
| client | `postcss` | `<=8.5.22` | **high** | GHSA-r28c-9q8g-f849, GHSA-fxqj-rqcc-2cmp — path traversal via attacker-controlled `sourceMappingURL` |

- **FR-007:** `app/package-lock.json` and `app/client/package-lock.json` MUST resolve
  `socket.io-parser` to `>=4.2.7`.
- **FR-008:** `app/client/package-lock.json` MUST resolve `postcss` to `>8.5.22`. #60 names
  only `socket.io-parser`, but its "no high vulnerabilities" criterion covers this too.
- **FR-009:** `npm audit` MUST report zero `high` and zero `critical` advisories in both
  trees, for both the default and `--omit=dev` scopes.
- **FR-010:** The `body-parser` advisory MUST be resolved within Express 4's dependency
  range (`>=1.20.6`) or, if that proves impossible, enumerated with a stated reason for
  deferral. Express MUST NOT be bumped to 5.x — that is a breaking major outside this
  issue's scope.
- **FR-011:** Each dependency change MUST be a targeted update with the resulting version
  recorded. Blanket `npm audit fix` MUST NOT be used.

### App image

- **FR-012:** `app/Dockerfile` MUST use `npm ci` (not `npm install`) for both the server
  and client dependency installs.
- **FR-013:** The image MUST be multi-stage, and the runtime stage MUST contain production
  dependencies and built client assets only — no client `devDependencies`, no build
  toolchain.
- **FR-014:** The runtime stage MUST run as a non-root user, and that user MUST own the
  writable runtime paths (`/data/sessions`, `/data/subtitles`, `/app/data`).
- **FR-015:** The base image MUST be pinned to an exact patch version.
- **FR-016:** The image MUST declare a `HEALTHCHECK` probing the app's own HTTP health
  endpoint.

### Health checks and deploy scripts

- **FR-017:** `watchparty`, `jellyfin`, `livekit`, and `caddy` MUST each declare a compose
  `healthcheck`.
- **FR-018:** `watchparty`'s `depends_on` for `jellyfin` and `livekit` MUST use
  `condition: service_healthy` rather than `service_started`.
- **FR-019:** A committed `deploy/health-check.sh` MUST probe every critical service and
  exit nonzero if any is not healthy within a bounded timeout.
- **FR-020:** `deploy/up-prod.sh` MUST exit nonzero when any critical service is unhealthy
  after its wait loop. (It currently falls through to a success message regardless —
  `up-prod.sh:69-85`.)
- **FR-021:** `deploy/health-check.sh` MUST print, on failure, the exact rollback command
  including the previous commit SHA.

### CI gates

- **FR-022:** CI MUST run these gates on push to `main` and `dev`, and on pull requests:
  server tests, client tests, client typecheck, client production build, Flutter
  analyze + test, and secret scanning.
- **FR-023:** The `deploy` job MUST declare `needs:` on every gate in FR-022 and MUST NOT
  run if any fails. (It currently has no `needs:` at all — `main.yml:67-89`.)
- **FR-024:** `deploy` MUST remain restricted to `main`; pushes to `dev` MUST run gates
  only.
- **FR-025:** After a deploy, CI MUST run `deploy/health-check.sh` on the VPS and fail the
  run nonzero if it fails.
- **FR-026:** A committed rollback runbook MUST document the recovery procedure, and that
  procedure MUST be executed once and its output recorded as evidence.
- **FR-027:** `app/package.json` MUST gain a `test` script so CI has a stable entrypoint.

### Pinning

- **FR-028:** Every `uses:` in `.github/workflows/main.yml` MUST be pinned to a full commit
  SHA with the human-readable version in a trailing comment.
- **FR-029:** Every image in `docker-compose.prod.yml` MUST be pinned to an exact version
  tag; no `latest`.
- **FR-030:** Where a registry digest cannot be resolved from the build environment, the
  exact-tag pin MUST be accompanied by a documented procedure for upgrading the pin to a
  digest from a network-enabled host.

### Secrets

Two separate LiveKit credential events are in scope. They have different severities and
different remedies — do not conflate them.

**Event A — historical, in git, not live.** `devkey` / `devsecret0000…`, LiveKit's published
dev default, tracked from `1822273` (add) to `a8a09bf` (delete), alongside an incidental
`node_ip 100.64.0.10` Tailscale address. Not a live secret; production never used it.
Remedy: documentation only, per decision.

**Event B — current, live, exposed during this spec's own authoring.** While verifying
LiveKit's UDP port configuration on 2026-08-05, a `grep` intended to redact secrets failed
(it filtered on the words `secret`/`key`, but the line is a bare `<keyid>: <secret>` pair)
and printed the live production LiveKit API key and secret into the session transcript.
The value is present in four gitignored files: `secrets/livekit.yaml`, `secrets/.env`,
`secrets/livekit.dev.yaml`, and `.env`. Nothing tracked in git was affected. This
supersedes the original "no rotation required" decision, whose premise was that the live
key had never been exposed.

- **FR-031:** `docs/security/livekit-credential-exposure.md` MUST record both events above,
  with Event A's commit range and Event B's date, cause, blast radius (four gitignored
  files, no tracked file), and remedy.

  For Event B the recorded remedy is **accepted, not rotated** — the repository owner was
  presented with the exposure and the rotation options on 2026-08-05 and elected to document
  it without rotating. The credential therefore remains valid. The doc MUST state this
  plainly, including that acceptance was an explicit owner decision, so a later reader does
  not mistake it for an oversight.
- **FR-031a:** Every diagnostic command in this work that reads a secret-bearing file MUST
  redact by **line position or key allowlist**, never by keyword match on the value's name.
  This is the direct lesson from Event B: the failed filter matched on the words
  `secret`/`key`, which do not appear in a bare `<keyid>: <value>` line.
- **FR-032:** The stale `.gitignore:4-7` comment instructing `git rm --cached livekit.yaml`
  MUST be removed, since `a8a09bf` already deleted the file.
- **FR-033:** A secret-scanning gate MUST run in CI over the pushed range and PR diffs.
- **FR-034:** The vestigial tracked `coturn.conf` (placeholders only, yet shadowed by the
  `*.conf` ignore rule) MUST be resolved — untracked or renamed to `.example` — so tracked
  state matches the ignore policy.

### Jellyfin media

- **FR-035:** Jellyfin's `./media` and `${MEDIA_ROOT}/media` mounts MUST be `:ro`.
- **FR-036:** Servarr services MUST retain write access to `/data` (import, hardlink, and
  rename all require it).
- **FR-037:** The read-only decision MUST be documented alongside the condition that would
  reverse it (enabling Jellyfin metadata/artwork saving into media folders).

## Success criteria

- **SC-001:** From an off-Tailscale host, all seven admin ports refuse connections, before
  and after a reboot.
- **SC-002:** `deploy/firewall.sh --verify` exits 0 on a correctly configured host and
  nonzero with a named missing rule otherwise.
- **SC-003:** `npm ls socket.io-parser` reports `>=4.2.7` in both trees, and
  `npm ls postcss` reports `>8.5.22` in the client tree.
- **SC-004:** `npm audit` reports 0 high and 0 critical in both trees, in both the default
  and `--omit=dev` scopes. Any surviving low/moderate advisory is listed in the spec with a
  deferral reason.
- **SC-005:** Express remains on 4.x — `npm ls express` shows no 5.x resolution.
- **SC-006:** The built app image runs as a non-root UID (`docker inspect` confirms) and
  serves traffic.
- **SC-007:** The runtime image contains no client `devDependencies`.
- **SC-008:** Two builds of the same commit install byte-identical dependency trees.
- **SC-009:** With a critical service forced unhealthy, `deploy/up-prod.sh` and
  `deploy/health-check.sh` both exit nonzero.
- **SC-010:** A commit with a failing server test does not reach the deploy job.
- **SC-011:** A commit containing a credential-shaped string fails the secret gate.
- **SC-011a:** `docs/security/livekit-credential-exposure.md` records both credential events,
  and states for Event B that the live key was exposed on 2026-08-05, that it remains valid,
  and that non-rotation was an explicit owner decision rather than an oversight.
- **SC-011b:** No command introduced by this work prints a secret value. Verified by
  re-running each diagnostic in the plan and grepping its output against the known key id.
- **SC-012:** `grep -E ':latest|@v[0-9]+$'` finds no matches in the prod compose file or
  workflow.
- **SC-013:** The documented rollback procedure has been executed once with recorded output.
- **SC-014:** Jellyfin serves playback with read-only media mounts.
- **SC-015:** Server, client, Flutter, and browser suites stay green: 139/139 server,
  46/46 client, 166 pass + 4 skip Flutter, 12/12 browser Python.

## Out of scope

- Git history rewrite — decided against; the exposed value is LiveKit's public dev default
  and the blast radius covers six audit worktrees plus the Wave 1 integration branch.
- Rotating the current production LiveKit key — **out of scope by explicit owner decision**,
  reaffirmed on 2026-08-05 after the Event B transcript exposure was raised (FR-031). The
  first declination rested on the key never having been exposed; that premise no longer
  holds, and the owner accepted the exposure anyway. Recorded, not silently dropped.
- Automated rollback — decided against in favour of a gated, documented manual procedure.
- Migrating the app image to GHCR — the build-on-VPS model is retained.
- Narrowing admin bind addresses — enforcement is at the packet-filter layer by decision.
- A staging environment; `dev` runs gates only.
- Restarting or recreating any live `watchparty-*` container.
- `docker-compose.yml` and `docker-compose.servarr.yml` (dev/optional stacks) except where
  a change is needed for consistency.

## Assumptions

- **A-1:** Admin exposure is acceptable at the packet-filter layer rather than the bind
  layer. Recorded risk: with `0.0.0.0` bindings, a flushed ruleset re-exposes every admin
  UI with no second layer — which is why FR-003 and FR-005 (persistence and verification)
  are requirements, not niceties.
- **A-2:** Jellyfin stores metadata and artwork under `/config`, so read-only media mounts
  do not break it. FR-037 records the reversing condition.
- **A-3:** The VPS runs Tailscale. The interface name is **not** assumed — FR-001a requires
  runtime detection with an `ADMIN_IFACE` override and a hard abort if none is found.
- **A-4:** `coturn` uses `network_mode: host`, so its ports cannot be bound selectively and
  are firewall-managed only.
- **A-4a:** LiveKit media uses single-port UDP mux on 7882, confirmed from
  `secrets/livekit.yaml` (`rtc.udp_port: 7882`, `use_external_ip: true`). `HANDOFF.md:428`
  still claims a `50000-50020/udp` range must be open — that is stale, from the pre-mux
  design in `HANDOFF.md:38-40`. FR-002 follows the live config, not the doc. Flagged
  separately: an operator writing firewall rules from HANDOFF.md would open 21 wrong ports
  and still not open the right one. HANDOFF.md is a historical brief, not current-state
  reference — correcting it is outside #60.
- **A-4b:** LiveKit's HTTP/WS port 7880 is deliberately **not** published in prod; the app
  reaches it as `ws://livekit:7880` over `watchparty-net`. The firewall script must not open
  it.
- **A-5:** ~~Container image digests cannot be resolved from this environment~~ —
  **superseded during implementation.** Docker Hub does 403 through the sandbox proxy, but
  the digests were obtained a better way: read off the nine containers actually running in
  production, then checked with `Id == RepoDigests[0]` (this host uses the containerd image
  store) to confirm they are genuine registry manifest digests that will resolve on pull.
  FR-029 therefore landed as **full digest pins**, not exact tags, and pins to an
  already-known-good set. The app's base image stays an exact version tag by choice — a
  local manifest digest is platform-specific and would break an arm64 build.
  `docs/deploy/pinning.md` records both procedures. Action SHAs were resolvable via the
  GitHub API throughout and are pinned to 40-character commit SHAs.
- **A-6:** `git` over SSH is unavailable here (no DNS for `github.com`, and the configured
  key `~/.ssh/Personal` is absent), so no branch will be pushed during this work. Issue
  operations go through the GitHub REST API, which does work.
- **A-7:** Firewall rules, reboot persistence, and off-host port probes cannot be verified
  from this machine — it is not the VPS. SC-001 is verified by static review plus a scripted
  self-check, and flagged for operator confirmation on the VPS.

## Blocking dependency: #60 must merge after #63a

**#60 must not reach `main` before the green-baseline work (`#63a`, commit `db6dd34`) does.**

FR-022 makes `flutter analyze` and `flutter test` deploy-blocking gates, and `deploy` now
declares `needs:` on them. But `db6dd34` ("test: restore green client baseline") is the
commit that made the Flutter tree analyzer-clean, and it exists only on
`audit/i63a-green-baseline` and the Wave 1 integration branch — **not on `dev`**, which this
branch is cut from.

Confirmed by running it, not inferred. On this branch `flutter analyze` reports
**25 issues** — 1 warning and 24 infos:

```
warning • Unused import: '../../state/providers.dart'
          lib/app/screens/servarr_detail_screen.dart:6:8 • unused_import
```

plus infos spanning `use_null_aware_elements`, `prefer_initializing_formals`,
`unnecessary_import`, `dangling_library_doc_comments`,
`prefer_function_declarations_over_variables`, and `unintended_html_in_doc_comment` across
`lib/app/screens/`, `lib/cache/`, `lib/data/api_client.dart`, `lib/player/player_view.dart`,
`lib/models/profile.dart`, and two test files.

`flutter_app/analysis_options.yaml` sets no `fatal-infos`/`fatal-warnings` overrides (its
only `errors:` entry is `invalid_annotation_target: ignore`), and `flutter analyze` defaults
`--fatal-warnings` **on**. So the single `unused_import` **warning** is on its own enough to
exit nonzero — this does not depend on how infos are treated. The new gate goes red, which
— correctly, by design — blocks every deploy.

The same command on `audit/i63a-green-baseline` passes, confirming `db6dd34` is precisely
the fix and that the ordering below is the whole resolution.

This was **not** resolved by weakening the gate. A gate that passes on known-broken code is
not a gate, and #60's acceptance criteria require Flutter checks to gate deploys. The
resolution is ordering:

1. Land `#63a` (green baseline) on `dev`.
2. Then land `#60`.

If #60 lands first, deploys stay blocked until #63a follows. Either order is safe for
production — the gate fails closed, it does not deploy something broken — but the first
order avoids a window of red CI.

`flutter analyze` was run by the repository owner (Flutter is not installed in the authoring
environment) on both branches: 25 issues on this one, clean on `#63a`. `flutter test` has
still not been run on either branch, so FR-022's test half of the Flutter gate remains
unverified — analyze alone is already enough to block, so this does not change the ordering
conclusion.

## Deviation from issue acceptance criteria

#60 requires "CI gates deploys on … post-deploy health, **and rollback behavior**." Per the
decision recorded above, rollback is **documented and verified but operator-triggered**, not
automated. FR-021, FR-026, and SC-013 cover the documented-and-tested half. This deviation
is deliberate and will be stated on the issue when the work is submitted.
