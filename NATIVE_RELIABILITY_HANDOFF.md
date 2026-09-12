# Native reliability diagnosis and implementation plan for 5.5

Baseline: `0d076c8`. This started as a diagnosis handoff and now tracks the
completed automated reliability pass.

## Implemented in this pass

- Track-only and title-metadata updates preserve the media revision, so
  `PlayerHost` does not reopen or seek the native player.
- Follow/Lead labels now match across Flutter and web while retaining the legacy
  `dragging`/`hopping` wire values. Follow no longer silently resumes after 30s;
  recovery, disconnect, mode change, or kicking the stalled member releases it.
- Native buffering blocks automatic correction. Recovery starts when buffering
  ends, applies authoritative pause independently, suppresses automatic seeks,
  and rejects non-finite or beyond-duration automatic targets.
- The native cache uses a bounded shared HTTP client, per-request
  cancellation, expiring single-flight signed URL reuse, body-idle timeouts,
  classified integrity/transient failures, and one bounded transient retry that
  honors integer and HTTP-date `Retry-After` values.
- Opt-in redacted diagnostics use a bounded monotonic ring buffer and JSON
  export. Enable with `WATCHPARTY_SYNC_DIAGNOSTICS=true` and/or
  `WATCHPARTY_CACHE_DIAGNOSTICS=true` as Dart defines.
- The headless sync harness is executable against the TypeScript sync source and
  covers stalled-member kick recovery. HLS scenarios explicitly select Lead.

True two-person P2P A/V is intentionally not mixed into this reliability patch.
LiveKit remains the production SFU transport. Direct P2P requires the separate
authenticated WebRTC signaling and transport design in section E, including a
new direct Flutter dependency, coordinated fallback, TURN policy, privacy review,
and physical NAT testing. Shipping a partial signaling scaffold would not be a
safe or functional P2P implementation.
Reported symptoms are not yet reproduced on the affected devices. Distinguish
confirmed code behavior below from hypotheses needing telemetry.

## Goal and priority

Make one movie reliably play for a fast host and a slow guest without seeking
the slow guest into perpetual buffering. Track changes must not reopen the file.
Downloads must approach the throughput of a comparable direct HTTP transfer.
Expose honest state and failure reasons rather than relying on reassuring badges.

Implement in order: observability/reproduction, track-change isolation, buffering
state machine and modes, transfer pipeline, integrated device verification.
Treat two-person P2P A/V as a separate transport project after playback stabilizes.

## Confirmed causes and suspected mechanisms

### 1. Endless buffering and both sync modes behaving similarly (P0)

- `flutter_app/lib/sync/sync_engine_impl.dart:413-468`: tick checks opening/busy/
  host-gone, but not local buffering before deciding/applying seek/rate/play.
- `flutter_app/lib/sync/sync_core.dart:144-179`: the decision input has no
  buffering/readiness state. Both guest modes hard-seek above 5s drift.
- Awaiting `PlayerController.seek` serializes command completion; it does not
  prove decoded frames or sufficient buffered runway are available.
- `app/server/index.js:1101-1149`: dragging/follow freezes the timeline for
  stalled members. The previous silent 30s auto-resume has been removed in this
  implementation pass.
- Frozen schedule handling can seek a lagging guest onto a host-ahead frozen
  position, despite the guest still needing bytes at its current position.

### 2. Pointer jumping to the end (P0, exact incident cause unconfirmed)

- `sync_core.dart:63-67`: expected position grows from wall time with no duration
  bound. Automatic seeks use that prediction without an EOF/readiness guard.
- `sync/server_clock.dart:60-61`: prediction uses DateTime plus an offset;
  readiness never expires after missing samples. Sleep/wake, stale schedules,
  time adjustments and long stalls need explicit recovery handling.
- `analog/player/analog_timeline.dart:162-164`: position/duration is clamped to
  100%. An invalid position OR temporarily incorrect duration can appear as an
  end-of-movie pointer even without a real seek to EOF.
- Distinguish local playhead, peer pointer and downloaded overlay in captures.
  Do not diagnose all three as a seek based on appearance alone.

### 3. Subtitle changes reopen playback (P0, confirmed)

- `state/party_playback.dart:251-292` includes selected subtitle/audio in the
  equality test, then calls `nowPlaying.open` when either changes.
- `state/now_playing_provider.dart:100-125` increments playback revision for
  track-only changes. PlayerHost responds by reopening the file.
