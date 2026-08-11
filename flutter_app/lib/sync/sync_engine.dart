import 'dart:async';

import '../models/party_state.dart';
import '../net/socket_client.dart';
import '../player/player_controller.dart';

/// FROZEN CONTRACT (PLAN §3.4). The host-authority sync engine binds a
/// [PlayerController] to a [SocketClient] and keeps local playback locked onto
/// the server's shared [SyncSchedule]. E5.1 implements the real drift-correction
/// / applying-guard algorithm (ported from the web `useSyncPlay`); Phase 0 ships
/// only the interface + a passive mock.
abstract class SyncEngine {
  /// Begin driving [player] from [socket] for the given party. [canControl]
  /// gates whether local user gestures author sync commands (host / collaborative).
  Future<void> attach({
    required PlayerController player,
    required SocketClient socket,
    required String partyId,
    required bool canControl,
  });

  /// Stop syncing and detach listeners (does not dispose the player/socket).
  Future<void> detach();

  /// Whether local gestures currently author sync commands.
  bool get canControl;
  set canControl(bool value);

  // ── Local user intents (only take effect when [canControl]) ────────────
  //
  // These are the ONLY route a party's transport may take. Poking
  // [PlayerController.play]/[PlayerController.pause] directly leaves the engine
  // unaware that a command was authored, so its applying-guard never fires and
  // the correction loop treats the result as drift to undo.
  Future<void> requestPlay();
  Future<void> requestPause();
  Future<void> requestSeek(Duration position);

  /// The last schedule the engine applied.
  SyncSchedule get currentSchedule;

  /// Emits every schedule the engine applies locally.
  Stream<SyncSchedule> get scheduleStream;

  /// Current measured drift between local playback and the shared timeline.
  Stream<Duration> get drift;

  /// How the correction loop is nudging local playback right now.
  ///
  /// Exposed so the player can SAY what it is doing. Silently altering the
  /// speed of someone's film is the kind of thing that reads as a fault when it
  /// is noticed and not understood — and now that the catch-up band is wide
  /// enough to ride out a real buffering stumble, it will be noticed. A viewer
  /// told "catching up" waits; a viewer not told wonders what is wrong with the
  /// app.
  Stream<CatchUp> get catchUp;
}

/// The correction loop's current nudge, as something the UI can render.
class CatchUp {
  const CatchUp({this.rate = 1.0, this.drift = Duration.zero});

  /// The playback rate the correction loop has applied. 1.0 means it is not
  /// correcting at all.
  final double rate;

  /// Signed distance from the room's timeline: positive means behind it.
  final Duration drift;

  /// Deliberately not `rate != 1.0`: the nudge is a float computed from a gain,
  /// so it lands on values like 1.0000000002 and would otherwise flicker the
  /// badge on and off around the release threshold.
  bool get active => (rate - 1.0).abs() > 0.005;

  /// Behind the room and being sped up, as opposed to ahead and being held
  /// back. Both are corrections; only one of them is "catching up".
  bool get behind => rate > 1.0;

  static const idle = CatchUp();
}

/// No-op mock: reflects schedules it receives via [applySchedule] and echoes
/// intents to the socket, so party UI (E5.2/5.3) can be built before the real
/// engine lands. It does NOT perform drift correction.
class MockSyncEngine implements SyncEngine {
  PlayerController? _player;
  SocketClient? _socket;
  // ignore: unused_field
  String? _partyId; // stored for the real E5 engine; unused in the mock
  bool _canControl = false;

  final _scheduleCtrl = StreamController<SyncSchedule>.broadcast();
  final _driftCtrl = StreamController<Duration>.broadcast();
  final _catchUpCtrl = StreamController<CatchUp>.broadcast();
  SyncSchedule _schedule = const SyncSchedule();

  @override
  Future<void> attach({
    required PlayerController player,
    required SocketClient socket,
    required String partyId,
    required bool canControl,
  }) async {
    _player = player;
    _socket = socket;
    _partyId = partyId;
    _canControl = canControl;
  }

  @override
  Future<void> detach() async {
    _player = null;
    _socket = null;
    _partyId = null;
  }

  /// Test/E5 hook: apply an incoming schedule (loosely mirrors it onto the player).
  Future<void> applySchedule(SyncSchedule schedule) async {
    _schedule = schedule;
    _scheduleCtrl.add(schedule);
    final player = _player;
    if (player == null) return;
    if (schedule.paused) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  @override
  bool get canControl => _canControl;
  @override
  set canControl(bool value) => _canControl = value;

  @override
  Future<void> requestPlay() async {
    if (!_canControl) return;
    await _player?.play();
    _socket?.emit('sync:play', {'positionTicks': 0});
  }

  @override
  Future<void> requestPause() async {
    if (!_canControl) return;
    await _player?.pause();
    _socket?.emit('sync:pause', {'positionTicks': 0});
  }

  @override
  Future<void> requestSeek(Duration position) async {
    if (_canControl) {
      _socket?.emit('sync:seek',
          {'positionTicks': position.inMilliseconds * 10000});
    }
  }

  @override
  SyncSchedule get currentSchedule => _schedule;

  @override
  Stream<SyncSchedule> get scheduleStream => _scheduleCtrl.stream;

  @override
  Stream<Duration> get drift => _driftCtrl.stream;

  /// The mock never corrects, so it never announces a correction.
  @override
  Stream<CatchUp> get catchUp => _catchUpCtrl.stream;
}
