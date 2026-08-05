# Spike Decision Record — Remote Browser over LiveKit

> Harness: `spikes/remote-browser/` (see its README for rationale and run order).
> **Status: RUN 2026-08-04** against the live `watchparty-livekit` on
> `watchparty-net`, LiveKit 1.13.2, Chromium 151.0.7922.71, host with 20 cores.
> Stage: looping H.264 video (Sintel trailer, 854x480@24 upscaled to 1280x720)
> plus a codec-independent 60fps canvas control.
> Supersedes the transport half of `docs/specs/2026-07-20-neko-spike-decision.md`;
> that record's findings about Neko's own API remain accurate for Neko.

## Hypothesis

A containerised Chromium can publish its own screen and audio into the LiveKit
room we already operate, as an ordinary publish-only participant. If that holds,
we never write a media server, a signalling layer, or a client — and the Flutter
clients get the feature for free, because they already speak LiveKit.

## Why we are re-deciding

`feature/neko-collab-browser` reached a working spike (`docs/specs/2026-07-20-neko-spike-decision.md`,
GO on 8 of 8 probes) and then spent 29 commits and ~6,700 lines going wrong in one
specific place. Neko owns its transport, so the integration had to grow a
same-origin proxy, a cookie relay, a path-prefix allow-list, and ultimately a
hand-port of Neko's WebRTC client. That port and its vendored keysym tables are
2,403 of those lines, and every commit after it is a bug inside it.

The split is worth stating precisely, because it decides what we keep:

| Layer | Lines | Verdict |
|---|---|---|
| `app/server/neko/{routes,lease,proxy,idle,teardown,detach}.js` | 646 src / 884 test | **Keep.** Lifecycle and control-lease. Ours, tested, not Neko-specific. |
| `nekoConnection.ts`, `guacamoleKeyboardCore.ts`, `NekoScreen.tsx`, … | 2,403 | **Drop.** A remote-desktop client we'd own forever. |

`proxy.js` goes too under this architecture — it existed only because Neko served
its own client from its own origin.

## Probes

| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1 | Chromium publishes a screen track into an existing room | **PASS** | `published video track` + `published audio track` as identity `remote-browser` in room `spike-remote-browser` |
| 2 | Capture starts with no picker dialog | **PASS** | `--auto-select-desktop-capture-source="Entire screen"` resolves to `screen:0:0`; requires Xvfb `-extension RANDR` (see below) |
| 3 | Sustained ≥25 fps at 720p, no freezes | **PASS** | send: `1280x720`, `fpsSent 30 / fpsCaptured 30`, `qualityLimitationReason: none`. receive: `1280x720 @ 30fps`, **freezes 0**, frames dropped 0, packets lost 0 (0.00%), nacks 0, plis 0, jitter buffer 8ms |
| 4 | Bitrate within ~2.5 Mbps | **PASS (marginal)** | 1.3–3.0 Mbps at 720p30; brief excursions above the 2500 cap on scene changes |
| 5 | CPU cost per party | **PASS** | **avg 47.2% of one core, peak 72.2%** over 60s at 720p30 (was 39%/81% at 15fps) |
| 6 | Memory cost per party | **PASS** | **531 MiB** RSS, versus the 3–4 GB/room the Neko notes assumed |
| 7 | Audio captured, published and audible | **PASS** | 2ch 44100Hz, `echoCancellation/noiseSuppression/autoGainControl` all off; `media-source.audioLevel 0.0031 (sound present)`. Needs `module-remap-source` AND a viewer unmute gesture (both below). Long-run A/V drift not measured. |
| 8 | H.264 available for hardware decode on iOS | **PARTIAL** | `send codecs=VP8,rtx,H264,AV1,VP9,red,ulpfec`; decode `h264/vp8/vp9/av1` all "probably". But the receiver reported `decoderImplementation` empty, and the default run negotiates `video/VP8`. `CODEC=h264` end-to-end, and a real iPhone, still untested. |
| 9 | Injected mouse/keyboard reaches the page | **PASS** | Interactive viewer: click, drag, right-click, wheel, touch and keyboard all forwarded and landing. Confirmed navigating and scrolling real sites, and confirmed by the operator driving it directly. |
| 10 | Input latency under ~150 ms | NOT MEASURED numerically | Operator reports it "works well" interactively, so it is not obviously bad. No figure taken; `rtt` instrumentation is still broken (see below). |
| 11 | Cursor visible in the stream | **FAIL (expected)** | capture settings report `cursor: "never"`. Not a blocker — render client-side from the controller's own pointer. |
| 12 | **YouTube plays with audio** (the stated acceptance bar) | **PASS** | 4K60 source, captured and published at 1280x720@30, 2.2–4.3 Mbps, `audioLevel 0.2064`. Costs ~40% more CPU and ~2x the memory of a local clip — see sizing. |
| 13 | DRM playback (Netflix/Disney+/Prime) | NOT TESTED | Out of scope — YouTube is the bar. Assume unavailable. |

