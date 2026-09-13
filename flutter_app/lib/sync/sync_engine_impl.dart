import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../diagnostics/reliability_diagnostics.dart';
import '../models/party_state.dart';
import '../net/events.dart';
import '../net/socket_client.dart';
import '../player/player_controller.dart';
import 'server_clock.dart';
import 'sync_core.dart';
import 'sync_engine.dart';

/// Real host-authority sync engine (PLAN §3.4 / E5.1). Port of the web
/// `useSyncPlay` hook: it binds a [PlayerController] to a [SocketClient] and
/// keeps local playback locked onto the server's shared [SyncSchedule] using
/// the pure [decideSyncAction] core, with drift correction, the applying-guard
/// (feedback-loop suppression), schedule versioning, and the canControl gate.
///
/// Fidelity notes vs. the browser hook:
///  - The web hard-seek is buffer-aware (HLS: pause → seek → await 'seeked' →
///    await BUFFER_AHEAD_SEC runway → snap to live → play). media_kit direct-
///    plays the original file (no HLS, no autoStartLoad:false loader) and the
///    frozen [PlayerController] exposes no buffered-range API, so a hard seek is
///    applied as a guarded seek(+play) and the loader is left to media_kit. The
///    HARD_SEEK_COOLDOWN hysteresis is preserved so a slow catch-up isn't
///    re-triggered from stale drift. `bufferSeek.js`'s waitForSeeked /
///    waitForBuffer / ensureHlsLoad have no analog here by design.
///  - Seek authoring has no discrete player event in the [PlayerController]
///    contract, so a controller's scrub must be reported via [requestSeek].
///    Play/pause authoring is driven from the player's `playing` stream (the
///    equivalent of the web's media 'play'/'pause' events), guarded and
///    de-duplicated against the current schedule phase to prevent echo.
class SyncEngineImpl implements SyncEngine {
  SyncEngineImpl({ServerClock? clock, this.clockFactory})
    : _injectedClock = clock;

  /// Optional factory to build a clock from the attached socket (defaults to a
  /// [SocketServerClock] driving `clock:ping`). Tests inject a [ManualServerClock].
  final ServerClock Function(SocketClient socket)? clockFactory;
  final ServerClock? _injectedClock;

  PlayerController? _player;
  SocketClient? _socket;
  ServerClock? _clock;
  bool _canControl = false;

  /// True when the local user is the party host (party.hostId == me). Distinct
  /// from [canControl] (see the `_isHost` note). E5.2 sets it from party state.
  bool isHost = false;
  String _mode = 'dragging';

  // ── Guards / refs (mirrors the useRef state in the web hook) ─────────────
  int _applying = 0; // reference-counted applying-guard (see markApplying)
  final List<Timer> _applyingTimers = [];
  SyncSchedule? _schedule;
  bool _userSeeking = false;
  Timer? _userSeekTimer;
  double _lastAppliedVersion = double.negativeInfinity;
  _PendingCommand? _pendingCommand;
  int _nextCommandId = 0;
  int? _lastMediaGen;
  int _lastReportMs = 0;
  int _lastHardSeekAtMs = -hardSeekCooldownMs;
  int _bufferRecoveryUntilMs = 0;
  final Stopwatch _monotonic = Stopwatch()..start();
  bool _loggedRecoverySuppression = false;

  Timer? _controlLoop;
  Timer? _openingStallTimer;
  final List<void Function()> _unsubs = [];
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  bool _stalled = false;
  bool? _reportedStalled;
  int? _reportedStallGeneration;
  Future<void> _lifecycle = Future.value();
  int _attachmentGeneration = 0;
  bool _disposeRequested = false;
  bool _disposed = false;
  Future<void> _operations = Future.value();
  int _operationEpoch = 0;
  int _opening = 0;
  int _busy = 0;
  bool _hostGone = false;
  bool _suppressLocalStartupStall = false;

