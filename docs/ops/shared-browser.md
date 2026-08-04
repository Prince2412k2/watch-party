# Shared browser — operating notes

A containerised Chromium that publishes its own screen into a party's existing
LiveKit room, so a party can watch something the Jellyfin library does not hold.

Spec: `docs/specs/2026-08-04-remote-browser.md`
Feasibility and measurements: `docs/specs/2026-08-04-remote-browser-spike.md`

## Turning it on

**It is off by default.** A deployment that sets nothing behaves exactly as it did
before the feature existed: no browser affordance in any client, no socket events
that drive it, no container.

Add to `.env`:

```sh
# Two switches, because they answer different questions:
#   BROWSER_ENABLED=1          does the app offer the feature?
#   COMPOSE_PROFILES=browser   does the container exist at all?
# Either alone is safe: an unreachable container reads as "unavailable", and a
# container nobody talks to sits idle at near-zero CPU.
BROWSER_ENABLED=1
COMPOSE_PROFILES=browser

# Gates the container's control API, which accepts input injection. REQUIRED —
# both the app and the container refuse to use the feature without it.
#   openssl rand -hex 32
BROWSER_AGENT_TOKEN=

# The page a browser opens on. Not an allow-list — the driver may go anywhere.
BROWSER_HOME_URL=https://www.google.com

# Ceiling, not a target: this stream shares an uplink with everyone's cameras.
BROWSER_MAX_BITRATE_KBPS=2500
```

Then:

```sh
docker compose up -d --build browser watchparty
```

Turning it off again is `BROWSER_ENABLED=` (and dropping the profile). No
migration: a party that was on the browser activity falls back to the lobby, and
any stale lease is cleared at startup.

## Why two switches

They fail in different directions, and both failures are harmless:

| `BROWSER_ENABLED` | container | behaviour |
|---|---|---|
| unset | absent | the feature does not exist; hand-crafted socket events are refused |
| unset | running | the container sits idle; the app never contacts it |
| `1` | absent | clients see the feature, and starting it reports "not running on this server" |
| `1` | running | working |

The third row is the one that matters: a missing container runtime is treated as
*the feature is unavailable*, never as a server fault.

## How it works

```
host presses "Shared browser"
  → app/server takes the single global lease            (browser/lease.js)
  → mints a publish-only LiveKit token for the party's room
  → POST /session/start to the container's agent        (browser/agent.py)
      → Chromium #1 (publisher, small, behind) captures the screen and publishes
      → Chromium #2 (target, maximized) shows the URL
  → publisher reports "published" → party state flips to active
  → every participant is already in that room, so the stream just appears
```

Input goes the other way: the driver's client maps pointer/keyboard events into
remote-screen coordinates, sends them over the existing Socket.IO connection, and
the server — which is the only place a client cannot bypass — checks that the
sender is the current driver before forwarding them to the agent's `/input`,
which turns them into `xdotool` calls.

Nothing here speaks RTP. Chromium does capture, encode and WebRTC; LiveKit does
transport; the Flutter app inherits viewing because it already speaks LiveKit.

## The container's control API

Listens on `8080`, **never published to the host** — it accepts input injection,
so it must be reachable only from `app/server` on `watchparty-net`. Every request
needs `Authorization: Bearer $BROWSER_AGENT_TOKEN`, and the agent refuses
everything if no token is configured (fail closed).

| method | path | purpose |
|---|---|---|
| `GET` | `/health` | container healthcheck; unauthenticated and stateless on purpose |
| `GET` | `/status` | running / publishing / last error / last stats |
| `POST` | `/session/start` | `{url, token, lkUrl, kbps, fps}` |
| `POST` | `/session/stop` | idempotent; wipes the profile |
| `POST` | `/session/navigate` | `{url}` — types it into the remote address bar |
| `POST` | `/input` | `{events: [...]}` batch |

## Resource ceilings

Set from measurement, not guesswork (spike decision record):

| | measured |
|---|---|
| 720p30 YouTube, 4 vCPU | 68.6% of one core avg, 96.9% peak |
| memory, same run | 1.15 GiB |
| bitrate | 2.4–2.5 Mbps |
| cold container start → frames | 6.3s |
| browser restart, container up | 3.5s |

Hence `cpus: "4.0"` and `mem_limit: 3g` in compose. **Prod has no swap**, so an
over-tight memory limit is an OOM kill rather than a slowdown; 3 GiB is ~2.6× the
measured peak. Note that `/dev/shm` pages count against `mem_limit` under
cgroup v2, which is why `shm_size` is 1 GiB rather than the spike's 2 GiB.

720p is the shipping resolution. 1080p was never validly measured at this
allocation (estimated 4–5.4 vCPU) and is out of scope.

## Idle cost

While no party is using it: Xvfb, PulseAudio and a Python agent. No browser
process, no encoding, no transmission — the container is resident precisely so
that starting one is 3.5s rather than 6.3s, not so that it keeps publishing.

The spike's idle figure of 24% CPU was measured with the publisher still
streaming an empty desktop. That is not what ships: both Chromium processes are
killed on stop.

## Privacy between parties

Chromium profiles live on a **tmpfs** at `/profiles` and are destroyed on every
stop — cookies, history, downloads, extensions, signed-in sessions. tmpfs so that
a wipe that fails, or a container killed outright, still cannot leak a signed-in
session into the next party.

The publisher's LiveKit token is deliberately `canSubscribe: false`. The browser
is a screen being shown to the room, not a member of it; a browser that could
subscribe would be a way to send a party's own cameras to whatever page it was
pointed at.

## Exactly one party at a time

One browser for the whole deployment — 4 of 8 shared vCPUs does not permit a
second. A second party's request is refused with *"The shared browser is in use
right now"* and nothing more: naming the occupying party or its host would tell a
stranger who is watching together.

The lease is a persisted row with a small state machine
(`starting → active → cleaning`). A lease found mid-transition at startup is the
fingerprint of a crash and is always torn down, so a crash cannot leave the
browser permanently "busy".

## When something goes wrong

```sh
docker logs watchparty-browser              # agent + publisher diagnostics
docker exec watchparty-browser curl -s -H "Authorization: Bearer $BROWSER_AGENT_TOKEN" \
  localhost:8080/status | python3 -m json.tool
```

The health monitor in `app/server/browser/service.js` polls `/status` every 4s
while a party holds the browser. A crash, an OOM kill or the driver closing the
last tab surfaces as an error on the browser surface only, and the party returns
to the lobby with playback, cameras and chat untouched.

Known operational quirks:

- **A developer behind a TLS-inspecting proxy** (e.g. Sophos) will see "Privacy
  error" inside the container while the host browses fine. Drop the appliance's
  CA into `browser/extra-ca/*.crt`; the entrypoint installs it into both the
  system store and Chromium's NSS db. Not a concern on the VPS.
- **DRM does not work and is not meant to.** Netflix, Disney+ and Prime are out of
  scope: Widevine is L3-only in a container, streaming services reject datacenter
  IPs, and Chromium blanks protected content under screen capture anyway. YouTube
  is the acceptance bar.
- **Control is desktop-only, in both clients.** The web client offers it on
  desktop; the Flutter app offers it on macOS, Windows and Linux. Phones and
  tablets are view-only by design — a touch surface has no hover, no right click
  and no keyboard — and the UI says so rather than showing a dead control. A party
  where every participant is on a phone has nobody who can navigate.