## 720p vs 1080p

Both sustain 30fps with `qualityLimitationReason: none`. Publisher-only figures, no
subscriber decoding in the same container:

| | 720p30 | 1080p30 |
|---|---|---|
| CPU avg / peak (of one core) | 0.47 / 0.72 | 0.89 / 1.86 |
| Memory | 531 MiB | 730 MiB |
| Bitrate | 1.3–3.0 Mbps | 3.6–6.3 Mbps |
| Keyframes | flat | flat |

1080p costs about 1.9x the CPU and roughly double the bandwidth. Even so it is still
under one core average, an order of magnitude below the 4–8 vCPU/room the Neko notes
assumed.

Which to pick depends on what is on screen, and the two pull opposite ways:

- **For browsing, 1080p is a real usability win.** At 720p a full-width page renders
  small text as mush, because the text is being resampled twice — laid out at 1920
  logically, then encoded at 1280. Verified by screenshot: Wikipedia body text is
  comfortably legible at 1080p and marginal at 720p.
- **For video, 720p is the better trade.** The stage is already upscaled from the
  source, so 1080p spends double the bandwidth re-encoding detail that was never in
  the original.

Bandwidth is the number that scales badly: 4–6 Mbps per party at 1080p against
1.3–3 Mbps at 720p, and that is VPS egress per concurrent party. Recommendation:
default to 720p, and treat 1080p as opt-in for browsing-heavy use.

### A keyframe storm that was not what it looked like

A first 1080p run showed `keyframes` climbing past 167 at ~1.75/s, where 720p had
produced about seven in total — enough extra bitrate to matter. It looked like an
encoder problem at 1080p. It was not. Re-run as a controlled pair:

- no subscriber: `keyframes: 5, plis: 0, nacks: 0`
- healthy local subscriber: `keyframes: 6, plis: 1, nacks: 0` — flat

So keyframe generation is receiver-driven, and the storm came from a subscriber
reconnecting repeatedly (LiveKit logged `CLIENT_REQUEST_LEAVE` and a rejoin for
`spike-viewer`); every reconnect forces a fresh keyframe. Recorded because the
symptom is easy to misread as a resolution or encoder fault, which is how it was
first read here. `plis`/`nacks` are now in the publisher's stats line so the next
occurrence is diagnosable at a glance.

Instrumentation gap: `rtt` logs as `?` — `roundTripTime` lives on
`remote-inbound-rtp`, not `outbound-rtp`, so it is not being read. Harmless, but the
field is currently useless.

## Sizing for the prod VPS

Prod is **8 shared EPYC vCPUs @ 2.0 GHz, 23 GiB RAM, no swap**. Everything measured
above ran on the dev box — an **i7-12700T, 20 threads @ 2.8 GHz, 31 GiB, with swap**.
Those are not comparable: Golden Cove at 2.8 GHz is roughly 1.5–2x a 2.0 GHz Zen core
per thread for this kind of SIMD work, and a shared vCPU adds steal time on top. Treat
every dev figure as optimistic and re-measure on prod with the same harness —
`CPUS=2 ./probe.sh up && ./probe.sh stats 60` — rather than trusting a conversion.

**The binding constraint is egress, not CPU.** LiveKit is an SFU: it sends one copy
per subscriber. A four-person party watching a 2 Mbps remote browser is 2 Mbps in and
**8 Mbps out**, before cameras and mics. At 1080p that is 4–6 Mbps in and 16–24 Mbps
out. Check the VPS uplink and monthly allowance before tuning anything else.