  /// Suspend authoring and correction before touching the native open pipeline.
  Future<void> beginOpen({bool localPlayback = false}) {
    _opening++;
    _operationEpoch++;
    _suppressLocalStartupStall = localPlayback;
    if (localPlayback && _stalled) {
      _stalled = false;
      if (_reportedStalled == true) _reportStall();
    }
    return Future.wait<void>([_lifecycle, _operations]).then((_) {});
  }

  void endOpen() {
    if (_opening > 0) _opening--;
    if (_opening == 0 && _player != null && !_disposeRequested) {
      _markApplying();
      _openingStallTimer?.cancel();
      if (_stalled) {
        _openingStallTimer = Timer(const Duration(seconds: 1), () {
          if (_opening == 0 && _stalled && !_disposeRequested) {
            _reportStall();
            _emitCatchUp(CatchUp(waiting: true, drift: _currentDrift()));
          }
        });
      }
    }
  }

  Duration get scheduledPosition =>
      _sec(predictPosition(_schedule, _serverNow()).clamp(0, double.infinity));

  /// Session acknowledgements carry authority too, not only socket pushes.
  void acceptSchedule(SyncSchedule schedule) => _onSchedule(schedule.toJson());

  Future<void> _operate(Future<void> Function(bool Function()) action) {
    final attachment = _attachmentGeneration;
    final epoch = _operationEpoch;
    bool valid() =>
        attachment == _attachmentGeneration &&
        epoch == _operationEpoch &&
        !_disposeRequested &&
        _opening == 0;
    _busy++;
    final next = _operations.then((_) async {
      if (!valid()) return;
      try {
        await action(valid);
      } finally {
        if (valid()) _markApplying();
      }
    });
    _operations = next.then<void>(
      (_) {
        _busy--;
      },
      onError: (_, _) {
        _busy--;
      },
    );
    return next;
  }

  /// UI route: call instead of locally seeking and reporting afterwards.
  Future<void> seekTo(Duration position) {
    if (!_canControl || _opening > 0) return Future.value();
    final schedule = _schedule;
    _operationEpoch++;
    return _operate((valid) async {
      if (!_canControl) return;
      await _player?.seek(position);
      if (valid() && _canControl && identical(_schedule, schedule)) {
        await requestSeek(position);
      }
    });
  }

  int Function()? downloadedChunks;

  final _scheduleCtrl = StreamController<SyncSchedule>.broadcast();
  final _driftCtrl = StreamController<Duration>.broadcast();
  final _catchUpCtrl = StreamController<CatchUp>.broadcast();
  CatchUp _catchUp = CatchUp.idle;

  static const int _reportMs = 1000;
  static const int _bufferRecoveryNoJumpMs = 30_000;
  static const _syncDiagnosticsEnabled = bool.fromEnvironment(
    'WATCHPARTY_SYNC_DIAGNOSTICS',
  );

  void _logSync(String event, Map<String, Object?> fields) {
    if (!_syncDiagnosticsEnabled) return;
    ReliabilityDiagnostics.instance.record('sync', event, fields);
    debugPrint('[sync] ${jsonEncode({'event': event, ...fields})}');
  }

  // INTERFACE FRICTION (flagged): the frozen [SyncEngine.attach] only carries
  // [canControl] (host OR collaborative), but [decideSyncAction] needs the true
  // host role — a hopping host plays natively and is exempt from the correction
  // loop, whereas a collaborative *guest* both follows the timeline AND may
  // author. E5.2 must set [isHost] from party state (hostId == me). Defaults to
  // false: a host that forgets to set it merely runs the guest correction loop
  // against its own authored schedule (safe, ~no-op), never a broken state.
  bool get _isHost => isHost;

