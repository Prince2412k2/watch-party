# KEEL — the perfected watch-party sync algorithm

**Status:** approved design, implementation-ready.
**Provenance:** synthesized from four competing proposals (SERVO, Bedrock, MAESTRO, RUNWAY) and three judge panels (correctness & robustness; sync quality & perceptual UX; implementation cost, risk & testability). **Spine: Bedrock** (ranked #1 by two of three judges — correctness-first protocol hardening, barriers-as-schedules, constants-as-floors). **Grafts:** SERVO's PI controller with skew feed-forward and flutter-proof actuator shaping; MAESTRO's certainty-gated error, `controlEpoch` authority fencing, and server monotonic timebase; RUNWAY's mandatory core-state round-trip, asymmetric runway rate caps, AMBER pre-stall stage, informed bounded holds, and late-join private rendezvous.

All file references are to the current `flutter-v1` tree; line numbers match the diagnosis (`app/server/index.js`, `app/server/session.js`, `app/client/src/sync/syncCore.js`, `app/client/src/hooks/useSyncPlay.js`, `app/client/src/hooks/useServerClock.js`, `flutter_app/lib/sync/*`).

---

## 1. Executive summary

The current system has good bones — a server-published parametric play-segment in Jellyfin ticks, extrapolated by one pure decision core mirrored on web and Flutter — but it fails in four ways: **protocol losses** (a 3-second blip orphans a guest forever; an undemoted ex-host free-runs against the room), **a clock that computes its own uncertainty and throws it away** (min-RTT offset steps manufacture fake drift that fires real HLS seeks), **compile-time constants** that treat a LAN desktop and a cross-region phone identically, and **no feedback loop** (telemetry is write-only).

KEEL keeps the parametric schedule, the tick wire unit, the socket.io relay authority, and the single-shared-brain architecture, and rebuilds everything around them:

1. **Clock:** monotonic timebase, outlier-rejected uncertainty-weighted offset with a Theil–Sen skew term, slew-never-step, readiness tiers — and its σ is *consumed by every threshold*.
2. **Controller:** an α-β drift estimator feeding a PI rate law on a certainty-gated error (you cannot chase noise you cannot measure), with skew feed-forward, anti-windup, runway-scaled asymmetric caps, slew-limited quantized actuation and direction dwell — audible flutter is structurally impossible.
3. **Seeks:** cost-modeled (rate-vs-seek economics on a per-guest measured seek cost) and executed as **aim-ahead rendezvous plans** that target where the timeline *will* be, killing the HLS chase loop; infeasible chases (fill rate ≤ 1) are never attempted.
4. **Stalls:** a graduated ladder — AMBER pre-stall prediction, a capability-gated 3% group pace slew, per-member informed hold budgets with progress-verified extension, a self-catch-up lane — replaces the binary freeze and 30 s cliff.
5. **Membership:** idempotent `session:attach` on every connect, `stateSeq`-versioned membership, away-grace linger, `mediaGeneration`/`controlEpoch` fencing, `commandId` retries — reconnect desync and stale-authority divergence become impossible by construction.
6. **Barriers:** every group discontinuity is a versioned *arming* schedule → prebuffer → ready-ack → future-`t0` release, so the room starts the same frame within clock error.
7. **Observability:** 1 Hz health reports from every member (host included) feed a server ledger that drives barriers, budgets, pace decisions, a room sync badge, and an asserted SLO. A **never-silent guarantee**: a client that cannot hold sync shows an out-of-sync badge with one-tap resync — silent free-running is unrepresentable.

The core stays one pure function pair (`syncCore2.js` ≙ `sync_core2.dart`), now equivalence-proven by generated JSON conformance vectors run in both CIs, with a **mandatory state round-trip** so the "implemented but never wired" bug class (FM2/FM6) cannot recur.

---

## 2. Goals & explicit sync SLO

All targets are *measured* (§4.6 ledger) and *asserted* (harness scenario `syncSlo`, §10). "Steady state" = no schedule change in the last 10 s. Link envelope: up to 300 ms RTT, 100 ms jitter, 1% loss.

| # | SLO | Target | Enforcement |
|---|-----|--------|-------------|
| S1 | Steady-state drift | p95 \|member − schedule\| ≤ 120 ms, p99 ≤ 250 ms for members with clock σ ≤ 100 ms ⇒ inter-member spread p95 ≤ 150 ms, p99 ≤ 300 ms | measured by ledger, asserted in harness |
| S2 | Rate flutter | playbackRate direction changes ≤ 1 per 10 s per member in steady state; rate steps ≤ 1%/tick, quantized 0.25% | structural (dwell + slew + quantization), verified from `rateFlips60s` |
| S3 | Hard seeks | ≤ 1 per disturbance event; ≤ 2 per 5 min steady state; 2+ unforced seeks in 30 s = chase-loop violation | plan state machine + re-seek guard; counted by ledger |
| S4 | Barrier starts | release spread p95 ≤ 120 ms in fully-capable rooms at clock tier ≥ good | one-shot `barrier:started` reports |
| S5 | Group holds | bounded by offender's budget (≤ 20 s absolute, typical 2–6 s); AMBER pace pre-empts ≥ 50% of would-be freezes | server grant machine + ledger |
| S6 | Reconnect | blip ≤ 90 s → resynced ≤ 5 s p95; host blip ≤ 5 s → zero room impact | harness `reconnect.js` |
| S7 | **Correctness KPI** | zero undetected desync: never \|drift\| > 1 s for > 10 s without a visible out-of-sync badge | never-silent guarantee, harness-asserted |
| S8 | Late join | first played frame within D_enter of the room; zero group disturbance | `joining` flag + private rendezvous |

Honesty clause: a member whose measured clock σ is 300 ms is *allowed* ~2σ of drift — we surface link-conditioned truth (badge/health) rather than flap against noise. The SLO is conditioned on clock tier by design.

---

## 3. Current pain points (from the diagnosis, abridged)

- **FM1** Reconnect desync: no `connectionStateRecovery`; clients emit `party:join`/`sync:hello` once per mount; a blip orphans a guest into silent free-run; a 2 s host blip force-pauses the room and phantom-transfers 30 s later.
- **FM2** Hysteresis (`SOFT_EXIT_SEC`, `correctionState`) implemented but never passed by any real consumer → audible rate flapping at the deadband edge.
- **FM3** `host:changed` never demotes the old web host (`role` stays `'host'`) → ex-host plays natively, ignoring the timeline forever.
- **FM4/FM5** All constants compile-time; clock uncertainty computed (`clockQuality()`) with zero call sites; min-RTT window aging step-changes the offset → fake drift → spurious hard seeks; one sample = "ready".
- **FM6** Binary dragging freeze + 30 s `STALL_MAX_MS` hostage window; Flutter never emits `sync:stall`; `stallFallback` clear never broadcast.
- **FM7** `bufferAwareSeek` seeks to *now*, buffers 4 s, re-reads once → on sub-realtime links the guest lands behind and re-seeks forever; `BUFFER_TIMEOUT_MS` "plays into starvation".
- **FM8** Host SPOF: hopping host exempt from loop and telemetry (room can sync to a timeline nobody watches); host loss = 30 s force-pause.
- **FM9** `sync:report` is write-only outside test mode; the system cannot know whether it works.
- **FM10** Client `t0` ignored (origin biased by controller uplink); `commandId`/`baseVersion` machinery dead on the wire.
- **FM11** Hand-mirrored dual core with already-diverged adapters; no conformance tests.
- **FM12** 0.4 s paused-hold slack — visibly different frozen frames.
- **FM13** Duplicated freeze-position truth (`reconcile` vs `handleHostDisconnect`).

---

## 4. The perfected architecture

### 4.1 Clock layer — skew, uncertainty, slew (spine: Bedrock; grafts: MAESTRO server timebase)

**Wire unchanged:** `clock:ping` → server ack. Server ack and *all* schedule stamps switch to a monotonic-anchored wall clock (MAESTRO graft), so a server OS NTP step can never bend the room's timeline:

```js
// app/server/index.js (boot)
const bootWall = Date.now(), bootMono = process.hrtime.bigint();
const serverNowMs = () => bootWall + Number(process.hrtime.bigint() - bootMono) / 1e6;
```

**Client estimator** is a pure shared reducer `clockCore` (JS reference + Dart port, conformance-vectored), replacing the internals of `useServerClock.js` and `server_clock.dart` behind their existing surfaces:

- **Monotonic timebase.** Samples use `performance.now()` (web) / `Stopwatch` (Dart). `Date.now()` is banished from clock math. Sample i: send at mono `m1`, receive at `m4`; `rtt_i = m4 − m1`; `off_i = serverTs − (m1 + m4)/2` (maps monotonic → server time; the arbitrary mono epoch is absorbed into the offset).
- **Window & outlier rejection.** ≤ 16 samples, expiring after 120 s. Drop any sample with `rtt > 3 × median(rtt)`. Estimation set = best `K = max(4, ceil(n/3))` by RTT — min-RTT bias without single-sample fragility.
- **Uncertainty-weighted offset.** `u_i = rtt_i / 2` (NTP one-way bound). `offset* = Σ(off_i/u_i²) / Σ(1/u_i²)`.
- **σ_clock** `= max( sqrt(1/Σ(1/u_i²)), stdev(off_i over set), |appliedOffset − offset*| ) + age·skewErr` — it grows while stale and while the slew is behind, so a stale or moving clock is self-distrusting.
- **Skew (Theil–Sen).** Median of pairwise slopes of `(m_i, off_i)` over the estimation set; requires ≥ 6 samples spanning ≥ 20 s, else `skew = 0`, `skewErr = 100 ppm`; fit residual sets `skewErr`. `serverNow(m) = m + appliedOffset + skew·(m − mAnchor)` — prediction stays accurate *between* samples, letting steady-state resampling relax to 20 s. (Chosen over SERVO's Kalman per the correctness judge: fewer tunables, robust statistics.)
- **Slew, never step.** `appliedOffset → offset*` at ≤ 5 ms per wall-second. If `|offset* − appliedOffset| > 250 ms` (server restart, route change): step once, **`clockEpoch++`**, set `σ_clock := |step|` decaying with 1 s half-life, and suppress the hard-seek band for 2 s. The controller treats a `clockEpoch` bump as a discontinuity (resets its drift filter), so an offset step can *never* read as drift. FM5's fake-drift hard seek is structurally impossible.
- **Readiness tiers** (replaces the one-sample boolean):
  - `unusable` (0 samples) — no corrections;
  - `coarse` (≥ 1) — paused holds and rendezvous only, generous margins;
  - `good` (≥ 4 accepted AND σ ≤ 60 ms) — nudging allowed;
  - `precise` (σ ≤ 25 ms, stable skew) — full tightness, future-`t0` barrier release.
  Hard corrections additionally require **≥ 4 samples AND σ ≤ 120 ms**.
- **Cadence:** burst 8 pings @ 250 ms on connect/reconnect/visibility-resume; 2 s while σ > 60 ms; 10 s at `good`; 20 s at `precise`; re-burst ×4 on RTT regime shift (median doubles or EWMA moves > 2σ).
- **Asymmetric-path bias** is priced into σ (stdev term + weighting), not pretended away.

**Output consumed everywhere:** `clock = {serverNowMs, sigmaMs, tier, epoch, rttMs, samples}`. `clockQuality()`-with-zero-call-sites dies; Flutter finally gets a quality surface.

### 4.2 The pure adaptive control loop (spine: Bedrock bands; grafts: SERVO PI + actuator, MAESTRO certainErr, RUNWAY caps)

Evaluation period stays `CONTROL_MS = 200 ms` on both adapters. All math below lives in the shared core (§5); positions are seconds internally, **ticks (1 s = 10,000,000) only at the wire boundary**. Sign convention: `drift > 0` = behind = `rate > 1`.

```
// ============ KEEL core: one tick ============  (T = 0.2 s)
step(state, in) -> {state', actions[], telemetry, health}

// ---- 0. Discontinuity fences ------------------------------------------------
if in.clock.epoch != state.lastClockEpoch:
    resetDriftFilter(state); state.lastClockEpoch = in.clock.epoch
if in.schedule.version != state.lastVersion:
    state.lastVersion = in.schedule.version
    if timelineJumped(in.schedule, state):        // position/phase/rate discontinuity
        resetDriftFilter(state)                   // a seek is not drift

// ---- 1. Guards (core-owned now) ---------------------------------------------
if in.flags.userSeekingUntilMs > in.nowServerMs: return idle       // scrub grace (3 s)
if in.flags.applying or state.mode == 'seeking': return continuePlan(state, in)

// ---- 2. Barrier / hold phases -------------------------------------------------
if in.schedule.phase == 'arming'
   or (in.schedule.phase == 'playing' and in.nowServerMs < in.schedule.t0):
    return armPath(state, in)      // prebuffer at target; emit barrier:ready when
                                   // runway >= readyRunway; action armStart{atServerMs: t0}
if in.schedule.phase != 'playing':                                  // paused / stalled hold
    D_hold = clamp(2*in.clock.sigmaMs/1000 + 0.05, 0.12, 0.40)      // 0.12 s on good clocks (FM12)
    return holdPath(state, in, D_hold)   // pause if playing; <=1 buffered paused-seek
                                         // per schedule version (bufferAwarePausedSeek)
if in.clock.tier == 'unusable': return idle

// ---- 3. Drift estimation: alpha-beta filter (SERVO) ---------------------------
exp   = predictPos(in.schedule, in.nowServerMs)   // P0 + schedule.rate*(now - t0)/1000
e     = exp - in.player.positionSec
pred  = state.d + state.dRate*T
nu    = e - pred
state.d     += 0.35 * nu                          // filtered drift
state.dRate += (0.06 / T) * nu                    // drift-rate: plant + residual clock skew
state.v      = 0.9*state.v + 0.1*nu*nu            // innovation variance
sigma_e = max(0.015, sqrt((0.7*in.clock.sigmaMs/1000)^2 + state.v))

// ---- 4. Deadband + MANDATORY hysteresis (kills FM2 structurally) --------------
D_enter = max(0.04, 2*sigma_e)                    // LAN sigma~3ms -> ~40ms (tighter than today)
D_exit  = D_enter / 2                             // cellular sigma~150ms -> ~300ms (stops noise-chasing)
if state.mode == 'follow' and |state.d| > D_enter: state.mode = 'nudge'
if state.mode == 'nudge'  and |state.d| < D_exit continuously for 1.5 s: state.mode = 'follow'

// ---- 5. Paused player under a playing schedule --------------------------------
if in.player.paused: return resumePlan(state, in)  // mini aim-ahead plan; requires
                                                   // runway >= min(R_resume, 2 s) before play
                                                   // (no more bare seekTo+play, FM7 sub-case)

// ---- 6. Rate-vs-seek: cost decision, not a cliff -------------------------------
Tseek = in.net.seekCostP90Sec                      // per-guest EWMA; priors 4.0 web-HLS / 0.75 libmpv
state.evidenceTicks = (|state.d| - 2*sigma_e > 0.35) ? state.evidenceTicks+1 : 0
wantSeek = |state.d| > 8.0                                          // forced
        or ( state.evidenceTicks >= 3                               // persistence: ~600ms of proof
             and |state.d| > max(0.5, 3*sigma_e)                    // magnitude floor
             and |state.d| / 0.10 > Tseek + 2.0 )                   // economics: nudging would take
                                                                    // >2 s longer than seeking
if wantSeek and in.nowServerMs > state.reseekBlockedUntilMs:
    return planRendezvous(state, in)                                // §4.3

// ---- 7. PI rate law on certainty-gated error (MAESTRO certainErr x SERVO PI) ---
e_c = (state.mode == 'nudge') ? sign(state.d) * max(0, |state.d| - D_exit) : 0
     // the controller literally cannot act on error it cannot distinguish from noise
state.integ = clamp(state.integ + 0.05 * e_c * T, -0.02, +0.02)     // Ki = 0.05/s
     // anti-windup: integrator frozen while output saturated or mode != 'nudge'
ff   = clamp(ewma30s(state.dRate), -0.01, +0.01)                    // skew feed-forward:
     // cancels 0.1-0.5% media-clock skew that leaves P-only loops in a sawtooth
conf = clamp(0.04 / sigma_e, 0.25, 1.0)
u    = 0.35*conf * e_c + state.integ + ff                           // Kp = 0.35*conf
band   = (|state.d| > 0.5) ? 0.10 : 0.04                            // catch-up vs steady authority
upCap  = band * clamp((runway - R_floor) / 4.0, 0, 1)               // RUNWAY graft: a thin-buffer
                                                                    // guest may NOT speed into
downCap= band                                                       // its own starvation; slowing
                                                                    // is always safe
targetRate = in.schedule.rate * (1 + clamp(u, -downCap, +upCap))
     // R_floor = max(1.5*segLen, 1.5 s); selfCatchUp lane raises band to 0.15

// ---- 8. Actuator shaping: flutter-proof by construction (SERVO + RUNWAY) -------
next = slewToward(state.appliedRate, targetRate, 0.01)              // <= 5%/s
if sign(next - 1) != sign(state.appliedRate - 1) and next != 1:
    dwell = (|state.d| > 2*D_enter) ? 4_000 : 10_000                // ms; S2 structural
    if in.nowServerMs < state.lastFlipAtMs + dwell: next = state.appliedRate
    else state.lastFlipAtMs = in.nowServerMs
next = quantize(next, 0.0025)                                       // 0.25% steps
if next != in.player.rate: actions += setRate{rate: next}           // redundant-write suppression
```

**Convergence character:** a 0.5 s error with a clean clock closes in ~5–6 s silently (vs 12.5 s/s-of-drift at today's saturated 0.08); the skew feed-forward removes the ±80 ms sawtooth a P-only loop leaves against real players; the certainty gate means a cellular guest at σ≈150 ms simply holds rate 1 instead of "correcting" clock noise. `HOST_DRAG_SEEK_SEC` and the hopping-host exemption dissolve into the host profile (§4.5).

### 4.3 Seeks: aim-ahead rendezvous plans (all four converged; feasibility gate from MAESTRO/RUNWAY)

Never seek to where the timeline *is* — seek to where it *will be* when you're ready, then let it arrive:

```
planRendezvous(state, in):
  rho = in.net.fillRate ?? prior(1.0)              // media-seconds fetched per wall-second
  if rho <= 1.05 and in.net.fillRateReliable:
      state.health = 'unsustainable'
      return { emit struggle }                     // downshift quality / selfCatchUp;
                                                   // a chase that cannot mathematically
                                                   // succeed is never attempted
  segLen = in.media.segLenSec ?? (webHls ? 4.0 : 2.0)
  R      = clamp(1.5*segLen + (1 - min(rho,1)) * 15, 2, 12)     // required runway (was fixed 4.0)
  prep   = in.net.seekCostP50Sec + R / rho                       // wall time the maneuver takes
  target = predictPos(in.schedule, in.nowServerMs + 1.15*prep*1000)
  state.plan = {targetSec: target, runwaySec: R, startedAtMs: now, replans: 0}
  state.mode = 'seeking'
  state.reseekBlockedUntilMs = now + max(20, 3*Tseek) * 1000
  actions: pause, seek{toSec: target, style: platform, runwaySec: R}
  // adapter executes: pause -> seek(target) -> ensureHlsLoad -> waitForBuffer(target, R)
  //   seekTimeout   = clamp(4 * seekCostP50, 3, 15) s          (was fixed 5 s)
  //   bufferTimeout = clamp(1.6 * R / max(rho, 0.1), 4, 20) s  (was fixed 8 s — no more
  //                                                            "give up and play into starvation")
  // then core action armStart: play exactly when predictPos(now) >= target - 0.05 s
  //   -> we land AHEAD; residual falls inside PI capture (<= 0.35 s); the rate loop closes it.
  // overrun: re-plan ONCE with fresh rho; second failure -> struggle + selfCatchUp lane.
```

Re-seek guard: no new seek for `max(20 s, 3·Tseek)` unless filtered drift grows monotonically for 2 s *and* exceeds the post-seek residual + 0.5 s. Combined with the plan state machine: **≤ 1 hard seek per disturbance (S3)**. `HARD_SEEK_COOLDOWN_MS = 2500` is deleted.

### 4.4 Stall & catch-up spectrum (spine: Bedrock health pipeline; grafts: SERVO pace + budgets, RUNWAY verified grants + lane)

The two product modes survive with today's names and semantics (invariant 11): **hopping** = the room never waits; **dragging** = the group protects stragglers — now gradually, with budgets. `gated()`'s binary freeze and `STALL_MAX_MS = 30_000` are deleted.

**Health classification is core output** (so Flutter participates by contract — FM6 dies):

```
health(state, in):                       // computed every tick, emitted on transition + 2 s heartbeat
  runway = in.player.bufferedAheadSec    // null => 'unknown': excused from pace triggers,
                                         //          stall only via explicit player.stalled
  R_ok   = max(2*segLen, 3.0)
  if in.player.stalled or runway < 0.5:
      RED, etaSec = (R - runway) / max(rho, 0.05)      // while stalled, fill = pure fetch rate
  elif runway < R_ok and rho < 1.0
       and runway / (rate - min(rho, rate)) < 10:      // predicted time-to-empty
      AMBER                                            // trouble BEFORE the freeze
  else GREEN
```

Wire: `sync:health {state, runwaySec, fillRate, etaSec, mediaGeneration}` (own rate bucket 10/3 s). Legacy `sync:stall` still accepted (`true → RED, eta null`).

**Server ladder** (replaces `reconcile()`'s gate; per-member state in the session):

- **Stage 0 — PACE (AMBER, or RED with eta ≤ 2.5 s).** Publish `schedule.rate = 0.97` for a bounded window `T_pace = min(deficit/0.03, 10 s)` — a 3% slowdown (inaudible; `preservesPitch` default on web, `audio-pitch-correction=yes` on mpv) lets the straggler's runway grow at `(rho − 0.97)` instead of `(rho − 1)`, usually preventing the stall entirely. **Capability-gated:** published only when every member advertises `caps ≥ sync2` (v1 cores ignore `schedule.rate` in extrapolation).
- **Stage 1 — HOLD with an informed grant (RED).** Freeze at `phase:'stalled'` as today, but the grant is `W = min(1.25 · etaSec, budget)` where **`budget = clamp(2 · EWMA(member's historical stall durations), 5, 20) s`**, seeded 10 s. The schedule carries `waitingOn: [{userId, etaSec, untilServerMs}]` — both UIs render "Waiting for Alice ~4 s". A bounded, explained wait is perceived as fine, not broken.
- **Progress-verified extension (RUNWAY).** At grant expiry: if `runwayNow ≥ runway0 + 0.6 · fillRate · W` (recovered at ≥ 60% of predicted pace) → grant ONE extension `min(1.25 · eta_new, budget − W)`; otherwise demote. Absolute per-episode ceiling **20 s shared across all concurrent stragglers** — no serial hostage rotation.
- **Stage 2 — self-catch-up lane** (generalizes `stallFallback`). Demoted member: excluded from grants and pace triggers; its core runs `selfCatchUp` (catch-up band 0.15, aim-ahead rendezvous against live, `unsustainable → downshift`); its future budget halves (repeat offender). **Every lane change is broadcast** — `sync:pace {selfCatchUp: [...], mediaGeneration, stateSeq}` on entry AND clear (fixes the silent `stallFallback` clear at index.js:531-534). Re-admission is hysteretic: 60 s of continuous GREEN.
- **Dead-member rule:** a member silent for ≥ 10 s, or lingering after disconnect, is excused immediately — a ghost can never gate the room, not even for 5 s.
- **Resume from any hold:** via a barrier release (§4.5) — the room restarts on the same frame instead of raggedly un-freezing.
- **Hopping (`w = 0`):** the ladder never gates anyone; stragglers self-manage (catch-up band → rendezvous → downshift → selfCatchUp). Host never waits — invariant intact.

The struggle detector moves into the core as health output (deleting `STRUGGLE_WINDOW_MS`/`STRUGGLE_HARD_SEEKS` from `useSyncPlay.js` — and Flutter gets it for free).

### 4.5 Membership, reconnect & coordinated barriers (spine: Bedrock; graft: MAESTRO fencing)

**Three reconnect layers** (FM1 is the single worst bug):

1. **Transport (optimization only):** `new Server(httpServer, {cors…, connectionStateRecovery: {maxDisconnectionDuration: 120_000, skipMiddlewares: true}, pingInterval: 5000, pingTimeout: 8000})` — sub-2-minute blips restore rooms and replay missed broadcasts; a dead socket is detected in ~13 s instead of ~45.
2. **Application attach (the guarantee):** one idempotent event emitted on **every** `'connect'` (first and reconnect):
   `session:attach {partyId, clientInstanceId, caps: ['sync2','barrier'], lastVersion, lastMediaGen, lastStateSeq}` → ack = full snapshot `{stateSeq, session, schedule, syncMode, selfCatchUp, mediaGeneration, hostId, controlEpoch, serverTs, you: {role, presence}, barrier?}`. Server-side it unifies today's `party:join` re-entry branches (index.js:272-297): refresh socketId, `socket.join`, **clear the host grace timer for a returning host**, reply. Safe to send twice. Web: `PartyContext` installs `socket.on('connect', attach)` with `partyId` persisted in `sessionStorage` (tab refresh recovers too). Flutter: `PartyNotifier` subscribes to `SocketClient.connectionState`; `IoSocketClient` enables socket.io auto-reconnection (it currently sets `forceNew` and never reconnects). `sync:hello` and pushed schedules stay for legacy (invariant 4).
3. **Guest linger:** disconnect no longer removes the member (index.js:569-582); `presence:'away'` for `GUEST_GRACE = 90 s`, stall/pace/barrier influence stripped *immediately*, `user:left` only after grace or explicit leave. A 3 s cellular blip becomes invisible. Kicked/approved re-entry rules unchanged (invariant 13).

**Ordering & fencing:**

- **`stateSeq`** — a per-session monotonic counter stamped on ALL membership/room broadcasts (`party:state`, `presence:changed`, `user:joined/left`, `host:changed`, `sync:pace`, `session:syncHealth`). Clients drop stale seq; a **gap triggers re-attach for a snapshot**. Membership now converges under the same drop-stale discipline the schedule already has.
- **`mediaGeneration` fence on commands:** `sync:play/pause/seek` carrying a stale generation are rejected with `{error:'stale generation', schedule, stateSeq}` — the sender converges in one RTT (today a stale client can seek the *new* movie's timeline).
- **`commandId` (UUID) + ack + one retry** (1.5 s timeout) on all sync commands from both clients — the server dedupe/CAS at session.js:151-177 finally goes live; retries are exactly-once. `baseVersion` CAS stays opt-in for collaborative UX.
- **FM10:** the timeline origin becomes a clock-agreed *future* instant via barriers (below); client press-time `t0` is kept on the wire but consumed only by a per-controller latency estimator (sizes barrier lead; telemetry).

**Coordinated PREBUFFER-THEN-RELEASE barriers** — every group discontinuity (play-from-pause, seek-while-playing, media change, stall recovery) is two-phase, and **barriers ARE schedules** (versioned, monotonic — any newer command supersedes a barrier through existing version discipline; zero new ordering primitives):

```
1) arm:     sync:schedule {positionTicks: target, t0: 0, rate: 0, paused: true,
                           phase: 'arming', version: v, mediaGeneration: g,
                           barrier: {id: 'g:v', targetTicks, deadlineTs, required: [presentMemberIds]}}
2) ready:   client -> barrier:ready {barrierId, mediaGeneration, runwaySec}     // idempotent Set semantics
            (clients prebuffer via the existing bufferAwarePausedSeek primitive)
3) release: on all-ready OR deadline:
            sync:schedule {positionTicks: target, t0: serverNow + lead, rate: 1,
                           paused: false, phase: 'playing', version: v+1}
            lead     = clamp(p95 room RTT/2 + 100 ms, 250, 1000) ms      // broadcast arrives BEFORE t0
            deadline = clamp(1.25 * max(required members' prepEta), 1.5, 8) s
```

Cores hold poised at the target during `arming` and start playback exactly at `t0` on their own aligned clocks (`armStart` action) — release spread ≈ clock σ (≤ 25 ms at `precise`), not one ragged RTT + decode spread. Paused-play barriers (everyone already holding the frame) release in < 400 ms. Stragglers past deadline are released into a personal rendezvous and flagged — the room never waits unbounded. Away members are auto-excused from `required`.

- **Scrub-while-paused** arms a *hold* barrier releasing into `phase:'paused'` — never starts the room (invariant 9).
- **Late join** never arms the room (host never waits): the joiner is flagged `joining` (its health is ignored by the ladder until its first plan completes — a cold buffer can't trigger a hold) and runs a **private aim-ahead rendezvous**: buffer paused at `predictPos(now + 1.15·prep)`, start when the timeline crosses it. First frame in sync, zero group disturbance (S8).
- **Legacy compat:** barrier semantics only when *all* members advertise `barrier`; otherwise the server double-broadcasts (same segment re-published with `phase:'playing'` at `t0`, `version+1`) — old cores already hold at `P0` for unknown phases, so degradation is graceful.

### 4.6 Host authority & failover (spine: Bedrock product rule; grafts: SERVO hostRegulate, MAESTRO controlEpoch)

**Ground truth is the server schedule, full stop.** The host is the default *controller*, never the timekeeper.

- **`hostRegulate` profile** (deletes the hopping-host exemption at syncCore.js:162): the host runs the same core with comfort deadbands — `D_enter_host = max(0.25, 3σ_e)`, rate-only corrections ±0.02, no hard seeks below 5 s of drift. Imperceptible in normal play, but the host's player is now glued to the timeline it authors, and it **reports health at 1 Hz like everyone** (today telemetry is guests-only). `kickHostPlay` survives as the adapter-level autoplay bootstrap (invariant 14). FM8a dies: the room can no longer sync to a timeline nobody is watching.
- **Host-stall gating (not reanchor):** if the host's own player stalls > 2 s in hopping, the server freezes the room at live position (`phase:'stalled', reason:'host'`); resume re-arms via barrier. (Bedrock's `sync:reanchor` was rejected: it converts one member's hiccup into everyone's correction; the UX judge preferred correcting the host.) Wedge detection: host health silent 5 s while connected → suspect banner; 10 s → treated as host stall.
- **Host loss — product rule preserved verbatim** (invariant 10): loss pauses the room; promotion after grace never auto-resumes. Hardened: **`HOST_SOFT_GRACE = 5 s`** — on host disconnect the room *keeps playing* for 5 s; since attach now auto-fires on reconnect, a 2 s host blip is a non-event instead of a guaranteed room-wide pause + phantom transfer. Only after 5 s → `freezeAt(sess)` (the **single** freeze primitive, collapsing FM13's duplicated truth) + paused schedule + `sync:host_gone`; promotion of the earliest-joined guest at the 30 s mark as today (`WP_HOST_GRACE_MS` override kept). MAESTRO's continue-without-host mode was rejected as a product-rule violation both correctness and cost judges penalized.
- **`controlEpoch` fencing (MAESTRO):** increments on every host change; stamped in every snapshot and `host:changed`. A stale ex-host command is rejected `{error:'stale-authority', controlEpoch, hostId}` with an authoritative update sent directly to the sender.
- **FM3 fixed at three layers:** (1) web role becomes *derived* — `isHost = session.hostId === userId` computed everywhere; the conditional `SET_ROLE` at PartyContext.jsx:131-137 is deleted (Flutter already correct); (2) server fencing above; (3) even a client with a stale host belief runs `hostRegulate` — it still *corrects*, so free-running divergence is impossible at every layer.

### 4.7 Observability — the feedback loop becomes load-bearing (FM9)

**Up:** `sync:report` v2 at 1 Hz from **all members including the host**, emitted as a core action so both platforms send identical truth (and Flutter stops reporting intent-rate fiction):

```
{v: 2, mediaGeneration, scheduleVersion, positionTicks, driftMs, driftVarMs2,
 appliedRate,            // the player's ACTUAL rate readout
 ctlState,               // follow|nudge|seeking|armed|hold|selfCatchUp|hostRegulate
 runwaySec, fillRate, clockSigmaMs, clockTier, rttMs, seekCostP90Ms,
 hardSeeks60s, rateFlips60s, stallMs60s}
```

**Server health ledger** (replaces write-only `sess.reports`), 60 s sliding window per session:
p50/p95/p99 |drift| **weighted by clock quality** (a report with σ = 200 ms can't claim 30 ms sync); inter-member spread (max − min against the same schedule — the honest "same frame?" number); rate flips/min; hard seeks/min; hold seconds by reason; barrier release spread (from one-shot `barrier:started` reports); clock-tier census.

**Consumers:** (1) `session:syncHealth {p95DriftMs, spreadMs, worstMember, waitingOn, tiers, stateSeq}` broadcast every 5 s → sync-health badge in both UIs; (2) **control inputs** — barrier lead/deadlines, pace triggers, per-member stall budgets, host-wedge detection; (3) `GET /debug/sessions/:id/sync` (extends the WP_TEST_MODE endpoints at index.js:189-208) + structured JSON logs. Server hints (`suggestedQualityDown`) stay advisory — the client core remains the decider; no server-pushed gain tuning (distributed-control oscillation risk).

**Never-silent guarantee (Bedrock, the product face):** a client flips to local `outOfSync` — visible badge + one-tap resync (personal rendezvous) — when σ_total > 350 ms, or p95 |drift| > 500 ms for > 10 s, or rendezvous re-plans are exhausted, or no schedule arrives within 5 s of a transport reconnect (which also auto re-attaches). Silent free-running is unrepresentable; S7 is the KPI.

### 4.8 Adaptive parameters — every constant gets a measured driver

Rule set: **(a) constants-as-floors** — behavior on a clean LAN never degrades below today's; tightening beyond today (40 ms deadband, 0.12 s hold) happens only where measurement supports it; **(b) null-degradation** — any missing measurement (Flutter buffered ranges, unknown segLen, fresh fillRate) degrades that one parameter to a conservative prior; adaptivity is strictly additive, never a precondition; **(c)** all derivations live in the pure core, EWMA-smoothed, clamped, vector-tested.

| Old constant | New derivation | Driver | Clamp |
|---|---|---|---|
| `SOFT_SEC` 0.08 / `SOFT_EXIT_SEC` 0.04 | `D_enter = max(0.04, 2σ_e)`, `D_exit = D_enter/2` + 1.5 s dwell | clock σ + drift innovation variance | 0.04–0.5 s |
| `RATE_GAIN` 0.12 | `Kp = 0.35·conf`, `conf = clamp(0.04/σ_e, 0.25, 1)`; `Ki = 0.05/s`, `I ≤ 0.02`; skew ff ≤ 0.01 | σ_e, dRate | — |
| `MAX_RATE_ADJ` 0.08 | 0.04 steady / 0.10 catch-up / 0.15 selfCatchUp; up-cap × runway scale | \|d\|, buffer runway | slew ≤ 1%/tick, quantize 0.25% |
| `HARD_SEEK_SEC` 1.0 | economics: `|d|/0.10 > seekCostP90 + 2 s` + evidence(3 ticks) + floor `max(0.5, 3σ_e)`; forced > 8 s | per-guest seek-cost EWMA/p90 | — |
| `HARD_SEEK_COOLDOWN_MS` 2500 | plan state machine + re-seek guard `max(20 s, 3·Tseek)` w/ growth test | measured seek cost | — |
| `BUFFER_AHEAD_SEC` 4.0 | `R = clamp(1.5·segLen + (1 − min(ρ,1))·15, 2, 12)` | hls.js `levelDetails.targetduration`; fillRate ρ | 2–12 s |
| `SEEK_TIMEOUT_MS` 5000 / `BUFFER_TIMEOUT_MS` 8000 | `clamp(4·seekCostP50, 3, 15)` / `clamp(1.6·R/max(ρ,0.1), 4, 20)` s | seek cost, ρ | — |
| `PAUSED_BUFFER_AHEAD_SEC` 2.0 | `min(R, 4)` s | R | — |
| `HOLD_TOLERANCE` 0.4 | `clamp(2σ_clock + 0.05, 0.12, 0.40)` s | clock σ | 0.12–0.4 s |
| `STALL_MAX_MS` 30 000 | per-member `budget = clamp(2·EWMA(stall history), 5, 20)` s + verified extension, episode ceiling 20 s | member stall history, reported eta | 5–20 s |
| `HOST_DRAG_SEEK_SEC` 2.0 | hostRegulate: `max(0.25, 3σ_e)` deadband, ±0.02, seeks ≥ 5 s | σ_e | — |
| clock resample 5 s | 250 ms burst → 2 s → 10 s → 20 s by tier; re-burst on regime shift | σ, RTT regime | — |
| `CONTROL_MS` 200 | **unchanged** (evaluation period only; actuation decoupled) | — | — |

Measured signals and where they come from: `σ_clock/tier` (clock core); `σ_e` (loop's own innovation variance); `seekCostP50/P90` (wall time seek→playable, last 8 seeks, reset per mediaGeneration; wall-clock only, so it works even with Flutter's poor buffer introspection); `fillRate ρ` (buffered media-seconds gained ÷ wall-seconds during loads — web from hls.js buffered deltas/`FRAG_BUFFERED`, Flutter from media_kit buffer deltas, with a reliability flag); `segLen` (hls.js `levelDetails.targetduration`; null on mpv → 2 s floor); room p95 RTT and prep etas (health ledger).

---

## 5. The shared web+Flutter pure-core contract

**One pure, deterministic, DOM/framework-free brain; two thin adapters — equivalence proven, not promised** (FM11).

**Files:** `app/client/src/sync/syncCore2.js` (JS reference) ≙ `flutter_app/lib/sync/sync_core2.dart`; `app/client/src/sync/clockCore.js` ≙ `flutter_app/lib/sync/clock_core.dart`; vectors in `app/shared/sync-vectors/*.jsonl`. `syncCore.js`/`sync_core.dart` remain as the kill-switch fallback until field p95s beat baseline.

```ts
// ---- signature (identical shape in Dart) ----
step(state: CtlState, input: TickInput) -> {state: CtlState, actions: Action[], telemetry, health}
clockUpdate(clock: ClockState, sample: {m1, m4, serverTs}) -> ClockState
deriveParams(signals) -> Params            // §4.8 derivations, pure
predictPos(schedule, serverNowMs) -> sec   // honors schedule.rate

TickInput = {
  nowServerMs, tickMs,
  schedule: {positionTicks, t0, rate, phase: 'playing'|'paused'|'stalled'|'arming',
             version, mediaGeneration, barrier?, waitingOn?},
  clock:    {sigmaMs, tier: 'unusable'|'coarse'|'good'|'precise', epoch, rttMs, samples},
  player:   {positionSec, paused, rate, seeking, stalled, bufferedAheadSec|null},
  media:    {segLenSec|null, durationSec|null},
  net:      {fillRate|null, fillRateReliable, seekCostP50Sec, seekCostP90Sec},
  role:     {isHost, canControl, mode: 'hopping'|'dragging'},
  flags:    {userSeekingUntilMs, applying, joining, selfCatchUp},
}

CtlState = {   // OPAQUE to adapters, JSON-serializable, MANDATORY round-trip
  mode: 'follow'|'nudge'|'seeking'|'armed'|'hold'|'selfCatchUp'|'hostRegulate',
  d, dRate, v, integ, appliedRate, lastFlipAtMs, evidenceTicks,
  plan: {targetSec, runwaySec, startedAtMs, replans}|null,
  reseekBlockedUntilMs, lastVersion, lastClockEpoch, lastHoldVersion,
  health: {state: 'green'|'amber'|'red'|'unknown', sinceMs},
}

Action =       // CLOSED vocabulary — the only side effects adapters may execute
  | setRate {rate}
  | seek    {toSec, style: 'buffered'|'bare'|'pausedBuffered', runwaySec, resumeAfter: 'armed'|'none'}
  | play | pause
  | armStart{atServerMs, targetSec}
  | emit    {event: 'sync:report'|'sync:health'|'barrier:ready'|'struggle', payload}
```

**Contract rules:**
1. **Mandatory state round-trip (RUNWAY):** adapters must feed back the exact returned state; hysteresis, the PI integrator, rate-slew memory, the plan, and the health classifier all live inside it. A conformance vector fails the moment an adapter drops state — the FM2 class ("implemented but never wired") is structurally impossible.
2. **Emit decisions live in the core** (SERVO/MAESTRO): stall/health reports, telemetry, barrier readiness, struggle are core outputs — a Flutter guest reports stalls because the core said so, not because someone remembered to port it (FM6 class closed).
3. **Purity:** zero `Date.now`, zero timers, zero platform types, no randomness; all time injected; platform differences (HLS vs mpv) enter only as *data* (`segLenSec: null`, seek styles, measured costs).
4. **Adapters are translators only** — they may NOT branch on drift, phase, or thresholds. Web `useSyncPlay` maps `seek{style:'buffered'}` onto the existing `bufferSeek.js` primitives (`waitForSeeked`/`waitForBuffer`/`ensureHlsLoad`/`selectBufferedResumeTarget`), now parameterized by `runwaySec` + adaptive timeouts, and keeps the refcounted applying-guard and `stillCurrent` identity checks verbatim (invariant 15). Flutter maps `seek` to `PlayerController.seek` (`style:'bare'`), gains one non-breaking surface member `bufferedAhead` (media_kit buffer / mpv `demuxer-cache-duration`; conservative fallback: ready = seeked + 1 s), and feeds measured seek wall time back. Autoplay-block muted retry (`kickHostPlay`) stays adapter-side by documented exception.
5. **Conformance vectors:** `app/shared/sync-vectors/*.jsonl`, one case per line `{name, module, state, input, expectState, expectActions, expectTelemetry}`, **generated from the JS reference** (`npm run gen-vectors`, regenerated in the same commit as any core change), replayed by vitest AND a table-driven `flutter test` runner; CI fails on any divergence. Numeric hygiene: ticks are integers on the wire (invariant 1), IEEE doubles internally, round-half-away-from-zero at tick boundaries, comparison at 1e-9.

---

## 6. Wire-protocol changes (all additive; backward-compat noted)

**Schedule (`sync:schedule`)** — existing fields unchanged; additive:
- `phase: 'arming'` (new value; old cores hold at `P0` for unknown phases — verified graceful),
- `rate` may be ≠ 0/1 (pace slew) — **published only to fully `sync2`-capable rooms**,
- `t0` may be in the future (barrier release; legacy rooms get the double-broadcast fallback),
- `barrier: {id, targetTicks, deadlineTs, required[]}`, `waitingOn: [{userId, etaSec, untilServerMs}]`, `holdReason`.
- `version` stays strictly monotonic per session; `mediaGeneration` semantics untouched (invariant 3).

**New events:**
- `session:attach` (c→s) + snapshot ack — idempotent membership; `sync:hello` and push-on-approve kept for legacy (invariant 4).
- `barrier:ready` (c→s), `barrier:started` (c→s, one-shot release-spread telemetry).
- `sync:health` (c→s) — GREEN/AMBER/RED heartbeat; legacy `sync:stall` still accepted and mapped.
- `sync:pace` (s→c) — selfCatchUp census, broadcast on every change.
- `session:syncHealth` (s→c, 5 s) — room aggregates for the badge.
- `presence:changed` (s→c) — away/linger transitions.

**Command envelope (`sync:play/pause/seek`)** — additive: `commandId` (UUID, retried once on ack timeout), `mediaGeneration` (fenced; mismatch → `{error:'stale generation', schedule, stateSeq}`), `baseVersion` (opt-in CAS, unchanged), `tPress` (client serverNow at press; consumed only by the latency estimator). Omission of all extras falls back to today's LWW (invariant 5).

**Rejections:** `{error:'stale-authority', controlEpoch, hostId}` for fenced ex-host commands; both rejections carry authoritative state so the sender self-corrects in one RTT.

**`sync:report` v2** — v-tagged; old shape still accepted from legacy clients.

**Capability negotiation:** `caps: ['sync2','barrier']` in attach/hello. Any room containing a legacy member runs legacy semantics for the gated features (no pace slew, double-broadcast instead of arming) — new fields are never sent where they would be misinterpreted. The active protocol level is shown in the health badge so rollout behavior isn't mysterious.

**Server config:** `connectionStateRecovery {maxDisconnectionDuration: 120_000, skipMiddlewares: true}`, `pingInterval: 5000`, `pingTimeout: 8000`.

---

## 7. The must-fix bugs, folded in

| Bug | Fix (mechanism → section) |
|---|---|
| **FM1** reconnect desync | `connectionStateRecovery` (optimization) + idempotent `session:attach` on every connect (web `PartyContext` connect handler + `sessionStorage`; Flutter `PartyNotifier` on `connectionState`, `IoSocketClient` reconnection enabled) + attach clears host grace timer + 90 s guest linger with influence stripped → §4.5. Shipped in Phase 0 with an interim `party:resume`. |
| **FM2** unwired hysteresis | Phase 0 stopgap: pass a persistent `correctionState` ref at useSyncPlay.js:330-340 and sync_engine_impl.dart:232-242 (core support exists). Structural fix: hysteresis is mandatory core state behind the mandatory round-trip; vectors fail if dropped → §4.2, §5. |
| **FM3** undemoted ex-host | Derived role (`isHost = session.hostId === userId`, delete conditional `SET_ROLE`) + `controlEpoch` server fencing with authoritative rejection + even a confused client runs `hostRegulate` (still corrects) → §4.6. |
| FM4/FM5 constants & dead clock quality | §4.1 (σ consumed), §4.8 (every constant derived + clamped). |
| FM6 stall cliff / silent Flutter | §4.4 ladder; health is core output; lane changes always broadcast. |
| FM7 chase loop | §4.3 aim-ahead plans + feasibility gate + adaptive timeouts + armed release. |
| FM8 host SPOF | §4.6 hostRegulate + host-stall gating + 5 s soft grace + wedge detection. |
| FM9 no feedback | §4.7 ledger + syncHealth + SLO harness. |
| FM10 dead command machinery / origin bias | §4.5 commandId retries + barrier-defined future origins. |
| FM11 hand-mirrored core | §5 vectors + mandatory round-trip + emits-in-core. |
| FM12 paused slack | `D_hold` → 0.12 s on good clocks (§4.2 step 2). |
| FM13 duplicated freeze truth | single `freezeAt(sess)` primitive (Phase 0). |

---

## 8. Phased migration plan

Six flag-guarded phases; each independently shippable, harness-green, and reversible. Wire rule throughout: additive fields only; gated features capability-negotiated. Telemetry lands **before** the controller so every later phase is measured against a baseline (cost judge's strongest recommendation).

**Phase 0 — verified bugs, zero wire semantics change (days).**
- `app/server/index.js`: `connectionStateRecovery` + ping tuning in the Server ctor (:66-68); `party:resume` handler beside `party:join` (:268) — idempotent re-attach, clears `hostDisconnectTimer`; guest linger in the disconnect handler (:569-582); `freezeAt(sess)` helper collapsing :663 vs :710 (FM13); `HOST_SOFT_GRACE = 5 s` keep-playing window in `handleHostDisconnect` (:698-730).
- `app/client/src/hooks/useSocket.js` + `app/client/src/context/PartyContext.jsx`: `socket.on('connect')` → re-emit resume + `sync:hello`; persist `partyId` in `sessionStorage`; derive `isHost` from `session.hostId` and delete the conditional `SET_ROLE` (:131-137) (FM3).
- `flutter_app/lib/net/socket_client.dart`: enable reconnection (drop `forceNew`); `flutter_app/lib/state/party_provider.dart`: subscribe `connectionState` → re-join; `flutter_app/lib/sync/sync_engine_impl.dart`: re-emit `sync:hello` on reconnect.
- FM2 stopgap: persistent `correctionState` at useSyncPlay.js:330-340 and sync_engine_impl.dart:232-242.
- Harness: new `reconnect.js` scenario (guest blip, host blip, no phantom transfer); update `advanced.js` hostMigration for the 5 s soft grace **deliberately** (per the comment at index.js:702-709).

**Phase 1 — clock v2 (~1 week).**
- `app/client/src/sync/clockCore.js` (pure: monotonic mapping, best-K weighted offset, Theil–Sen skew, slew, tiers, epochs) behind the existing `serverNow()/clockReady()` surfaces of `useServerClock.js`; port `flutter_app/lib/sync/clock_core.dart` driven by `server_clock.dart` (Flutter finally exposes quality).
- Server: `serverNowMs()` hrtime anchor for ping acks and all schedule stamps.
- Immediate relief patch: feed σ into the *existing* `decideSyncAction` as an optional deadband inflator `D = max(0.08, 2σ_total)` — most of FM4/FM5 relief before any core rewrite.
- First conformance vectors (clockCore: outliers, steps, skew, slew, epochs).

**Phase 2 — telemetry + ledger, BEFORE the controller (~1 week).**
- Both clients: `sync:report` v2 (v-tagged; host included; actual player rate).
- `app/server/index.js`: health ledger replacing `sess.reports` ingestion (:513-517), 60 s aggregation, `session:syncHealth` broadcast, `GET /debug/sessions/:id/sync` (extend :189-208).
- Harness: `syncSlo.js` scenario driving simulated guests through jitter/loss/slow-link profiles, asserting §2 aggregates. Baseline captured.

**Phase 3 — core v2 (~2–3 weeks).**
- `app/client/src/sync/syncCore2.js`: `step()` per §4.2/4.3 + `deriveParams` + health classifier + full vector suite in `app/shared/sync-vectors/`; `flutter_app/lib/sync/sync_core2.dart` port; CI conformance gate in both repos.
- Adapters become translators: `useSyncPlay.js` maps actions onto parameterized `bufferSeek.js` primitives (runwaySec + adaptive timeouts; applying-guard and `stillCurrent` kept verbatim); `sync_engine_impl.dart` executes actions, feeds `bufferedAhead` (new `PlayerController` member, non-breaking) and measured seek wall time.
- `SYNC_V2` flag per platform; `syncCore.js` v1 stays as kill switch until field p95 beats the Phase 2 baseline. Web rolls first; Flutter after vectors pass.
- Struggle detector and stall reporting move into the core (delete from `useSyncPlay.js`; Flutter joins dragging).

**Phase 4 — protocol hardening + barriers (~1–2 weeks).**
- `app/server/index.js` + `session.js`: `session:attach` + snapshot + `stateSeq` on all membership broadcasts; caps negotiation; `mediaGeneration` fence on commands; `controlEpoch` + stale-authority rejection; client SDKs send `commandId` (+ retry) and `tPress`.
- Barriers: `phase:'arming'` + `barrier:ready` + future-`t0` release wired into `sync:play`, playing `sync:seek`, `party:selectMedia`, and hold recovery — all writes still flow through `setSchedule` (:591-598, version monotonicity intact); legacy double-broadcast fallback; `predictPos` honors `schedule.rate` in both cores (capability-gated publish).
- Harness: `barrier.js` (kill sockets mid-arming, command during arming, duplicate ready), `clockstep.js`, mixed v1/v2 fleet scenario.

**Phase 5 — graduated stall ladder + host regulation (~1 week).**
- `app/server/index.js`: replace `gated()`/`STALL_MAX_MS` reconcile logic (:589, :638-640, :655-688) with the AMBER→PACE→HOLD(budget, verified extension)→selfCatchUp ladder; `sync:pace` broadcasts on entry AND clear; per-member budgets from the ledger.
- Core: `hostRegulate` profile replaces the host exemption; server host-stall gating + wedge detection.
- Delete dead constants (`SOFT_EXIT_SEC`, `HOLD_TOLERANCE`, `STALL_MAX_MS`, `BUFFER_AHEAD_SEC`, `HARD_SEEK_COOLDOWN_MS` as fixed values).
- Harness: `straggler.js` (assert pace → bounded hold → verified extension → lane, never a blind 30 s freeze; stall exactly at budget boundaries), lane-flapping soak.

**Invariants audit per phase:** ticks stay the wire unit; schedule stays a parametric segment; version monotonicity untouched; product rules 9–16 asserted by the harness, with the two deliberate behavior changes (5 s host soft grace; budgeted holds) updating `app/harness/scenarios/advanced.js` in the same commit as their phase.

---

## 9. Test plan

**Pure-core unit tests (conformance vectors, both runtimes):**
- clockCore: outlier storms, RTT regime shifts, offset steps → epoch + reset, skew estimation windows, slew backlog σ accounting, tier transitions.
- syncCore2: deadband/hysteresis sweeps at every band edge; dwell + slew + quantization traces; PI anti-windup (saturated output, mode exits); certainty-gated error at σ extremes; skew feed-forward convergence; evidence + economics seek gating; plan lifecycle (overrun → single re-plan → struggle; infeasible ρ → never chase); armed starts (early/late/duplicate release); hold paths (≤ 1 paused-seek per version, 0.12 s tolerance); health classification edges + heartbeat; selfCatchUp; hostRegulate; discontinuity resets (schedule jump, clock epoch).
- **Property tests (JS reference):** no action when |d| < D_exit; ≤ 1 rate-direction flip per 10 s on steady-noise traces; ≤ 1 seek per injected disturbance; state round-trip mandatory (dropping state fails the vector run).
- deriveParams: every clamp boundary; null-degradation rule (each missing signal degrades exactly one parameter to its prior).
- Existing `syncCore.test.js` / `session.test.js` keep passing until their phases retire them.

**Integration (app/harness/, VirtualPlayer):**
- `reconnect.js`: guest 3 s/30 s/95 s blips (resync ≤ 5 s; left only after linger); host 2 s blip (zero room impact); host 6 s (soft-grace freeze, no phantom transfer); reconnect storm (idempotent attach).
- `barrier.js`: chaos — member vanishes mid-arming, newer command supersedes, duplicate/late ready, deadline release, legacy-room double-broadcast; assert release spread p95 ≤ 120 ms (S4).
- `straggler.js`: one slow client — AMBER pace fires before freeze; hold ≤ budget; verified extension; demotion + broadcast; hysteretic re-admission; dead-client zero-wait; budget-boundary flapping soak.
- `clockstep.js`: server/client NTP steps → no spurious seek (S3), epoch reset observed.
- `latejoin.js`: cold joiner — zero group disturbance, first frame within D_enter (S8).
- `hostMigration` (updated): transfer → old host authoring rejected AND old host visibly converges; promotion never auto-resumes.
- `syncSlo.js`: soak across link profiles (LAN / 100 ms / 300 ms RTT + 100 ms jitter + 1% loss), asserting every §2 number via the debug endpoints, including S7 (inject a wedged player; assert badge within 10 s).
- Mixed-fleet scenario: one v1 client in the room → pace/barriers gated off, no misinterpretation.

---

## 10. Open questions

1. **libmpv buffer fidelity.** If `demuxer-cache-duration` proves unreliable per-container, Flutter runs health-unknown (excused from pace triggers, stall via explicit buffering events, barrier readiness = seeked + 1 s). Acceptable degradation, but quantify during Phase 3.
2. **Strict-dragging preset.** Do any rooms want unbounded "wait forever" semantics? If so, expose a room-level budget multiplier rather than resurrecting the 30 s cliff.
3. **Pace depth vs content.** 3% is inaudible for dialog; music-heavy content may warrant 2% or opt-out. Tune from Phase 2 fleet data before Phase 5 ships.
4. **Vector ossification.** Vectors are regenerated by script in the same commit as any JS core change and reviewed as a pair; do we additionally want a CI check that the generator output is clean against the committed vectors?
5. **Multi-node future.** All session state (ledger, budgets, barriers, linger) is single-node in-memory by design, matching today's posture; `connectionStateRecovery` and attach are per-node. Revisit only if the deployment story changes.
6. **Collaborative CAS UX.** `baseVersion` rejection surfaces as what — a toast ("someone just seeked"), or silent re-sync? Product call before Phase 4.
7. **`tPress` trust bounds.** We consume client press time only for latency estimation; if we ever honor it for pause-position beyond today's behavior, clamp to `[arrival − RTT, arrival]` (RUNWAY's rule) and gate on reported clock σ ≤ 100 ms.
