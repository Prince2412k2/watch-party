# Neko container-recreate: SSH forced-command setup

Task C3b (`docs/plans/2026-07-20-neko-collab-browser.md`). Confirms and documents
the deployment side of the container-recreate reset validated in
`docs/specs/2026-07-20-neko-spike-decision.md` (item 6: `docker compose up -d
--force-recreate` gives a clean container; `docker restart` does not).

## Why SSH, not the docker socket

The app container triggers a reset by running exactly one fixed command on the
**Neko host** over SSH, via a forced-command key. It does **not** get access to
`/var/run/docker.sock` — mounting the docker socket into the app container
would let a compromise of the app (or of anything that can reach its
process) drive the docker daemon arbitrarily (any container, any image, host
mounts). The SSH forced-command approach instead lets the key do exactly one
thing: recreate the `neko` service. See "Architecture decisions" in the plan.

## 1. Generate the keypair

On your workstation (not on the Neko host, not baked into any image):

```sh
ssh-keygen -t ed25519 -f neko-recreate-key -C "watchparty-app neko-recreate" -N ""
```

This produces `neko-recreate-key` (private) and `neko-recreate-key.pub`
(public). The private key is what gets mounted read-only into the
`watchparty` app container — see `docker-compose.prod.yml`'s
`./secrets/neko-recreate-key:/run/secrets/neko-recreate-key:ro` volume. It
must never be committed to the repo or baked into `app/Dockerfile`.

## 2. Install the forced-command script on the Neko host

On the host that runs the `neko` compose service (may be the same VPS as the
app, or a separate box on the tailnet), create `/usr/local/bin/neko-recreate`:

```sh
#!/bin/sh
# Forced-command target for the watchparty-app SSH key. Does exactly one
# thing, ignoring any command the client actually asked to run (see the
# authorized_keys `command=` binding below).
set -eu
cd /path/to/compose   # directory containing docker-compose.prod.yml (or docker-compose.yml)
exec docker compose up -d --force-recreate neko
```

```sh
chmod +x /usr/local/bin/neko-recreate
```

Adjust `/path/to/compose` to wherever this repo (or just the compose file +
`.env`) is checked out on that host.

## 3. Bind the public key to that command in `authorized_keys`

Add the generated public key to the `neko-recreate` user's
`~/.ssh/authorized_keys` on the Neko host, with `command=` and `restrict`
(OpenSSH ≥ 7.2 — `restrict` also disables port/agent/X11 forwarding, pty
allocation, etc., so the connection genuinely can't do anything but run the
bound command):

```
restrict,command="/usr/local/bin/neko-recreate" ssh-ed25519 AAAA... watchparty-app neko-recreate
```

Whatever command the app's `ssh` invocation names (see
`app/server/neko/container.js`'s `defaultRunner` — it doesn't pass a command
at all, relying entirely on the server side default-command binding) is
irrelevant: the server always runs `/usr/local/bin/neko-recreate` instead.
This is what makes "arbitrary command → refused by forced-command" true even
if the app container were compromised — the blast radius of that key is
exactly `docker compose up -d --force-recreate neko`, nothing else.

Create a dedicated `neko-recreate` system user for this (no shell, no other
purpose) rather than reusing an admin account.

## 4. Wire the app container to it

- `NEKO_SSH_HOST` — the Neko host's tailnet name or IP (e.g.
  `neko-host.tailnetxyz.ts.net`). Set in `secrets/.env`.
- `NEKO_SSH_KEY_PATH` — `/run/secrets/neko-recreate-key` inside the container;
  mounted from `./secrets/neko-recreate-key` on the compose host (read-only).
- The app's `known_hosts` for `neko-recreate@<NEKO_SSH_HOST>` must be
  pre-populated (baked into the image or mounted) since `defaultRunner` uses
  `StrictHostKeyChecking=yes` — an unknown host key must refuse, not prompt.
  Pin it explicitly, e.g. by adding a `~/.ssh/known_hosts` file to the volume
  mount alongside the key, generated once via `ssh-keyscan <host> >>
  known_hosts` and committed to `secrets/` (gitignored, like the key).
- `app/Dockerfile` installs `openssh-client` (`apk add --no-cache
  openssh-client`) so the `ssh` binary is present; no key or host-key
  material is added at image-build time — both come from the runtime mount.

## 5. Pinned image tag

The `neko` service in both compose files pins
`ghcr.io/m1k1o/neko/firefox:3.1.4` (≥ 3.1.2, the CVE floor from
GHSA-2gw9-c2r2-f5qf — see the spike decision doc). Never move this to
`:latest`; bump the pinned tag deliberately and re-run the spike checks in
`docs/specs/2026-07-20-neko-spike-decision.md` before rolling forward.

## 6. Network boundary (finding #4)

Neko's TCP port 8080 (HTTP/WS/API, including `/metrics` and `/api/sessions`)
must be reachable **only** from the `watchparty` app/backend — never from
client devices, and never published on the host's public interface. In both
compose files here, 8080 is intentionally left unpublished; the app reaches
it over the internal `watchparty-net` docker network at `http://neko:8080`
and re-exposes only the authenticated `/neko` proxy path. If Neko runs on a
**separate host** from the app (its own VPS/box on the tailnet), enforce this
with:

- A host firewall rule (ufw/iptables) that only allows 8080/tcp from the app
  host's tailnet IP.
- A Tailscale ACL restricting the `neko` node's 8080/tcp to the `watchparty`
  node.

Only the WebRTC EPR/UDP range (`NEKO_WEBRTC_EPR`, published in both compose
files) — or a TURN relay — needs to be reachable by client devices directly;
that's media transport, not the admin/session API, and doesn't expose the
`NEKO_SESSION` cookie's authority. This is what prevents a user who extracts
their own `NEKO_SESSION` cookie from bypassing the app's allow-list (C11) by
hitting the Neko host directly.

## Alternative for a local single-host deploy

If the app and the `neko` service run on the **same** host and the deploy
already trusts whoever can run `docker compose` there (e.g. a personal/local
deploy, not the multi-tenant prod VPS), an alternative runner could shell out
to `docker compose up -d --force-recreate neko` directly instead of over SSH,
skipping the forced-command host entirely. This is **not implemented** here —
`app/server/neko/container.js`'s `recreateContainer()` always uses the SSH
runner — because it would require mounting the docker socket (or running
docker-in-docker) into the app container, reintroducing the blast-radius
problem this design avoids (see "Why SSH, not the docker socket" above). Only
consider it for a genuinely single-trust-domain local setup, and only via a
custom `runner` passed to `recreateContainer({ runner })`, not the default.