  @override
  Future<void> attach({
    required PlayerController player,
    required SocketClient socket,
    required String partyId,
    required bool canControl,
  }) {
    if (_disposeRequested) return _lifecycle;
    _operationEpoch++;
    _canControl = canControl;
    return _serializeLifecycle(() async {
      await _detachNow();
      if (_disposeRequested) return;
      _player = player;
      _socket = socket;

      final clock =
          _injectedClock ??
          (clockFactory?.call(socket) ?? SocketServerClock(socket));
      _clock = clock;
      if (clock is SocketServerClock) clock.start();

      _unsubs.add(socket.on(ServerEvent.syncSchedule, _onSchedule));
      _unsubs.add(socket.on(ServerEvent.syncHostGone, (_) => _onHostGone()));

      // Author play/pause from the player's own transitions (the Dart analog of
      // the web media element's 'play'/'pause' events wired to request*).
      _playingSub = player.playing.listen(_onPlayingChanged);
      _stalled = player.isBufferingNow && !_suppressLocalStartupStall;
      if (_stalled) {
        _logSync('attach_buffering', {
          'mediaGeneration': _schedule?.mediaGeneration,
        });
      }
      _bufferingSub = player.buffering.listen(_onBufferingChanged);

      // Ask the server for the current timeline once we're listening (avoids the
      // race where a pushed schedule arrives before we subscribed).
      socket.emit(ClientEvent.syncHello);

      _controlLoop = Timer.periodic(
        const Duration(milliseconds: controlMs),
        (_) => _tick(),
      );
    });
  }

  @override
  Future<void> detach() {
    if (_disposeRequested) return _lifecycle;
    _operationEpoch++;
    return _serializeLifecycle(_detachNow);
  }

  Future<void> _detachNow() async {
    _attachmentGeneration++;
    _operationEpoch++;
    _controlLoop?.cancel();
    _controlLoop = null;
    _openingStallTimer?.cancel();
    _openingStallTimer = null;
    for (final u in _unsubs) {
      u();
    }
    _unsubs.clear();
    await _playingSub?.cancel();
    _playingSub = null;
    await _bufferingSub?.cancel();
    _bufferingSub = null;
    if (_reportedStalled == true && _reportedStallGeneration != null) {
      _socket?.emit(ClientEvent.syncStall, {
        'stalled': false,
        'mediaGeneration': _reportedStallGeneration,
      });
    }
    _stalled = false;
    _bufferRecoveryUntilMs = 0;
    _loggedRecoverySuppression = false;
    _reportedStalled = null;
    _reportedStallGeneration = null;
    if (_opening == 0) _suppressLocalStartupStall = false;
    _userSeekTimer?.cancel();
    _userSeekTimer = null;
    for (final t in _applyingTimers) {
      t.cancel();
    }
    _applyingTimers.clear();
    _applying = 0;
    final clock = _clock;
    if (clock is SocketServerClock) clock.stop();
    _clock = null;
    await _operations;
    try {
      await _player?.setRate(1);
    } catch (_) {
      // Teardown must finish even if the native player has already closed.
    }
    _player = null;
    _socket = null;
    _schedule = null;
    _lastAppliedVersion = double.negativeInfinity;
    _pendingCommand = null;
    _lastMediaGen = null;
    _hostGone = false;
    _userSeeking = false;
    _lastHardSeekAtMs = -hardSeekCooldownMs;
    _lastReportMs = 0;
    _emitCatchUp(CatchUp.idle);
  }

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final next = _lifecycle.then((_) => operation());
    _lifecycle = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  // ── Applying-guard (feedback-loop suppression), refcounted like the web ──
  void _markApplying() {
    _applying += 1;
    late Timer t;
    t = Timer(const Duration(milliseconds: 150), () {
      _applying = _applying > 0 ? _applying - 1 : 0;
      _applyingTimers.remove(t);
    });
    _applyingTimers.add(t);
  }

  double _nowMs() => DateTime.now().millisecondsSinceEpoch.toDouble();
  int _monotonicMs() => _monotonic.elapsedMilliseconds;
  double _serverNow() => _clock?.serverNow() ?? _nowMs();
  bool _clockReady() => _clock?.ready ?? false;

  void _notifyUserSeeking() {
    _userSeeking = true;
    _userSeekTimer?.cancel();
    _userSeekTimer = Timer(
      const Duration(seconds: 3),
      () => _userSeeking = false,
    );
  }