- Server `party:setPlaybackTracks` refreshes track state without resetting the
  timeline (`app/server/index.js:798-837`). Native state conflates track changes
  with media replacement. Restoring the schedule after open does not make an
  unnecessary reopen acceptable.

### 4. Download/stream throughput and repeated failures (P0/P1)

- `cache/media_cache_proxy.dart:582-631`: every range mints a signed URL and
  creates a fresh HttpClient; it is closed after each response. No connection or
  signed-capability reuse. Sequential 8MiB downloads still pay this overhead.
- `media_cache_proxy.dart:375-397`: foreground misses now fetch/validate/store
  then reread each 1MiB chunk before forwarding. This changed in the last fix;
  explicitly benchmark against the previous streaming behavior.
- `media_cache_proxy.dart:553-562`: a 30-second WHOLE-body deadline rejects even
  a steadily progressing 8MiB transfer below approximately 2.24Mbit/s. Partial
  bytes from that request are discarded. Retrying with the same policy can
  fail indefinitely on a slow connection.
- Playback, read-ahead and downloads lack a shared priority/range-reservation
  scheduler. Overlapping consumers can compete for bandwidth or duplicate work.
- `state/downloads_provider.dart:190-205`: bounded title-level retries are not
  a substitute for classified per-range recovery; UI lacks useful error detail.
- Actual bottleneck remains unmeasured: local proxy, app server, reverse proxy,
  Jellyfin, disk and transport must be timed separately.

## Implementation contracts

### A. Instrument first

Add bounded, exportable, redacted diagnostic records with monotonic timestamps,
app/build/OS, media generation/source, local position and duration, schedule
version/phase/position/t0, clock freshness, buffering transitions, seek reason /
target / command completion / first frame, native errors, range offset/status,
TTFB, transfer rate, retry reason, cache hit and disk timing. Never log signed
tokens, cookies or Jellyfin API keys. Surface concise reasons in the UI.

Reproduce with a deterministic slow HTTP origin, delayed native seek completion,
separate decoded-frame readiness, mid-body stalls and disconnect/reconnect.
Capture the affected build IDs, timestamps, media source and server version.

### B. Isolate track selection

Separate media identity/revision from track selection/presentation revisions.
Only a changed item/source or explicit recovery should call native `open`.
Apply embedded audio/subtitle and external subtitle changes to the existing
controller; preserve current position, playing/paused state, rate and cache.
Use generation guards for rapid selections and delayed subtitle fetches.

Acceptance: change subtitles A -> B -> Off -> A while playing, paused, buffering
and at a nonzero resume point. Zero additional media opens, no seek to zero,
no transport command authored, all participants display the selected track.

### C. Define Follow / Lead behavior before changing labels

Proposed mapping (explicit product assumption):
- **Follow** replaces Dragging: the room waits for struggling participants.
- **Lead** replaces Tailing/Hopping: the host continues; guests recover locally.

Use helper descriptions to make the distinction clear. For compatibility, retain
legacy wire enum values initially and map labels in Flutter/web; if wire values
change, normalize old values server-side and migrate persisted room state.

Follow: freeze room advancement on genuine participant buffering. Do not silently
resume after 30s; show who is buffering/failed/disconnected and host choices to
continue in Lead or remove a participant. Handle disconnected membership separately
from a still-connected buffering player. Avoid paused/buffering feedback loops.

Lead: host continues, but a buffering guest must not repeatedly chase the moving
live edge. Let usable data/frames accumulate, then perform a bounded recovery.
After repeated failed recoveries, require an explicit retry/quality action;
do not use endless hard-seek loops as bandwidth adaptation.

Introduce explicit local states: opening, ready, playing, buffering, seeking,
recovering, paused, completed, failed. Keep room intent distinct from local
readiness. A seek Future is not the readiness signal. Add media_kit buffer/frame
signals through PlayerController as needed and update fakes accordingly.

Automatic correction requires fresh schedule/clock, stable valid duration,
current media generation and local readiness. While buffering, retain the last
confirmed playhead; no automatic forward seeks. Authored host seek is a distinct
event that may supersede recovery once, then waits for readiness.

Reject nonfinite/out-of-range automatic targets and handle completed state
explicitly. Do not clamp a huge stale prediction to duration and seek to EOF.
Invalidate/re-establish the clock after sleep/reconnect or implausible jumps;
use monotonic elapsed time anchored to a fresh server epoch sample.

Acceptance: 60-120s guest stall, repeated jitter, sleep/wake, stale clock,
paused buffering, near EOF and explicit seek during recovery. No autonomous EOF
jump, no repeated forward seeks while stalled, distinct Follow/Lead behavior,
and accurate host-visible status throughout. Update shared JS/Dart contract
fixtures with the semantics rather than preserving faulty parity.

