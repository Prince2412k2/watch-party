import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/player_controller.dart';
import 'package:watchparty/sync/server_clock.dart';
import 'package:watchparty/sync/sync_engine_impl.dart';
import 'package:watchparty/sync/sync_engine.dart';

/// Deterministic, fully-driven [PlayerController] fake: no internal timer, all
/// state is set explicitly, and every mutation is recorded for assertions.
class FakePlayer implements PlayerController {
  Duration pos = Duration.zero;
  bool playingNow = false;
  bool bufferingNow = false;
  double rate = 1.0;
  Completer<void>? playGate;
  Completer<void>? seekGate;

  final _playingCtrl = StreamController<bool>.broadcast();
  final _bufferingCtrl = StreamController<bool>.broadcast();
  final calls = <String>[];

  @override
  Future<void> play() async {
    calls.add('play');
    final gate = playGate;
    if (gate != null) await gate.future;
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
    final gate = seekGate;
    if (gate != null) await gate.future;
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

  void setBuffering(bool value) {
    bufferingNow = value;
    _bufferingCtrl.add(value);
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
  bool get isBufferingNow => bufferingNow;

  @override
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    bool autoplay = false,
  }) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setAudioTrack(String? trackId) async {}
  @override
  Future<void> setSubtitle(String? trackId) async {}
  @override
  Future<void> dispose() async {
    await _playingCtrl.close();
    await _bufferingCtrl.close();
  }

  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get buffering => _bufferingCtrl.stream;
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<PlayerTracks> get tracks => const Stream.empty();
}

class DelayedAckSocket extends MockSocketClient {
  final acks = <Completer<dynamic>>[];

  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) {
    emitted.add((event, data));
    final ack = Completer<dynamic>();
    acks.add(ack);
    return ack.future;
  }
}

Map<String, dynamic> playingSchedule({
  int posTicks = 100000000,
  int t0 = 1000,
  int version = 1,
}) => {
  'positionTicks': posTicks,
  't0': t0,
  'rate': 1,
  'paused': false,
  'phase': 'playing',
  'version': version,
  'mediaGeneration': 0,
};

Map<String, dynamic> pausedSchedule({
  int posTicks = 100000000,
  int version = 1,
  int gen = 0,
}) => {
  'positionTicks': posTicks,
  't0': 0,
  'rate': 0,
  'paused': true,
  'phase': 'paused',
  'version': version,
  'mediaGeneration': gen,
};

/// Build an engine with a manual clock whose server-now is [nowMs].
SyncEngineImpl engineWith(double Function() nowMs) =>
    SyncEngineImpl(clock: ManualServerClock(nowMs: nowMs, ready: true));