  // ── Incoming server schedule ─────────────────────────────────────────────
  void _onSchedule(dynamic data) {
    if (data is! Map) return;
    final s = SyncSchedule.fromJson(Map<String, dynamic>.from(data));

    // Reset the version baseline on a media-generation change (new media /
    // back-to-lobby); schedule.version keeps climbing across generations
    // within one party session, it does not restart.
    final gen = s.mediaGeneration;
    final previousGen = _lastMediaGen;
    if (previousGen != null && gen < previousGen) return;
    final generationChanged = gen != previousGen;
    if (generationChanged) {
      _lastMediaGen = gen;
      _lastAppliedVersion = double.negativeInfinity;
    }
    // Drop a stale/duplicate/out-of-order schedule — only ever move forward.
    if (s.version <= _lastAppliedVersion) return;
    _lastAppliedVersion = s.version.toDouble();

    _schedule = s;
    _hostGone = false;
    _userSeeking = false;
    _userSeekTimer?.cancel();
    final pending = _pendingCommand;
    if (pending != null &&
        (generationChanged || s.version > pending.observedVersion)) {
      _pendingCommand = null;
    }
    _reportStall(force: generationChanged);
    _scheduleCtrl.add(s);

    _kickHostPlay();
  }

  void _onHostGone() {
    _hostGone = true;
    _operationEpoch++;
    final p = _player;
    if (p != null) {
      unawaited(_operate((valid) => p.pause()).catchError((Object _) {}));
    }
  }

  // ── Host authoring from the player's own play/pause transitions ──────────
  void _onPlayingChanged(bool playing) {
    if (playing) _suppressLocalStartupStall = false;
    if (!_canControl) return;
    if (_opening > 0 || _busy > 0 || _hostGone) return;
    if (_applying > 0) return; // our own applied change — don't echo it back
    final phase = _schedule?.phase;
    final posTicks = (_player?.positionNow.inMilliseconds ?? 0) * ticksPerMs;
    if (playing && phase != 'playing') {
      _sendTransportCommand('play', posTicks, includeT0: true);
    } else if (!playing && phase == 'playing') {
      _sendTransportCommand('pause', posTicks);
    }
  }

  void _onBufferingChanged(bool stalled) {
    // media_kit on Windows can hold a local source in `buffering=true` until
    // its first play. Reporting that startup state freezes Follow mode before
    // the player gets the play it needs to clear it. Real stalls after playback
    // begins still pass through normally.
    if (stalled && _suppressLocalStartupStall) {
      _stalled = false;
      if (_reportedStalled == true) _reportStall();
      return;
    }
    _stalled = stalled;
    if (_opening > 0) {
      if (stalled) {
        unawaited(_player?.setRate(1).catchError((Object _) {}));
        _emitCatchUp(CatchUp(waiting: true, drift: _currentDrift()));
      }
      return;
    }
    _openingStallTimer?.cancel();
    _openingStallTimer = null;
    _reportStall();
    if (stalled) {
      _bufferRecoveryUntilMs = 0;
      _loggedRecoverySuppression = false;
      _logSync('buffering_start', {
        'mediaGeneration': _schedule?.mediaGeneration,
        'positionMs': _player?.positionNow.inMilliseconds,
        'driftMs': _currentDrift().inMilliseconds,
        'phase': _schedule?.phase,
      });
      unawaited(_player?.setRate(1).catchError((Object _) {}));
      _emitCatchUp(CatchUp(waiting: true, drift: _currentDrift()));
    } else {
      _bufferRecoveryUntilMs = _monotonicMs() + _bufferRecoveryNoJumpMs;
      _logSync('buffering_end', {
        'mediaGeneration': _schedule?.mediaGeneration,
        'positionMs': _player?.positionNow.inMilliseconds,
        'driftMs': _currentDrift().inMilliseconds,
        'recoveryUntilMs': _bufferRecoveryUntilMs,
      });
      if (_schedule?.phase != 'stalled') {
        _emitCatchUp(CatchUp(rate: 1, drift: _currentDrift()));
      }
    }
  }

  Duration _currentDrift() {
    final schedule = _schedule;
    final player = _player;
    if (schedule == null || player == null || !_clockReady()) {
      return Duration.zero;
    }
    final expected = predictPosition(schedule, _serverNow());
    return Duration(
      milliseconds:
          ((expected - player.positionNow.inMilliseconds / 1000) * 1000)
              .round(),
    );
  }

