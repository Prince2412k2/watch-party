import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/models/party_state.dart';
import 'package:watchparty/sync/sync_core.dart';

// Ports app/client/src/sync/syncCore.test.js plus extra coverage of every
// branch of decideSyncAction, so the Dart core tracks the shared timeline
// identically to the browser guest.
void main() {
  // positionTicks 100_000_000 ticks = 10s; t0 = 1000ms.
  const playing = SyncSchedule(
      positionTicks: 100000000, t0: 1000, phase: 'playing', version: 7, paused: false, rate: 1);

  double at(double ms) => ms;

  group('predictPosition', () {
    test('advances at wall rate while playing', () {
      // P0 = 10s, elapsed (2000-1000)=1s → 11s.
      expect(predictPosition(playing, 2000), 11);
    });
    test('frozen at P0 while paused', () {
      const paused = SyncSchedule(positionTicks: 100000000, t0: 0, phase: 'paused');
      expect(predictPosition(paused, 999999), 10);
    });
    test('null schedule → 0', () => expect(predictPosition(null, 5), 0));
  });

  test('paused hopping guest with material drift requests buffer-aware catch-up', () {
    final intent = decideSyncAction(
      schedule: playing,
      serverNowMs: () => at(2000),
      clockReady: () => true,
      currentTime: 0,
      paused: true,
      isHost: false,
      mode: 'hopping',
      userSeeking: false,
    )!;
    expect(intent.hardSeek, true);
    expect(intent.seekToSec, 11);
    expect(intent.play, true);
  });

  test('hard-seek cooldown keeps a playing guest on bounded rate correction', () {
    final intent = decideSyncAction(
      schedule: playing,
      serverNowMs: () => at(2000),
      clockReady: () => true,
      currentTime: 8, // expected 11 → err 3s, would hard-seek but suppressed
      paused: false,
      isHost: false,
      mode: 'hopping',
      userSeeking: false,
      suppressHardSeek: true,
    )!;
    expect(intent.hardSeek, false);
    expect(intent.seekToSec, isNull);
    expect(intent.rate, closeTo(1.08, 1e-9)); // clamped to +MAX_RATE_ADJ
  });

  test('hopping host is exempt (native playback)', () {
    expect(
        decideSyncAction(
          schedule: playing,
          serverNowMs: () => at(2000),
          clockReady: () => true,
          currentTime: 0,
          paused: false,
          isHost: true,
          mode: 'hopping',
          userSeeking: false,
        ),
        isNull);
  });

  test('userSeeking suppresses correction', () {
    expect(
        decideSyncAction(
          schedule: playing,
          serverNowMs: () => at(2000),
          clockReady: () => true,
          currentTime: 0,
          paused: false,
          isHost: false,
          mode: 'hopping',
          userSeeking: true,
        ),
        isNull);
  });

  test('paused/stalled schedule holds everyone at the frozen frame', () {
    const paused = SyncSchedule(positionTicks: 100000000, t0: 0, phase: 'paused');
    final intent = decideSyncAction(
      schedule: paused,
      serverNowMs: () => at(9999),
      clockReady: () => true,
      currentTime: 50, // far from P0 (10s) → pausedSeek
      paused: false,
      isHost: false,
      mode: 'hopping',
      userSeeking: false,
    )!;
    expect(intent.pause, true);
    expect(intent.pausedSeek, true);
    expect(intent.seekToSec, 10);
  });

  test('small drift within SOFT_SEC → no nudge, rate 1', () {
    final intent = decideSyncAction(
      schedule: playing,
      serverNowMs: () => at(2000),
      clockReady: () => true,
      currentTime: 11.05, // err 0.05 < SOFT_SEC 0.08
      paused: false,
      isHost: false,
      mode: 'hopping',
      userSeeking: false,
    )!;
    expect(intent.rate, 1);
    expect(intent.seekToSec, isNull);
  });

  test('gross drift beyond HARD_SEEK_SEC → hard seek', () {
    final intent = decideSyncAction(
      schedule: playing,
      serverNowMs: () => at(2000),
      clockReady: () => true,
      currentTime: 5, // expected 11, err 6s
      paused: false,
      isHost: false,
      mode: 'hopping',
      userSeeking: false,
    )!;
    expect(intent.hardSeek, true);
    expect(intent.seekToSec, 11);
  });

  test('dragging host corrects only gross drift, never nudges', () {
    final small = decideSyncAction(
      schedule: playing,
      serverNowMs: () => at(2000),
      clockReady: () => true,
      currentTime: 10.5, // err 0.5 (> SOFT but < HOST_DRAG 2.0)
      paused: false,
      isHost: true,
      mode: 'dragging',
      userSeeking: false,
    )!;
    expect(small.seekToSec, isNull);
    expect(small.rate, 1);

    final gross = decideSyncAction(
      schedule: playing,
      serverNowMs: () => at(2000),
      clockReady: () => true,
      currentTime: 5, // err 6 > 2.0
      paused: false,
      isHost: true,
      mode: 'dragging',
      userSeeking: false,
    )!;
    expect(gross.seekToSec, 11);
  });

  test('clock not ready → no correction while playing', () {
    expect(
        decideSyncAction(
          schedule: playing,
          serverNowMs: () => at(2000),
          clockReady: () => false,
          currentTime: 0,
          paused: false,
          isHost: false,
          mode: 'hopping',
          userSeeking: false,
        ),
        isNull);
  });
}