### D. Replace per-range connection churn with a transfer pipeline

1. Benchmark same source via direct Jellyfin, app native-file endpoint and local
   cache proxy, same device/network/storage. Report MiB/s, TTFB, CPU and failures.
2. Reuse bounded per-origin HTTP connections and cache signed capabilities by
   origin/account/source/purpose until near expiry. Single-flight refresh on
   expiration/401; invalidate on logout/server change. Do not expose upstream keys.
3. Shared scheduler for playback/read-ahead/downloads: playback priority, bounded
   global concurrency, reserve missing intervals to deduplicate overlap. Start
   conservatively (e.g. 2-4 download requests); tune from benchmarks, not promises.
4. Stream valid foreground bytes promptly without disk reread. Validate status /
   Content-Range before forwarding; bound the body and handle truncation. Cache
   writes must be committed only when their intended units are verified; preserve
   byte integrity when requests overlap, fail or are canceled.
5. Use connection/header deadlines and BODY-IDLE deadlines that reset on actual
   progress. Size chunks adaptively or choose throughput-appropriate windows.
   Cancellation aborts immediately; bounded per-range transient retries use
   jitter/backoff, honor Retry-After, and preserve verified completed intervals.
6. Keep corruption/representation/auth failures distinct from timeouts. Detect
   source changes with strong validators when the upstream supports them; never
   splice two representations. Address disk-full explicitly.

Acceptance: hash-equal completed files; cancel/resume/restart; short/overlong/
wrong-range bodies; 401/429/5xx; slow-but-progressing responses; midstream resets;
simultaneous playback/download; disk-full; explicit source and origin switches.
Agree a benchmark target (initially >=80% of comparable direct HTTP throughput on
a controlled fast link) and publish measured results. Never describe 8x fewer
requests as an 8x throughput guarantee.

### E. Two-person peer-to-peer A/V (separate milestone)

LiveKit's documented architecture is an SFU, including two-person rooms:
https://docs.livekit.io/reference/internals/livekit-sfu/
`flutter_app/lib/livekit/livekit_room.dart` wraps lk.Room; there is no existing
participant-count toggle that turns it into browser/device-to-device transport.

If direct two-person A/V is required, add a separate WebRTC transport behind the
A/V service interface. Exactly two approved compatible participants negotiate
authenticated SDP/ICE signaling, with STUN and TURN fallback. A failed direct
connection falls back to LiveKit. Three or more use LiveKit. Count admitted room
membership, not enabled cameras. Capability negotiation protects older clients.

Transport transitions need hysteresis, explicit ownership of capture/tracks,
muting/PTT preservation, no duplicate audio, interruption bounds and cleanup.
Test 1->2->3->2, blocked UDP, TURN-only NAT, reconnect, host transfer and logout.
TURN-relayed WebRTC is not direct P2P; show actual selected transport honestly.
This changes camera/microphone routing, not movie HTTP delivery, and cannot by
itself fix movie buffering or download throughput. Direct P2P also exposes peers'
network addresses, which must be accounted for in the product decision.

## Execution and verification for 5.5

- Keep separate commits for track selection, sync/modes, transfers, and P2P.
- Add failing scenario tests before each behavior change. Avoid fakes that equate
  seek command completion with ready-to-play video.
- Use CI-pinned Flutter 3.44.5 / Dart 3.12.2 and the repository's existing
  `tool/apply-flutter-semantics-fix.sh`, not a newer incompatible SDK.
- Automated verification completed in this pass: clean Dart analysis, 696
  Flutter tests, 125 server tests, 429 web tests, production web typecheck/build,
  and all 28 live headless sync scenarios. That demonstrates regression
  coverage, not real-network readiness.
- Run physical macOS/Windows hosts and guests with fast/slow roles reversed,
  long movies, external/embedded subtitles, disk cache and concurrent A/V.
- Completion requires diagnostic captures, a benchmark table, stable playback
  through a sustained slow-link scenario, and no unexplained autonomous seeks.
- Preserve cache v3 validation/migration guarantees; do not solve performance by
  restoring unchecked writes or deleting user downloads silently.

Open questions for reproduction: which pointer moves, exact affected build,
movie/container/runtime, solo versus party subtitle behavior, where the comparison
download runs, and whether the host should wait indefinitely by default. These
do not block writing regression scenarios for the confirmed code paths above.