  void _reportStall({bool force = false}) {
    final generation = _schedule?.mediaGeneration;
    if (generation == null) return;
    if (!force &&
        _reportedStalled == _stalled &&
        _reportedStallGeneration == generation) {
      return;
    }
    _socket?.emit(ClientEvent.syncStall, {
      'stalled': _stalled,
      'mediaGeneration': generation,
    });
    _reportedStalled = _stalled;
    _reportedStallGeneration = generation;
  }

  // Hopping hosts keep native position, but still obey authoritative transport.
  void _kickHostPlay() {
    if (_opening > 0 || _busy > 0 || _hostGone) return;
    final p = _player;
    final schedule = _schedule;
    if (p == null ||
        schedule == null ||
        !_isHost ||
        _mode == 'dragging' ||
        _pendingCommand != null) {
      return;
    }
    final play = schedule.phase == 'playing';
    if (play == p.isPlayingNow) return;
    unawaited(
      _operate((valid) async {
        if (!identical(_schedule, schedule)) return;
        if (play) {
          await p.play();
        } else {
          await p.pause();
        }
      }).catchError((Object _) {}),
    );
  }

  // ── Control loop (200ms), port of the useSyncPlay setInterval ────────────
  void _tick() {
    final p = _player;
    final s = _schedule;
    if (p == null || s == null) return;
    // Stream delivery can be coalesced while mpv rebuilds tracks. Never let a
    // missed buffering=false event freeze Follow mode after the player itself
    // already reports that it recovered.
    if (_stalled && !p.isBufferingNow) _onBufferingChanged(false);
    _reportPlayback(p, _currentDrift().inMilliseconds / 1000);
    if (_stalled) {
      if (s.phase != 'playing' && p.isPlayingNow && _busy == 0) {
        unawaited(
          _operate((valid) async {
            if (identical(_schedule, s)) await p.pause();
          }).catchError((Object _) {}),
        );
      }
      _emitCatchUp(CatchUp(waiting: true, drift: _currentDrift()));
      return;
    }
    if (_opening > 0 || _busy > 0 || _hostGone) return;
    // A locally-authored command is in flight and hasn't round-tripped yet —
    // scheduleRef is still stale. Skip so our own change isn't fought.
    if (_applying > 0) return;
    final pending = _pendingCommand;
    if (pending != null) {
      if (pending.untilMs > DateTime.now().millisecondsSinceEpoch) return;
      _pendingCommand = null;
    }

    _kickHostPlay();

    if (_busy > 0) return;

    final nowMs = _monotonicMs();
    final inBufferRecovery = nowMs < _bufferRecoveryUntilMs;
    final suppressHardSeek =
        nowMs - _lastHardSeekAtMs < hardSeekCooldownMs || inBufferRecovery;
    final intent = decideSyncAction(
      schedule: s,
      serverNowMs: _serverNow,
      clockReady: _clockReady,
      currentTime: p.positionNow.inMilliseconds / 1000.0,
      paused: !p.isPlayingNow,
      isHost: _isHost,
      mode: _mode,
      userSeeking: _userSeeking,
      suppressHardSeek: suppressHardSeek,
      duration: p.durationNow > Duration.zero
          ? p.durationNow.inMilliseconds / 1000.0
          : null,
    );
    if (intent == null) {
      final drift = _currentDrift();
      if (inBufferRecovery &&
          !_loggedRecoverySuppression &&
          drift.inMilliseconds.abs() > (hardSeekSec * 1000).round()) {
        _loggedRecoverySuppression = true;
        _logSync('hard_seek_suppressed_for_buffer_recovery', {
          'mediaGeneration': s.mediaGeneration,
          'positionMs': p.positionNow.inMilliseconds,
          'driftMs': drift.inMilliseconds,
          'phase': s.phase,
          'recoveryRemainingMs': (_bufferRecoveryUntilMs - nowMs).round(),
        });
      }
      _emitCatchUp(CatchUp(waiting: _stalled || s.phase == 'stalled'));
      _reportPlayback(p, null);
      return;
    }
    if (s.phase == 'stalled') {
      _emitCatchUp(CatchUp(waiting: true, drift: _sec(intent.drift ?? 0)));
    }
    _reportPlayback(p, intent.drift);

    if (intent.hardSeek) {
      _lastHardSeekAtMs = _monotonicMs();
    }
    unawaited(
      _operate((valid) async {
        bool current() => valid() && identical(_schedule, s);
        if (intent.pause && p.isPlayingNow) await p.pause();
        if (!current()) return;
        if (intent.seekToSec != null) await p.seek(_sec(intent.seekToSec!));
        if (!current()) return;
        if (intent.rate != null) await p.setRate(intent.rate!);
        if (!current()) return;
        if (intent.play || (intent.hardSeek && s.phase == 'playing')) {
          await p.play();
        }
      }).catchError((Object _) {}),
    );

    // Drift telemetry — guests only (a hopping host returned null above).
    if (!_isHost) {
      _driftCtrl.add(_sec(intent.drift ?? 0));
      _emitCatchUp(
        CatchUp(
          rate: intent.rate ?? 1,
          drift: _sec(intent.drift ?? 0),
          seeking: intent.seekToSec != null,
          waiting: _stalled || s.phase == 'stalled',
        ),
      );
    }
  }

