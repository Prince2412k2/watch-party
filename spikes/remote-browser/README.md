# Spike — remote browser published into LiveKit

Throwaway harness. Nothing here is meant to ship.

## The question

Can a containerised Chromium publish its own screen into the LiveKit room we
already run, non-interactively, at watchable video quality and a cost we'd accept
— so that we never write a media server, a signalling layer, or a client?

Everything else about the feature is straightforward if the answer is yes, and
nothing else matters if it's no.

## Why this shape

The previous attempt (`feature/neko-collab-browser`, 29 commits, ~6,700 lines)
worked from the opposite end. Neko brings its own transport, so the branch had to
grow a same-origin proxy, a cookie relay, a path-prefix allow-list, and finally a
hand-port of Neko's WebRTC client — `nekoConnection.ts` plus 1,545 lines of
vendored Guacamole keysym tables. Every commit after the port is a bug in that
layer: wire envelope, cursor offset from `object-fit: contain` letterboxing,
scroll clamped at ±32767.

Here Chromium does capture, encode and WebRTC, and LiveKit does transport. What
that buys:

- **No client.** A screen-share track from a bot participant is just another
  LiveKit track; `CameraTile` already renders those.
- **Flutter for free.** It already speaks LiveKit. The branch's planned native
  Neko client — REST auth, WS signalling, SDP/ICE, data-channel input, across
  four platforms — doesn't exist as work.
- **No proxy layer.** No `/neko` prefix, no hashed-asset allow-list, no cookie
  relay, no `SameSite=None`-needs-HTTPS. All of it was a workaround for Neko
  owning its own transport.
- **ICE/TURN already solved**, by the deployment we already debug.

What survives from the branch unchanged: `app/server/neko/{lease,idle,teardown,detach,routes}.js`
— 646 lines of lifecycle and control-lease logic with 884 lines of tests. That
was always the valuable part.

## Prerequisites

LiveKit must actually be running. At the time of writing `watchparty-livekit` is
in a restart loop because `docker-compose.yml:44` bind-mounts `./livekit.yaml`,
which is an empty root-owned directory Docker created because the file doesn't
exist. Prod mounts `./secrets/livekit.yaml` correctly. Confirm with
`docker logs watchparty-livekit | tail -30` and fix that first, or the container
here will just fail to connect.

## Run

```sh
cd spikes/remote-browser
./probe.sh build
./probe.sh up                  # mints tokens, starts the container, prints the URL
```

Then open **http://localhost:8899** — the viewer page is served *from inside the
container* and port-published, so it works from a browser on this host. Do not serve
it from anywhere else: a helper shell or a sandbox puts it on the wrong localhost,
which looks identical until nothing loads.

Drive the remote browser:

```sh
./probe.sh goto en.wikipedia.org   # navigate (ctrl+L, type, Enter via xdotool)
./probe.sh newtab                  # ctrl+T
./probe.sh key F5                  # any xdotool combo: ctrl+w, Tab, …
./probe.sh shot page.png           # grab the framebuffer, no WebRTC involved
./probe.sh stats 60                # CPU/memory
./probe.sh down
```

Defaults to Wikipedia at 1280x720@30, VP8, 2.5 Mbps cap, with Chromium's tab strip
and address bar **in** the stream. Override per run:

```sh
TARGET_URL=https://youtube.com/watch?v=… CODEC=h264 SCREEN_H=540 ./probe.sh up
BROWSER_CHROME=kiosk ./probe.sh up          # page only, no tabs/toolbar
TARGET_URL=http://127.0.0.1:9000/player.html ./probe.sh up   # video measurement stage
```

## Diagnostic pages

All served from the container at `http://127.0.0.1:9000/`. Each one isolates a
single layer, which is how the four bugs above were actually found — the failures
all present as something else.

| page | isolates |
|---|---|
| `captest.html` | does `getDisplayMedia` start at all (no LiveKit, no token) |
| `fpstest.html` | the rate capture *really* delivers, via `requestVideoFrameCallback`. `?wh=1` adds the publisher's resolution constraints |
| `codectest.html` | decode + **send** codec support (settles the H.264/iOS question) |
| `audiotest.html` | `getUserMedia` audio and `enumerateDevices` input list |
| `motion.html` | codec-independent 60fps canvas — separates "encode can't keep up" from "the page wasn't animating" |
| `player.html` | looping real video, with a decoded-fps HUD so a screenshot proves it's moving |