void main() {
  test('CatchUp refreshes capped-rate drift and clears on paused seek', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000);
      final player = FakePlayer()
        ..playingNow = true
        ..pos = const Duration(seconds: 10);
      final socket = MockSocketClient();
      final seen = <CatchUp>[];
      engine.catchUp.listen(seen.add);
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      fa.elapse(const Duration(milliseconds: 250));
      expect(seen.last.rate, 1.1);
      expect(seen.last.drift, const Duration(seconds: 1));
      player.pos = const Duration(milliseconds: 9500);
      fa.elapse(const Duration(milliseconds: 200));
      expect(seen.last.rate, 1.1);
      expect(seen.last.drift, const Duration(milliseconds: 1500));
      socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 2));
      fa.elapse(const Duration(milliseconds: 600));
      expect(player.rate, 1);
      expect(seen.last.active, isFalse);
      engine.dispose();
      fa.flushMicrotasks();
    });
  });

  for (final mode in ['dragging', 'hopping']) {
    test(
      '$mode delayed host play yields to newer authority without authoring',
      () {
        fakeAsync((fa) {
          final engine = engineWith(() => 2000)
            ..syncMode = mode
            ..isHost = true;
          final player = FakePlayer()..playGate = Completer<void>();
          final socket = MockSocketClient();
          engine.attach(
            player: player,
            socket: socket,
            partyId: 'p',
            canControl: true,
          );
          fa.flushMicrotasks();
          socket.inject(ServerEvent.syncSchedule, pausedSchedule());
          engine.requestPlay();
          fa.flushMicrotasks();
          socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 2));
          fa.elapse(const Duration(seconds: 1));
          player.playGate!.complete();
          fa.flushMicrotasks();
          fa.elapse(const Duration(milliseconds: 500));
          expect(player.playingNow, isFalse);
          expect(
            socket.emitted.where((e) => e.$1 == ClientEvent.syncPlay),
            isEmpty,
          );
          engine.dispose();
          fa.flushMicrotasks();
        });
      },
    );

    test('$mode delayed seek is serialized and newer pause prevents play', () {
      fakeAsync((fa) {
        final engine = engineWith(() => 2000)..syncMode = mode;
        final player = FakePlayer()..seekGate = Completer<void>();
        final socket = MockSocketClient();
        engine.attach(
          player: player,
          socket: socket,
          partyId: 'p',
          canControl: true,
        );
        fa.flushMicrotasks();
        socket.inject(ServerEvent.syncSchedule, playingSchedule());
        fa.elapse(const Duration(seconds: 4));
        expect(player.calls.where((c) => c.startsWith('seek:')), hasLength(1));
        expect(player.calls, isNot(contains('play')));
        socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 2));
        player.seekGate!.complete();
        fa.flushMicrotasks();
        fa.elapse(const Duration(milliseconds: 500));
        expect(player.playingNow, isFalse);
        expect(player.rate, 1);
        expect(
          socket.emitted.where((e) => e.$1 == ClientEvent.syncPlay),
          isEmpty,
        );
        engine.dispose();
        fa.flushMicrotasks();
      });
    });
  }

  test('authored seek queues behind correction and wins without echo', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000);
      final player = FakePlayer()..seekGate = Completer<void>();
      final socket = MockSocketClient();
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: true,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      fa.elapse(const Duration(milliseconds: 250));
      engine.seekTo(const Duration(seconds: 42));
      fa.elapse(const Duration(seconds: 3));
      expect(player.calls.where((c) => c.startsWith('seek:')), hasLength(1));
      player.seekGate!.complete();
      fa.flushMicrotasks();
      expect(player.pos, const Duration(seconds: 42));
      expect(player.calls, isNot(contains('play')));
      final seeks = socket.emitted.where((e) => e.$1 == ClientEvent.syncSeek);
      expect(seeks, hasLength(1));
      expect((seeks.single.$2 as Map)['positionTicks'], 420000000);
      engine.dispose();
      fa.flushMicrotasks();
    });
  });

  test(
    'open drains correction and suppresses delayed native authoring',
    () async {
      final engine = engineWith(() => 2000);
      final player = FakePlayer()..seekGate = Completer<void>();
      final socket = MockSocketClient();
      await engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: true,
      );
      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      await Future<void>.delayed(const Duration(milliseconds: 250));
      var drained = false;
      final opening = engine.beginOpen().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      player.seekGate!.complete();
      await opening;
      player.userSetPlaying(true);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      player.userSetPlaying(false);
      await Future<void>.delayed(Duration.zero);
      expect(
        socket.emitted.where((e) => e.$1 == ClientEvent.syncPause),
        isEmpty,
      );
      expect(player.calls, isNot(contains('play')));
      engine.endOpen();
      player.rate = 1.1;
      await engine.detach();
      expect(player.rate, 1);
      await engine.dispose();
      await player.dispose();
    },
  );

  test('detach drains delayed seek before reusing the player', () async {
    final engine = engineWith(() => 2000);
    final player = FakePlayer()..seekGate = Completer<void>();
    final socket = MockSocketClient();
    await engine.attach(
      player: player,
      socket: socket,
      partyId: 'p',
      canControl: false,
    );
    socket.inject(ServerEvent.syncSchedule, playingSchedule());
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final detached = engine.detach();
    player.seekGate!.complete();
    await detached;
    expect(player.calls, isNot(contains('play')));
    expect(player.rate, 1);
    await engine.dispose();
    await player.dispose();
  });

  test('dragging is the default sync mode', () {
    expect(engineWith(() => 0).syncMode, 'dragging');
  });

  test('guest is driven onto the shared timeline (seek + play)', () {
    fakeAsync((fa) {
      var serverNow = 2000.0; // 1s after t0 → expected 11s
      final engine = engineWith(() => serverNow);
      final player = FakePlayer();
      final socket = MockSocketClient();

      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
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

  test('buffering guest is not chased forward, then recovers without jump', () {
    fakeAsync((fa) {
      var serverNow = 2000.0;
      final engine = engineWith(() => serverNow)..syncMode = 'hopping';
      final player = FakePlayer()
        ..playingNow = true
        ..pos = const Duration(seconds: 1)
        ..bufferingNow = true;
      final socket = MockSocketClient();
      final seen = <CatchUp>[];
      engine.catchUp.listen(seen.add);

      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, playingSchedule());

      fa.elapse(const Duration(minutes: 2));
      expect(player.calls.where((c) => c.startsWith('seek:')), isEmpty);
      expect(player.playingNow, isTrue);
      expect(seen.last.waiting, isTrue);

      player.setBuffering(false);
      fa.flushMicrotasks();
      fa.elapse(const Duration(milliseconds: 250));

      expect(player.calls.where((c) => c.startsWith('seek:')), isEmpty);
      expect(player.rate, 1.1);
      expect(seen.last.waiting, isFalse);
      expect(seen.last.behind, isTrue);

      engine.dispose();
      fa.flushMicrotasks();
    });
  });

  test('authoritative pause applies while buffering without a seek', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000);
      final player = FakePlayer()
        ..playingNow = true
        ..pos = const Duration(seconds: 50)
        ..bufferingNow = true;
      final socket = MockSocketClient();

      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, pausedSchedule());
      fa.elapse(const Duration(milliseconds: 250));
      fa.flushMicrotasks();

      expect(player.calls, contains('pause'));
      expect(player.calls.where((c) => c.startsWith('seek:')), isEmpty);
      expect(player.playingNow, isFalse);

      engine.dispose();
      fa.flushMicrotasks();
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
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: true,
      );
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      final beforePlays = socket.emitted
          .where((e) => e.$1 == ClientEvent.syncPlay)
          .length;

      fa.elapse(const Duration(milliseconds: 250)); // loop applies play()
      fa.flushMicrotasks(); // deliver the player's playing-stream event

      expect(player.playingNow, isTrue);
      final afterPlays = socket.emitted
          .where((e) => e.$1 == ClientEvent.syncPlay)
          .length;
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
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();

      // Explicit intents are dropped.
      engine.requestPlay();
      engine.requestPause();
      fa.flushMicrotasks();
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
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: true,
      );
      fa.flushMicrotasks();

      engine.requestSeek(const Duration(seconds: 30));
      engine.requestPause();
      fa.flushMicrotasks();

      final seek = socket.emitted.firstWhere(
        (e) => e.$1 == ClientEvent.syncSeek,
      );
      expect((seek.$2 as Map)['positionTicks'], 30 * 1000 * ticksPerMs);
      expect((seek.$2 as Map)['baseVersion'], isNull);
      expect((seek.$2 as Map)['commandId'], isNotEmpty);
      final pause = socket.emitted.firstWhere(
        (e) => e.$1 == ClientEvent.syncPause,
      );
      expect((pause.$2 as Map)['positionTicks'], 42 * 1000 * ticksPerMs);
      expect((pause.$2 as Map)['commandId'], isNotEmpty);

      // A UI-driven play transition authors sync:play at the player position.
      fa.elapse(const Duration(milliseconds: 160));
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
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncSchedule, playingSchedule(version: 5));
      socket.inject(
        ServerEvent.syncSchedule,
        playingSchedule(version: 3),
      ); // stale
      socket.inject(
        ServerEvent.syncSchedule,
        playingSchedule(version: 5),
      ); // dup
      socket.inject(
        ServerEvent.syncSchedule,
        playingSchedule(version: 6),
      ); // ok
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
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();

      socket.inject(
        ServerEvent.syncSchedule,
        pausedSchedule(version: 9, gen: 0),
      );
      // New media: version restarts lower but a new generation resets baseline.
      socket.inject(
        ServerEvent.syncSchedule,
        pausedSchedule(version: 1, gen: 1),
      );
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
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncHostGone, null);
      fa.flushMicrotasks();
      expect(player.calls, contains('pause'));
      expect(player.playingNow, isFalse);

      engine.detach();
    });
  });

  test('buffering reports stalls and recovery for dragging mode', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0);
      final player = FakePlayer();
      final socket = MockSocketClient();
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, pausedSchedule(gen: 4));

      player.setBuffering(true);
      player.setBuffering(false);
      fa.flushMicrotasks();

      final stalls = socket.emitted
          .where((event) => event.$1 == ClientEvent.syncStall)
          .map((event) => event.$2 as Map)
          .toList();
      expect(stalls, [
        {'stalled': false, 'mediaGeneration': 4},
        {'stalled': true, 'mediaGeneration': 4},
        {'stalled': false, 'mediaGeneration': 4},
      ]);
      engine.detach();
    });
  });

  test('buffering during native open does not immediately report a stall', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0);
      final player = FakePlayer();
      final socket = MockSocketClient();
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, pausedSchedule(gen: 4));

      engine.beginOpen();
      fa.flushMicrotasks();
      player.setBuffering(true);
      fa.flushMicrotasks();
      expect(
        socket.emitted.where(
          (event) =>
              event.$1 == ClientEvent.syncStall &&
              (event.$2 as Map)['stalled'] == true,
        ),
        isEmpty,
      );

      engine.endOpen();
      fa.elapse(const Duration(milliseconds: 999));
      expect(
        socket.emitted.where(
          (event) =>
              event.$1 == ClientEvent.syncStall &&
              (event.$2 as Map)['stalled'] == true,
        ),
        isEmpty,
      );
      fa.elapse(const Duration(milliseconds: 1));
      expect(
        socket.emitted.where(
          (event) =>
              event.$1 == ClientEvent.syncStall &&
              (event.$2 as Map)['stalled'] == true,
        ),
        isNotEmpty,
      );
      engine.detach();
    });
  });

  test(
    'buffering waits for a generation, then samples and resends on change',
    () {
      fakeAsync((fa) {
        final engine = engineWith(() => 2000.0);
        final player = FakePlayer()..bufferingNow = true;
        final socket = MockSocketClient();
        engine.attach(
          player: player,
          socket: socket,
          partyId: 'p',
          canControl: false,
        );
        fa.flushMicrotasks();

        player.setBuffering(false);
        player.setBuffering(true);
        fa.flushMicrotasks();
        expect(
          socket.emitted.where((event) => event.$1 == ClientEvent.syncStall),
          isEmpty,
        );

        socket.inject(ServerEvent.syncSchedule, pausedSchedule(gen: 4));
        socket.inject(
          ServerEvent.syncSchedule,
          pausedSchedule(version: 2, gen: 5),
        );

        final stalls = socket.emitted
            .where((event) => event.$1 == ClientEvent.syncStall)
            .map((event) => event.$2 as Map)
            .toList();
        expect(stalls, [
          {'stalled': true, 'mediaGeneration': 4},
          {'stalled': true, 'mediaGeneration': 5},
        ]);
        expect(
          stalls.every((payload) => payload['mediaGeneration'] != null),
          isTrue,
        );
        engine.detach();
      });
    },
  );

  test('peer telemetry includes position and downloaded chunks', () {
    fakeAsync((fa) {
      var now = 2000.0;
      final engine = engineWith(() => now)..downloadedChunks = () => 7;
      final player = FakePlayer()..pos = const Duration(seconds: 12);
      final socket = MockSocketClient();
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      fa.flushMicrotasks();
      socket.inject(
        ServerEvent.syncSchedule,
        pausedSchedule(posTicks: 120000000),
      );
      fa.elapse(const Duration(milliseconds: 250));
      now += 1000;
      fa.elapse(const Duration(seconds: 1));

      final report =
          socket.emitted
                  .lastWhere((event) => event.$1 == ClientEvent.syncReport)
                  .$2
              as Map;
      expect(report['position'], 12.0);
      expect(report['downloadedChunks'], 7);
      expect(report['mediaGeneration'], 0);
      engine.detach();
    });
  });

  test('a local play ignores an old schedule but obeys a newer authority', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0)..isHost = true;
      final player = FakePlayer();
      final socket = DelayedAckSocket();
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: true,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 1));

      engine.requestPlay();
      fa.flushMicrotasks();
      expect(player.playingNow, isTrue);
      final command = socket.emitted.firstWhere(
        (event) => event.$1 == ClientEvent.syncPlay,
      );
      expect((command.$2 as Map)['baseVersion'], isNull);
      expect((command.$2 as Map)['commandId'], isNotEmpty);
      socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 1));
      fa.elapse(const Duration(milliseconds: 500));
      fa.flushMicrotasks();

      expect(player.playingNow, isTrue);
      socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 2));
      fa.elapse(const Duration(milliseconds: 250));
      fa.flushMicrotasks();

      expect(player.playingNow, isFalse);
      socket.acks.single.complete({'ok': true, 'version': 2});
      fa.flushMicrotasks();
      engine.detach();
    });
  });

  test('rapid transport commands do not share an optimistic base version', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0)..isHost = true;
      final player = FakePlayer();
      final socket = DelayedAckSocket();
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: true,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, pausedSchedule(version: 1));

      engine.requestPlay();
      fa.flushMicrotasks();
      engine.requestPause();
      fa.flushMicrotasks();

      final commands = socket.emitted
          .where(
            (event) =>
                event.$1 == ClientEvent.syncPlay ||
                event.$1 == ClientEvent.syncPause,
          )
          .map((event) => event.$2 as Map)
          .toList();
      expect(commands, hasLength(2));
      expect(
        commands.every((command) => !command.containsKey('baseVersion')),
        isTrue,
      );
      expect(commands[0]['commandId'], isNot(commands[1]['commandId']));

      socket.acks[0].complete({'ok': true, 'version': 2});
      socket.acks[1].complete({'ok': true, 'version': 3});
      fa.flushMicrotasks();
      engine.detach();
    });
  });

  test('a delayed play cannot emit into a replacement attachment', () async {
    final engine = engineWith(() => 2000.0)..isHost = true;
    final firstPlayer = FakePlayer()..playGate = Completer<void>();
    final firstSocket = MockSocketClient();
    final secondSocket = MockSocketClient();

    await engine.attach(
      player: firstPlayer,
      socket: firstSocket,
      partyId: 'one',
      canControl: true,
    );
    final play = engine.requestPlay();
    await Future<void>.delayed(Duration.zero);
    final replacement = engine.attach(
      player: FakePlayer(),
      socket: secondSocket,
      partyId: 'two',
      canControl: true,
    );
    firstPlayer.playGate!.complete();
    await play;
    await replacement;

    expect(
      firstSocket.emitted.where((event) => event.$1 == ClientEvent.syncPlay),
      isEmpty,
    );
    expect(
      secondSocket.emitted.where((event) => event.$1 == ClientEvent.syncPlay),
      isEmpty,
    );
    await engine.dispose();
  });

  test('a pending local pause yields to a newer playing schedule', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0)..isHost = true;
      final player = FakePlayer()..playingNow = true;
      final socket = DelayedAckSocket();
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: true,
      );
      fa.flushMicrotasks();
      socket.inject(ServerEvent.syncSchedule, playingSchedule(version: 1));

      engine.requestPause();
      fa.flushMicrotasks();
      expect(player.playingNow, isFalse);

      socket.inject(ServerEvent.syncSchedule, playingSchedule(version: 2));
      fa.elapse(const Duration(milliseconds: 250));
      fa.flushMicrotasks();

      expect(player.playingNow, isTrue);
      socket.acks.single.complete({'ok': true, 'version': 2});
      fa.flushMicrotasks();
      engine.detach();
    });
  });

  test('attach, detach, and dispose are serialized', () async {
    final engine = engineWith(() => 2000.0);
    final firstPlayer = FakePlayer();
    final secondPlayer = FakePlayer();
    final firstSocket = MockSocketClient();
    final secondSocket = MockSocketClient();

    await engine.attach(
      player: firstPlayer,
      socket: firstSocket,
      partyId: 'one',
      canControl: false,
    );
    final detach = engine.detach();
    final secondAttach = engine.attach(
      player: secondPlayer,
      socket: secondSocket,
      partyId: 'two',
      canControl: false,
    );
    await secondAttach;
    final dispose = engine.dispose();
    await Future.wait([detach, dispose]);

    firstSocket.inject(ServerEvent.syncHostGone, null);
    secondSocket.inject(ServerEvent.syncHostGone, null);
    expect(firstPlayer.calls, isEmpty);
    expect(secondPlayer.calls, isEmpty);
    expect(engine.isDisposed, isTrue);
  });

  test('hopping host is not corrected but is kicked into play', () {
    fakeAsync((fa) {
      final engine = engineWith(() => 2000.0)
        ..isHost = true
        ..syncMode = 'hopping';
      final player = FakePlayer(); // paused
      final socket = MockSocketClient();
      engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: true,
      );
      fa.flushMicrotasks();

      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      fa.flushMicrotasks();
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

  // Deliberately NOT fakeAsync, unlike every other test in this file.
  //
  // detach() awaits _playingSub.cancel(), and a broadcast StreamSubscription's
  // cancel() future never completes inside fakeAsync — verified in isolation:
  // a bare `StreamController.broadcast()` subscription's cancel() stays pending
  // through flushMicrotasks() and through elapse(), while the same controller's
  // close() does deliver onDone normally. So under fakeAsync dispose() hangs at
  // `await detach()` and never reaches the stream close, meaning the assertions
  // below would be measuring the harness rather than the engine.
  //
  // Real timers instead, kept short: the control loop is 200ms, so a ~300ms
  // wait proves it is live and a ~500ms wait proves it stopped.
  test(
    'dispose() stops the control loop and closes the engine streams',
    () async {
      final engine = engineWith(() => 2000.0);
      final player = FakePlayer();
      final socket = MockSocketClient();
      var scheduleStreamDone = false;
      engine.scheduleStream.listen(
        (_) {},
        onDone: () => scheduleStreamDone = true,
      );

      await engine.attach(
        player: player,
        socket: socket,
        partyId: 'p',
        canControl: false,
      );
      socket.inject(ServerEvent.syncSchedule, playingSchedule());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(player.calls, isNotEmpty, reason: 'the control loop is live');

      await engine.dispose();

      // Nothing may drive the player after disposal — the 200ms control loop,
      // the applying timers and the user-seek timer all outlived the provider
      // before, still holding the player and socket they were attached to.
      player.calls.clear();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(player.calls, isEmpty);
      expect(engine.isDisposed, isTrue);
      expect(scheduleStreamDone, isTrue);
    },
  );
}