  void _reportPlayback(PlayerController player, double? drift) {
    final now = _nowMs();
    if (now - _lastReportMs < _reportMs) return;
    _lastReportMs = now.toInt();
    _socket?.emit(ClientEvent.syncReport, {
      'position': player.positionNow.inMilliseconds / 1000.0,
      'drift': drift ?? 0,
      'rate': _catchUp.rate,
      'downloadedChunks': downloadedChunks?.call() ?? 0,
      'mediaGeneration': _schedule?.mediaGeneration,
      'stalled': _stalled,
    });
  }

  /// Only on a CHANGE. The correction loop runs every CONTROL_MS, and pushing
  /// an identical value 5x a second would rebuild the badge for nothing.
  void _emitCatchUp(CatchUp next) {
    if (next.active == _catchUp.active &&
        next.behind == _catchUp.behind &&
        next.rate == _catchUp.rate &&
        next.waiting == _catchUp.waiting &&
        next.seeking == _catchUp.seeking) {
      if (next.drift != _catchUp.drift) {
        _catchUp = next;
        if (!_catchUpCtrl.isClosed) _catchUpCtrl.add(next);
        return;
      }
      _catchUp = next;
      return;
    }
    _catchUp = next;
    if (!_catchUpCtrl.isClosed) _catchUpCtrl.add(next);
  }

  Duration _sec(double s) => Duration(milliseconds: (s * 1000).round());

  // ── canControl gate ──────────────────────────────────────────────────────
  @override
  bool get canControl => _canControl;
  @override
  set canControl(bool value) => _canControl = value;

  /// Host toggles hopping ↔ dragging (E5.2 wires party:setSyncMode). Kept off
  /// the frozen interface; the engine reads it in the control loop.
  set syncMode(String mode) =>
      _mode = mode == 'dragging' ? 'dragging' : 'hopping';
  String get syncMode => _mode;

  // ── Local user intents (only take effect while canControl) ───────────────
  void _sendTransportCommand(
    String kind,
    int positionTicks, {
    bool includeT0 = false,
  }) {
    final socket = _socket;
    if (socket == null) return;
    final schedule = _schedule;
    final command = _PendingCommand(
      kind: kind,
      id: '${DateTime.now().microsecondsSinceEpoch}-${_nextCommandId++}',
      observedVersion: schedule?.version ?? -1,
      untilMs: DateTime.now().millisecondsSinceEpoch + 2000,
    );
    _pendingCommand = command;
    final payload = <String, Object>{
      'positionTicks': positionTicks,
      'commandId': command.id,
      if (includeT0) 't0': _serverNow(),
    };
    unawaited(_awaitCommandAck(socket, command, 'sync:$kind', payload));
  }