### Measured under a 2-CPU cap (`CPUS=2`, dev box)

| | 720p30 local clip | 1080p30 local clip | **720p30 YouTube** |
|---|---|---|---|
| CPU avg / peak (of one core) | 51.4% / 79.8% | 114.8% / 192.7% | **73.3% / 160.2%** |
| Memory | 542 MiB | 640 MiB | **1.00 GiB** |
| Bitrate | 1.9–2.8 Mbps | 1.9–5.6 Mbps | **2.2–4.3 Mbps** |
| 30fps held | yes, headroom | yes, **saturated** | yes |

**YouTube is the number that matters, and it is ~40% more CPU and nearly 2x the
memory of a local video file at the same output resolution.** It is a heavy web app:
player JavaScript, a high-resolution source being decoded and downscaled, and its own
network activity. Anything sized against a bare `<video>` tag will be undersized.
Audio confirmed present (`audioLevel 0.2064, energy rising`).

1080p peaks at 192.7% against a 200% ceiling — it is pinned to the limit. It still
holds 30fps *on this fast silicon*, with no headroom left. Apply the 1.5–2x
slower-core penalty and 1080p at 2 vCPUs on prod will not hold 30fps; it needs closer
to 4 vCPU, i.e. half the machine.

720p at 51% average and 80% peak of a single core has genuine room. Even at the
pessimistic end of the penalty that is roughly 1.0 core average and 1.6 peak on prod —
comfortable inside a 2 vCPU allocation.

A caveat on the bitrate column: this is a mostly-dark animated trailer. Bright,
high-motion content will sit higher, and the 1080p range already brushes its 6 Mbps
cap.

### Allocation: 4 vCPU / 10 GB (operator's decision)

With 4 vCPU the 720p YouTube figure above — 160% of a core at peak on the dev box,
so roughly 2.4–3.2 vCPU on prod — fits with real margin. That is the configuration to
ship.

**1080p + YouTube at 4 vCPU is not established.** Estimating from the two valid
measurements (1080p local clip peaked at 192.7%, YouTube carries a ~40% CPU premium)
puts it near 270% on the dev box, i.e. **4–5.4 vCPU on prod** — at or past the
allocation. Do not commit to 1080p until it is measured with a working YouTube.

On **10 GB**: `mem_limit` is a ceiling, not a reservation. Measured peak usage is
1.00 GiB, so a 10 GB limit never binds and therefore stops protecting anything. Its
purpose is to bound the container so the *rest* of the box survives; on a no-swap host
also running Jellyfin, the *arr stack and postgres, a 10 GB ceiling lets a leaking
Chromium reach 10 GB before the cgroup intervenes, by which point the kernel may
OOM-kill something else instead. **~3g is the better limit** — 3x measured, enough for
heavy multi-tab use, and it fails the browser fast and loudly. Use `mem_reservation`
if the intent is to guarantee availability rather than to cap.

### Measurement hazard: the interception recurs

A 4-vCPU YouTube run produced 21.4% CPU at a flat 430 kbps with 480 MiB — a *cheaper*
and entirely fake result, because the Sophos privacy error had returned and the
"video" was a TLS error page. It was caught only by `audioLevel` reading `SILENT`.
**Always confirm `audioLevel` shows sound and take a `./probe.sh shot` before trusting
any measurement.** A static page yields a rock-steady bitrate and a flattering CPU
number, and nothing else in the stats distinguishes it from success.

Recommendations, in order of how much they matter:

1. **720p at `cpus: 4`** (the operator's allocation). YouTube peaks at 160% of a core
   on the dev box → ~2.4–3.2 vCPU on prod, so 4 leaves genuine margin for the peaks
   that matter: page load, ads, quality switches. Throttling here surfaces as dropped
   frames, so margin is worth more than tightness. The 73% average means it will not
   sit at 4. **1080p stays unproven at this allocation** — see above.
2. **`mem_limit: ~3g`, not 10g.** YouTube measured **1.00 GiB** RSS against 542 MiB for
   a local clip, so 1g would OOM-kill — and with **no swap on prod that is a kill, not
   a slowdown**. 3g is 3x measured with room for many tabs, while still bounding a
   runaway. `/dev/shm` is charged to the container under cgroup v2, so the limit must
   cover `shm_size: 1g` on top of RSS.
3. **Keep simulcast off — but lower the cap.** Simulcast is the single biggest CPU
   saving available and 8 shared vCPUs cannot afford three layers of full-motion
   video. The cost is no per-viewer adaptation: a viewer on poor mobile gets the full
   bitrate or nothing. On this box, prefer a lower ceiling (~1.5 Mbps at 720p) over
   adding layers.
4. **Jellyfin is the other big consumer.** A software transcode can saturate all 8
   vCPUs on its own; a remote browser running at the same time will contend. Favour
   direct play, and cap Jellyfin's transcode threads.
5. **One container, one party.** The existing single-global-instance design in
   `app/server/neko/lease.js` is the right shape here. Do not attempt concurrent
   per-party containers on 8 shared vCPUs.

## What broke, and why it matters

Four failures, none of which announced itself honestly. These are the spike's real
output — the architecture was never the risk.

1. **Xvfb + RANDR silently kills screen capture.** Xvfb advertises RANDR 1.6 with
   no CRTC or output behind it. Chromium's `ScreenCapturerX11` takes the XRandR
   path whenever the extension is present, enumerates monitors, finds none, and
   `SelectSource("screen:0:0")` returns false. The page sees only
   `NotReadableError: Could not start video source` — *after* the log has cheerfully
   reported SHM v1.2 and XRandR v1.6 working. Only `--vmodule=*desktop_capture*=3`
   showed the real line: `DesktopCaptureDevice::Create fails because … SelectSource
   … is false`. Fix: `Xvfb -extension RANDR`, which falls back to root-window grab.
2. **Chromium filters PulseAudio monitor sources.** Monitors aren't microphones, so
   pointing the default source at `spike_sink.monitor` gives
   `NotFoundError: Requested device not found` and `audioinput count=0`, despite
   `pactl` listing it. Fix: `module-remap-source` republishes it as an ordinary
   source. Neither `PULSE_SERVER` nor `AudioServiceOutOfProcess` was involved.
3. **`screenShareEncoding` overrides `videoEncoding`.** livekit-client:
   `if (isScreenShare) videoEncoding = options.screenShareEncoding`. A
   ScreenShare-source track therefore *discards* `videoEncoding` and takes the
   default `ScreenSharePresets.h1080fps15` — pinning the stream to exactly 15fps.
   The symptom reads as a capture or CPU ceiling and is neither: `getDisplayMedia`
   delivered a clean 30fps when measured directly with
   `requestVideoFrameCallback`, and CPU sat at 39% of one core throughout.
4. **The obvious test video was a static error page.** Google's public
   `gtv-videos-bucket/BigBuckBunny.mp4` now returns `AccessDenied`, so the "video"
   was XML. A bare `.mp4` URL is the same trap by another route — it plays once and
   freezes on its last frame. Both turn a motion test into a still-image test while
   every number still looks plausible. The harness now serves a looping player page
   and a canvas control.

### Two more, from making the viewer interactive

5. **One request per input event wedges the tab.** The first interactive viewer sent
   a `fetch()` per `pointermove` at 40/s. Chrome allows ~6 concurrent connections per
   origin, so the moment the server fell behind the excess queued in the network
   stack without bound. The tab went "Page Unresponsive" and — the diagnostic tell —
   **could not be reloaded**, because a reload waits on in-flight requests. Fixed by
   batching with exactly one request in flight, coalescing consecutive moves, and
   capping the queue at 64 while dropping stale *moves* in preference to clicks and
   keystrokes. **This is a hard design constraint for the real feature**, not a spike
   artefact: whatever carries input (Socket.IO, a data channel) needs bounded
   concurrency and move coalescing, or a fast mouse takes the page down.
6. **Audio was captured but never played.** The container's capture was correct all
   along — two Chromium sink-inputs feeding the null sink, `spike_sink.monitor` and
   `spike_mic` both `RUNNING`, and `media-source.audioLevel = 0.0031` in the
   published stream. The viewer auto-connects, so there is no user gesture and every
   browser refuses audible playback; `audioEl.play()` rejected silently, which is
   indistinguishable from "the stream has no audio". Fixed with an explicit Sound
   button, and `audioLevel` is now logged so the two cases can be told apart. The
   real feature inherits this: a party surface that starts streaming on load needs a
   deliberate unmute affordance.

Corrections to earlier assumptions in this document's first draft: H.264 **is**
present in Debian's Chromium (no need for Google's .deb), and occluded-window
throttling was **not** the cause of the 15fps — the anti-throttle flags remain only
as hygiene for a permanently hidden publisher window.