Run one against the live container without a rebuild:

```sh
docker exec -e DISPLAY=:99 spike-remote-browser bash -c '
  prof=$(mktemp -d); timeout 20 chromium --no-sandbox --no-first-run --test-type \
    --user-data-dir="$prof" --use-fake-ui-for-media-stream \
    --auto-select-desktop-capture-source="Entire screen" \
    --enable-logging=stderr --v=0 http://127.0.0.1:9000/fpstest.html?fps=30 2>&1 |
  grep -a FPS'
```

When a capture failure needs digging, the only log that says anything useful is
`--vmodule="*desktop_capture*=3,*video_capture*=3,*media_stream_manager*=3"`.

## What to record

Fill in the table in `docs/specs/2026-08-04-remote-browser-spike.md`.

| # | Probe | How | Bar |
|---|---|---|---|
| 1 | Publishes at all | `./probe.sh logs` shows `published video track` | pass/fail — everything depends on this |
| 2 | Non-interactive | no picker dialog blocks startup | must pass; the auto-select flags are the load-bearing hack |
| 3 | Video quality | viewer panel: resolution, fps, freezes | ≥25 fps sustained at 720p, freezes ≈ 0 |
| 4 | Bitrate | viewer panel | ≤2.5 Mbps for watchable 720p30 |
| 5 | CPU cost | `./probe.sh stats 60` | avg under ~2 cores is good, over ~4 is a problem |
| 6 | Memory | same | note it; Chromium + Xvfb realistically wants 1.5–2 GB |
| 7 | Audio | viewer hears it, in sync | pass/fail, plus drift over ~5 min |
| 8 | Client decode | viewer panel `decoder` | hardware is the win for iOS battery |
| 9 | Input works | `./probe.sh input` | pointer moves, text lands |
| 10 | Input latency | time `input` returning → change visible | under ~150 ms feels direct |
| 11 | Cursor visible | look at the stream | see the note below — a fail here is not a blocker |
| 12 | DRM | try a real streaming site | expected fail; confirm which sites |

## Things I expect to bite

- **The auto-select capture flags.** `--auto-select-desktop-capture-source` and
  `--auto-select-tab-capture-source-by-title` drift between Chromium versions. If
  probe 2 fails, that's the first thing to check, and `DESKTOP_SOURCE` is an env
  var precisely so you can try other names ("Screen 1", "Entire Screen") without
  a rebuild.
- ~~H.264 encode may be missing.~~ **Measured false.** Debian's Chromium 151
  reports `send codecs=VP8,rtx,H264,AV1,VP9` and decodes h264/vp8/vp9/av1, so
  `CODEC=h264` is available and iOS viewers can get hardware decode. No need for
  Google's Chrome .deb.
- **`screenShareEncoding`, not `videoEncoding`.** livekit-client does
  `if (isScreenShare) videoEncoding = options.screenShareEncoding`, so a
  ScreenShare-source track ignores `videoEncoding` and takes the default
  `ScreenSharePresets.h1080fps15` — pinning the stream to exactly 15fps whatever
  you asked for. This cost real time to find; the symptom looks like a capture or
  CPU limit and is neither.
- **Cursor capture.** X11 screen capture usually omits the pointer, so probe 11
  will likely fail. **Don't spend time on it** — the controlling client knows
  where it put the cursor, so rendering it client-side is both easier and lower
  latency than round-tripping it through the encoder. Neko did exactly this.
- **Simulcast is off** (`publisher.js`), because encoding three layers of
  full-motion video is the biggest CPU cost available to avoid. The tradeoff is
  that a viewer on a weak connection can't drop to a lower layer. Revisit only if
  probe 5 comes back cheap.
- **`CAPTURE_MODE=tab`** is the lighter path — no framebuffer round-trip, and tab
  audio comes along free, skipping PulseAudio entirely. It needs `TARGET_TITLE` to
  match the tab, which you can't know ahead of an arbitrary URL. Worth measuring
  against `screen` once, since it bounds how much the framebuffer copy costs.

## What this deliberately does not answer

Multi-tenancy. One container serves one party, exactly as before — the branch ran
a single global instance with `NEKO_RECREATE_MODE=noop`, meaning no isolation
between parties at all. Rebuilding the media path doesn't touch that. A
single-global-instance v1 is still the sane first cut, and
`app/server/neko/lease.js` already encodes it.