  Future<void> _awaitCommandAck(
    SocketClient socket,
    _PendingCommand command,
    String event,
    Map<String, Object> payload,
  ) async {
    dynamic response;
    try {
      response = await socket
          .emitWithAck(event, payload)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      if (identical(_pendingCommand, command)) _pendingCommand = null;
      return;
    }
    if (!identical(_pendingCommand, command)) return;
    if (response is! Map || response['ok'] != true) {
      _pendingCommand = null;
      return;
    }
    final version = response['version'];
    if (version is! num || (_schedule?.version ?? -1) >= version.toInt()) {
      _pendingCommand = null;
    }
  }

  /// The transport's play, authored.
  ///
  /// Applies to the local player under the applying-guard AND emits, rather
  /// than only emitting: a viewer who presses play must see the frame move
  /// now, not after a server round trip. The guard is what keeps
  /// [_onPlayingChanged] from emitting the same command a second time.
  ///
  /// No `_applying` early-return, unlike the correction loop: this is a
  /// deliberate gesture, not an echo, and dropping it because the engine
  /// happened to be mid-apply is how a press goes nowhere.
  @override
  Future<void> requestPlay() async {
    if (!_canControl || _opening > 0) return;
    final schedule = _schedule;
    _operationEpoch++;
    await _operate((valid) async {
      final p = _player;
      if (!_canControl) return;
      if (p != null && !p.isPlayingNow) await p.play();
      if (!valid() || !_canControl || !identical(_schedule, schedule)) return;
      _sendTransportCommand(
        'play',
        (p?.positionNow.inMilliseconds ?? 0) * ticksPerMs,
        includeT0: true,
      );
    });
  }

  @override
  Future<void> requestPause() async {
    if (!_canControl || _opening > 0) return;
    final schedule = _schedule;
    _operationEpoch++;
    await _operate((valid) async {
      final p = _player;
      if (!_canControl) return;
      if (p != null && p.isPlayingNow) await p.pause();
      if (!valid() || !_canControl || !identical(_schedule, schedule)) return;
      _sendTransportCommand(
        'pause',
        (p?.positionNow.inMilliseconds ?? 0) * ticksPerMs,
      );
    });
  }

  @override
  Future<void> requestSeek(Duration position) async {
    if (!_canControl || _opening > 0) return;
    _operationEpoch++;
    _notifyUserSeeking();
    _sendTransportCommand(
      'seek',
      position.inMilliseconds * ticksPerMs,
      includeT0: true,
    );
  }

  @override
  SyncSchedule get currentSchedule => _schedule ?? const SyncSchedule();

  @override
  Stream<SyncSchedule> get scheduleStream => _scheduleCtrl.stream;

  @override
  Stream<Duration> get drift => _driftCtrl.stream;

  @override
  Stream<CatchUp> get catchUp => _catchUpCtrl.stream;

  /// True once [dispose] has run: no control loop, applying timers, user-seek
  /// timer, socket handlers, clock ping, or open stream controllers remain.
  bool get isDisposed => _disposed;

  /// Final teardown, wired to `syncEngineProvider`'s `onDispose`. [detach]
  /// alone leaves the engine reusable (and its schedule/drift controllers
  /// open); this releases it for good, because a container teardown used to
  /// leave the 200ms control loop and the clock's ping timer running against a
  /// player and socket nobody owns anymore. Kept off the frozen [SyncEngine]
  /// interface — the provider builds the concrete engine.
  Future<void> dispose() async {
    if (_disposeRequested) return _lifecycle;
    _disposeRequested = true;
    return _serializeLifecycle(() async {
      if (_disposed) return;
      await _detachNow();
      _disposed = true;
      await _scheduleCtrl.close();
      await _driftCtrl.close();
      await _catchUpCtrl.close();
    });
  }
}

class _PendingCommand {
  const _PendingCommand({
    required this.kind,
    required this.id,
    required this.observedVersion,
    required this.untilMs,
  });

  final String kind;
  final String id;
  final int observedVersion;
  final int untilMs;
}
