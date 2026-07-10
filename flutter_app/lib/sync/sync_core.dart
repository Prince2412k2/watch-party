// UI-free playback-sync decision core.
//
// Direct port of the web app's `app/client/src/sync/syncCore.js` — the pure
// math extracted from the `useSyncPlay` control loop. It knows nothing about
// media_kit or Flutter: given the current schedule, clock, and player state it
// returns a [SyncIntent] describing what the caller should do to the player.
// The web hook and this engine drive the identical decision function, so a
// Flutter guest tracks the shared timeline identically to a browser guest.

import '../models/party_state.dart';

/// Jellyfin ticks per second (1 tick = 100ns).
const int ticksPerSecond = 10000000;

// ── Correction-loop tuning (verbatim from syncCore.js) ──────────────────────
/// How often the correction loop re-evaluates drift.
const int controlMs = 200;

/// Guest drift beyond this (seconds) → jump to live (hard seek) instead of nudge.
const double hardSeekSec = 1.0;

/// A dragging host only corrects gross drift, not routine jitter.
const double hostDragSeekSec = 2.0;

/// Drift beyond this (seconds) → speed nudge begins (enter threshold).
const double softSec = 0.08;

/// Exit threshold for the soft nudge (hysteresis, lower than [softSec]).
const double softExitSec = 0.04;

/// How much of the current error is corrected per tick.
const double rateGain = 0.12;

/// How far playbackRate may move from 1.0 while nudging (0.92x–1.08x).
const double maxRateAdj = 0.08;

/// Slack (seconds) around the frozen position while paused before re-seeking.
const double holdTolerance = 0.4;

/// Debounce after a hard seek: suppress re-triggering for this long so the
/// catch-up (real wall time) isn't re-entered mid-flight from stale drift.
const int hardSeekCooldownMs = 2500;

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// Predicted shared-timeline position (seconds) at [serverNowMs]. Pure.
/// While playing, position advances from P0 at wall-rate since t0; otherwise
/// the timeline is frozen at P0. Mirrors `predictPosition` in syncCore.js.
double predictPosition(SyncSchedule? s, double serverNowMs) {
  if (s == null) return 0;
  final p0 = s.positionTicks / ticksPerSecond;
  if (s.phase != 'playing') return p0;
  return p0 + (serverNowMs - s.t0) / 1000.0;
}

/// The action the control loop wants applied to the player for one tick.
/// Mirrors the plain-object intent returned by `decideSyncAction` in the web
/// core. A `null` return (see [decideSyncAction]) means "no-op this tick".
class SyncIntent {
  const SyncIntent({
    this.seekToSec,
    this.rate,
    this.play = false,
    this.pause = false,
    this.hardSeek = false,
    this.pausedSeek = false,
    this.drift,
  });

  /// Seconds to seek the player to (a hard correction), or null.
  final double? seekToSec;

  /// playbackRate to set, or null.
  final double? rate;

  /// Call play().
  final bool play;

  /// Call pause().
  final bool pause;

  /// The seek is a "lost sync" jump (guest hopping) — caller routes it through
  /// the buffer-aware catch-up path and records it for struggle detection.
  final bool hardSeek;

  /// The seek positions a paused guest onto the frozen frame (never resumes).
  final bool pausedSeek;

  /// expected - currentTime (seconds), for telemetry. May be null.
  final double? drift;
}

/// Caller-owned hysteresis state for the soft-correction band. Mirrors the
/// optional `correctionState` object in syncCore.js. The web `useSyncPlay`
/// hook does NOT pass one (single-threshold behavior); provided here for
/// fidelity and headless callers that want the flutter-free nudge band.
class CorrectionState {
  bool correcting = false;
}

/// Decide the sync action for one control tick. Pure — no side effects.
///
/// Faithful port of `decideSyncAction` (syncCore.js). Returns null when the
/// tick is a no-op.
///
/// - [serverNowMs] / [clockReady] are callbacks (server-aligned now in ms; is
///   the NTP-lite clock trustworthy) — kept as functions to match the web core
///   so the clock is read lazily, exactly when needed.
/// - [currentTime] / [paused] are the player's live snapshots (seconds / bool).
SyncIntent? decideSyncAction({
  required SyncSchedule? schedule,
  required double Function() serverNowMs,
  required bool Function() clockReady,
  required double currentTime,
  required bool paused,
  required bool isHost,
  required String mode,
  required bool userSeeking,
  bool suppressHardSeek = false,
  CorrectionState? correctionState,
}) {
  final s = schedule;
  if (s == null) return null;
  // A hopping host plays natively and never runs the correction loop.
  if (isHost && mode != 'dragging') return null;
  if (userSeeking) return null;

  final p0 = s.positionTicks / ticksPerSecond;

  // paused OR stalled → everyone holds at the frozen position.
  if (s.phase != 'playing') {
    final wantPause = !paused;
    double? seekTo;
    var pausedSeek = false;
    if ((currentTime - p0).abs() > holdTolerance) {
      seekTo = p0;
      pausedSeek = true;
    }
    return SyncIntent(
        rate: 1, pause: wantPause, seekToSec: seekTo, pausedSeek: pausedSeek);
  }

  if (!clockReady()) return null;
  final expected = predictPosition(s, serverNowMs());
  if (expected < 0) return null;

  if (paused) {
    final drift = expected - currentTime;
    final hard = !isHost && mode == 'hopping' && drift.abs() > hardSeekSec;
    return SyncIntent(
        seekToSec: expected, rate: 1, play: true, drift: drift, hardSeek: hard);
  }

  final err = expected - currentTime;
  final ae = err.abs();

  if (isHost) {
    // dragging host: obey the timeline, correct only gross drift, no nudge.
    return SyncIntent(
        rate: 1, drift: err, seekToSec: ae > hostDragSeekSec ? expected : null);
  }

  if (ae > hardSeekSec && !suppressHardSeek) {
    correctionState?.correcting = false;
    return SyncIntent(seekToSec: expected, rate: 1, hardSeek: true, drift: err);
  }

  // Hysteresis around the soft band: once nudging, keep nudging until drift
  // falls under the lower [softExitSec] bound. With no [correctionState] the
  // threshold is always [softSec] — identical to the web hook (which passes none).
  final wasCorrecting = correctionState?.correcting ?? false;
  final softThreshold = wasCorrecting ? softExitSec : softSec;
  final shouldCorrect = ae > softThreshold;
  correctionState?.correcting = shouldCorrect;

  if (shouldCorrect) {
    return SyncIntent(
      rate: 1 + _clamp(err * rateGain, -maxRateAdj, maxRateAdj),
      drift: err,
    );
  }
  return SyncIntent(rate: 1, drift: err);
}