## Verified without running anything

- **Token scoping works.** `mint-token.mjs` resolves the repo's existing
  key/secret and produces correctly scoped grants — decoded from the JWTs:
  publisher `{roomJoin, room, canPublish: true, canSubscribe: false}`, viewer the
  inverse, both room-scoped, 4h expiry. `canSubscribe: false` on the browser is
  deliberate: a misconfigured container must not be able to pull participants'
  cameras into a server-side browser.
- **The network path exists.** `docker-compose.yml` declares `watchparty-net` with
  an explicit `name:`, so it is not project-prefixed and the spike attaches to it
  as `external`. The container reaches `ws://livekit:7880`, the same address
  `app/server` uses.
- **`livekit-client` 2.20.0** is already vendored from the repo's `node_modules`,
  so the image builds with no network access to npm.

## Blocking issue found while setting this up

`watchparty-livekit` is in a restart loop (`Restarting (0)`). `docker-compose.yml:44`
bind-mounts `./livekit.yaml:/etc/livekit.yaml`, but `./livekit.yaml` is an empty
**root-owned directory** — the signature of Docker auto-creating a missing
bind-mount target. LiveKit then starts with `--config` pointing at a directory.
`docker-compose.prod.yml:70` mounts `./secrets/livekit.yaml:/etc/livekit.yaml:ro`
correctly; dev was never brought in line.

Confirmed by behaviour: with the mount corrected LiveKit went from `Restarting (0)`
to `Up` and stayed up. The failing log itself was never captured, so the causal link
is inferred from the single-variable change rather than read directly.

Local dev only — prod mounts the config correctly and the operator confirms LiveKit
is healthy there.

Fix applied: mount `./secrets/livekit.dev.yaml` (see next section for why a dev-specific
file rather than the prod one), then `sudo rmdir livekit.yaml`.

## RESOLVED: LiveKit was advertising an unreachable IP (local dev only)

A subscriber run inside the container fails with
`ConnectionError: could not establish pc connection`, and LiveKit logs the reason:

```
participant: spike-viewer   transport: PUBLISHER
stats: [{"state": "failed", "nominated": false,
         "local": "203.0.113.11:7882 udp type(host/), priority(2130706431)"}]
```

`203.0.113.11` is the host's **public** IP. `secrets/livekit.yaml` sets
`rtc.use_external_ip: true` and the dev compose sets no `NODE_IP`, so LiveKit
STUN-discovers the public address and offers it as its only host candidate. Note
the earlier startup log also shows the discovery only half-succeeding:
`could not validate external IP … context canceled` → `no external IPs found,
using node IP for NAT1To1Ips {"ip":"203.0.113.11"}`.

Reproduced independently in a browser on the host — same
`ConnectionError: could not establish pc connection` — so this was never an artefact
of running the subscriber inside a container.

**`NODE_IP` does not fix this.** It was tried first, mirroring
`docker-compose.prod.yml`, and verified present in the container
(`NODE_IP=172.19.0.1` in `docker exec … env`), yet LiveKit still logged
`nodeIP: 203.0.113.11`. When `rtc.use_external_ip` is true it overwrites the node
IP from STUN discovery at startup, so the env var is inert. Worth recording, because
the comment in `secrets/livekit.yaml` implies `NODE_IP` is the knob and it is not.

**Fix applied:** a dev-only config, `secrets/livekit.dev.yaml`, generated from the
prod one with `rtc.use_external_ip: false`, mounted by `docker-compose.yml`. Prod
keeps `secrets/livekit.yaml` unchanged via `docker-compose.prod.yml`. This restores
the dev/prod split the original compose already implied — it mounted `./livekit.yaml`,
a dev-specific file that had gone missing, which is why Docker created an empty
root-owned directory in its place and LiveKit crash-looped. Pointing dev at the prod
config was the expedient first fix and conflated the two.

