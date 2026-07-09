import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/player_controller.dart';
import 'package:watchparty/sync/server_clock.dart';
import 'package:watchparty/sync/sync_engine_impl.dart';

/// Deterministic, fully-driven [PlayerController] fake: no internal timer, all
/// state is set explicitly, and every mutation is recorded for assertions.
class FakePlayer implements PlayerController {
  Duration pos = Duration.zero;
  bool playingNow = false;
  double rate = 1.0;

  final _playingCtrl = StreamController<bool>.broadcast();
  final calls = <String>[];

  @override
  Future<void> play() async {
    calls.add('play');
    if (!playingNow) {
      playingNow = true;
      _playingCtrl.add(true);
    }
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    if (playingNow) {
      playingNow = false;
      _playingCtrl.add(false);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    pos = position;
  }

  @override
  Future<void> setRate(double r) async {
    rate = r;
  }

  // Simulate a user/UI-driven transition that must author sync commands.
  void userSetPlaying(bool v) {
    playingNow = v;
    _playingCtrl.add(v);
  }

  @override
  Stream<bool> get playing => _playingCtrl.stream;
  @override
  Duration get positionNow => pos;
  @override
  bool get isPlayingNow => playingNow;
  @override
  Duration get durationNow => const Duration(minutes: 90);
  @override
  bool get isBufferingNow => false;

  @override
  Future<void> open(String url,
      {Duration startAt = Duration.zero, bool autoplay = false}) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setAudioTrack(String? trackId) async {}
  @override
  Future<void> setSubtitle(String? trackId) async {}
  @override
  Future<void> dispose() async => _playingCtrl.close();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<PlayerTracks> get tracks => const Stream.empty();
}

Map<String, dynamic> playingSchedule({int posTicks = 100000000, int t0 = 1000, int version = 1}) =>
    {
      'positionTicks': posTicks,
      't0': t0,
      'rate': 1,
      'paused': false,
      'phase': 'playing',
      'version': version,
      'mediaGeneration': 0,
    };

Map<String, dynamic> pausedSchedule({int posTicks = 100000000, int version = 1, int gen = 0}) =>
    {
      'positionTicks': posTicks,
      't0': 0,
      'rate': 0,
      'paused': true,
      'phase': 'paused',
      'version': version,
      'mediaGeneration': gen,
    };

/// Build an engine with a manual clock whose server-now is [nowMs].
SyncEngineImpl engineWith(double Function() nowMs) => SyncEngineImpl(
    clock: ManualServerClock(nowMs: nowMs, ready: true));

void main() {
  test('guest is driven onto the shared timeline (seek + play)', () {
    fakeAsync((fa) {
      var serverNow = 2000.0; // 1s after t0 → expected 11s
      final engine = engineWith(() => serverNow);
      final player = FakePlayer();
      final socket = MockSocketClient();

      engine.attach(player: player, socket: socket, partyId: 'p', canControl: false);
      fa.flushMicrotasks();

      // sync:hello was emitted on attach.
      expect(socket.emitted.any((e) => e.$1 == ClientEvent.syncHello), isTrue);

      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      fa.elapse(const Duration(milliseconds: 250)); // ≥1 control tick

      // Guest was paused at 0 → hard-seek to expected (~11s) and play.
      expect(player.calls.any((c) => c.startsWith('seek:')), isTrue);
      expect(player.calls, contains('play'));
      expect(player.playingNow, isTrue);
      // Landed near 11s (hard seek then re-read to live; within a tick's slop).
      expect(player.pos.inSeconds, inInclusiveRange(10, 12));

      engine.detach();
    });
  });

  test('applying-guard prevents the engine echoing its own applied change', () {
    fakeAsync((fa) {
      var serverNow = 2000.0;
      final engine = engineWith(() => serverNow)..isHost = false;
      final player = FakePlayer();
      final socket = MockSocketClient();
      // canControl TRUE (collaborative guest): its own gestures author, so the
      // guard must stop the loop-applied play() from being re-emitted.
      engine.attach(player: player, socket: socket, partyId: 'p', canControl: true);
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      final beforePlays = socket.emitted.where((e) => e.$1 == ClientEvent.syncPlay).length;

      fa.elapse(const Duration(milliseconds: 250)); // loop applies play()
      fa.flushMicrotasks(); // deliver the player's playing-stream event

      expect(player.playingNow, isTrue);
      final afterPlays = socket.emitted.where((e) => e.$1 == ClientEvent.syncPlay).length;
      // The applied play() did NOT round-trip back out as a sync:play command.
      expect(afterPlays, beforePlays);

      engine.detach();
    });
  });

  test('no-control guest cannot drive playback (gestures never author)', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0);
      final player = FakePlayer();
      final socket = MockSocketClient();
      engine.attach(player: player, socket: socket, partyId: 'p', canControl: false);
      fa.flushMicrotasks();

      // Explicit intents are dropped.
      engine.requestPlay();
      engine.requestPause();
      engine.requestSeek(const Duration(seconds: 30));

      // And a local UI-driven play transition is not authored either.
      player.userSetPlaying(true);
      fa.flushMicrotasks();

      expect(socket.emitted.any((e) => e.$1 == ClientEvent.syncPlay), isFalse);
      expect(socket.emitted.any((e) => e.$1 == ClientEvent.syncPause), isFalse);
      expect(socket.emitted.any((e) => e.$1 == ClientEvent.syncSeek), isFalse);

      engine.detach();
    });
  });

  test('a controller authors play/pause/seek to the server', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 5000.0)..isHost = true;
      final player = FakePlayer()..pos = const Duration(seconds: 42);
      final socket = MockSocketClient();
      engine.attach(player: player, socket: socket, partyId: 'p', canControl: true);
      fa.flushMicrotasks();

      engine.requestSeek(const Duration(seconds: 30));
      engine.requestPause();

      final seek = socket.emitted.firstWhere((e) => e.$1 == ClientEvent.syncSeek);
      expect((seek.$2 as Map)['positionTicks'], 30 * 1000 * ticksPerMs);
      final pause = socket.emitted.firstWhere((e) => e.$1 == ClientEvent.syncPause);
      expect((pause.$2 as Map)['positionTicks'], 42 * 1000 * ticksPerMs);

      // A UI-driven play transition authors sync:play at the player position.
      player.userSetPlaying(true);
      fa.flushMicrotasks();
      expect(socket.emitted.any((e) => e.$1 == ClientEvent.syncPlay), isTrue);

      engine.detach();
    });
  });

  test('stale / out-of-order schedules are dropped by version gating', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0);
      final player = FakePlayer();
      final socket = MockSocketClient();
      final seen = <int>[];
      engine.scheduleStream.listen((s) => seen.add(s.version));
      engine.attach(player: player, socket: socket, partyId: 'p', canControl: false);
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncSchedule, playingSchedule(version: 5));
      socket.inject(ServerEvent.syncSchedule, playingSchedule(version: 3)); // stale
      socket.inject(ServerEvent.syncSchedule, playingSchedule(version: 5)); // dup
      socket.inject(ServerEvent.syncSchedule, playingSchedule(version: 6)); // ok
      fa.flushMicrotasks();

      expect(seen, [5, 6]);
      expect(engine.currentSchedule.version, 6);

      engine.detach();
    });
  });

  test('media-generation change resets the version baseline', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0);
      final player = FakePlayer();
      final socket = MockSocketClient();
      final seen = <int>[];
      engine.scheduleStream.listen((s) => seen.add(s.version));
      engine.attach(player: player, socket: socket, partyId: 'p', canControl: false);
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 9, gen: 0));
      // New media: version restarts lower but a new generation resets baseline.
      socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 1, gen: 1));
      fa.flushMicrotasks();

      expect(seen, [9, 1]);
      engine.detach();
    });
  });

  test('sync:host_gone pauses local playback', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0)..isHost = false;
      final player = FakePlayer()..playingNow = true;
      final socket = MockSocketClient();
      engine.attach(player: player, socket: socket, partyId: 'p', canControl: false);
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncHostGone, null);
      expect(player.calls, contains('pause'));
      expect(player.playingNow, isFalse);

      engine.detach();
    });
  });

  test('hopping host is not corrected but is kicked into play', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0)..isHost = true;
      final player = FakePlayer(); // paused
      final socket = MockSocketClient();
      engine.attach(player: player, socket: socket, partyId: 'p', canControl: true);
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      // kickHostPlay runs on the schedule handler (host, hopping, phase playing).
      expect(player.playingNow, isTrue);

      // The correction loop must NOT seek the host around (native playback).
      player.calls.clear();
      fa.elapse(const Duration(milliseconds: 400));
      fa.flushMicrotasks();
      expect(player.calls.any((c) => c.startsWith('seek:')), isFalse);

      engine.detach();
    });
  });
}