Verified after the change:
- `nodeIP: 172.19.0.3` (LiveKit's own container address), no STUN discovery.
- The host can route to it: `http://172.19.0.3:7880` → HTTP 200 from the host
  network namespace, so browsers on this machine reach the advertised media address.
- A subscriber now connects and receives cleanly: **1280x720, 30fps, 1089 kbps,
  video/VP8, packets lost 0 (0.00%), jitter 0.0ms, jitter buffer 8ms, freezes 0,
  frames dropped 0, nacks 0, plis 0** over 569 decoded frames.

### Scope: this is a local-dev bug only, NOT the camera regression

An earlier draft of this document called it "a strong candidate for the camera
regression that has outlived several sessions". **Retracted** — the operator confirms
cameras work on the deployed site and LiveKit is healthy on prod.

The reason it never affected prod is that `use_external_ip: true` is *correct* there:
`docker-compose.prod.yml` supplies `NODE_IP=${VPS_PUBLIC_IP}`, and a client on the
internet genuinely can reach the VPS public address. The same setting is wrong only on
a local box, where LiveKit discovers *this machine's* public IP and offers it to
clients sitting inside the same LAN, who would have to hairpin back through the router
to reach it.

So the failure shape — signalling succeeds, media never establishes — is real, but its
blast radius is local and tailnet development only. Anything still outstanding on
cameras is a separate investigation and should not be closed on the strength of this
finding.

## GO / NO-GO

**GO — confirmed end to end, operator-verified.** The hypothesis holds and the cost is
far better than assumed.

Recommended starting configuration for prod: **720p30, `cpus: 4`, `mem_limit: 3g`,
`shm_size: 1g`, simulcast off, one container per party via the existing lease.**
YouTube plays with audio, which was the stated acceptance bar.

Environment gotcha worth recording: on the network this was developed on, a **Sophos
TLS-inspection appliance** re-signed Google traffic, so Chromium showed "Privacy error"
and YouTube would not load at all — while Wikipedia and GitHub did, being on the
bypass list. The appliance presents only the leaf certificate, so its CA cannot be
recovered from the connection; it has to come from IT. `entrypoint.sh` will trust any
`.crt` dropped in `extra-ca/` (into both the system store and Chromium's NSS store,
since Chromium may consult either). The interception later stopped on its own without
the CA being installed, so it appears intermittent — expect it to return, and do not
mistake it for a remote-browser fault. Irrelevant on a VPS.

- Probes 1–8 pass. A containerised Chromium publishes 1280x720@30 video plus
  2ch/44.1kHz audio into the existing LiveKit room, with no picker, no media
  server, no signalling layer, and no client code.
- **CPU: 0.47 cores average, 0.72 peak. Memory: 531 MiB.** Against a GO bar of two
  cores, and against the 4–8 vCPU / 3–4 GB per room the Neko notes assumed. That
  is roughly an order of magnitude cheaper than the abandoned approach and changes
  what concurrency is plausible on one VPS.
- H.264 is available for send, so iOS viewers can hardware-decode.
- The whole 2,403-line client layer and `proxy.js` stay deleted; the 646 lines of
  lifecycle in `app/server/neko/` carry over unchanged.

Caveats to carry into the spec rather than discover later: bitrate briefly exceeds
its cap on scene changes (1.3–3.0 Mbps against a 2500 kbps setting); simulcast is
off, so a viewer on a weak link cannot drop a layer; and the cursor is not captured
(`cursor: "never"`), which should be drawn client-side.

Still unmeasured, and worth closing before committing to the spec: client-side
`decoderImplementation` on a real iPhone, input latency, long-run A/V drift, and
DRM. None of these can change the GO — they size the experience, not the
feasibility.

## Not in scope

- **Multi-tenancy.** One container, one party, unchanged from the branch — which
  ran a single global instance with `NEKO_RECREATE_MODE=noop`, i.e. no isolation
  between parties at all. Rebuilding the media path does not touch this.
- **DRM.** Assume Netflix, Disney+ and Prime do not work. Widevine is L3-only in a
  container, streaming services reject datacenter IPs, and Chromium blanks
  protected content under `getDisplayMedia` regardless of who owns the container.
- **Cursor fidelity.** Render it client-side from the controller's own pointer
  position. Lower latency than capturing it, and it is what Neko did.
