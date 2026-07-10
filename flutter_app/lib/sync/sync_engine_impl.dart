import 'dart:async';

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
  SyncEngineImpl({ServerClock? clock, this.clockFactory}) : _injectedClock = clock;

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
  String _mode = 'hopping';

  // ── Guards / refs (mirrors the useRef state in the web hook) ─────────────
  int _applying = 0; // reference-counted applying-guard (see markApplying)
  final List<Timer> _applyingTimers = [];
  SyncSchedule? _schedule;
  bool _userSeeking = false;
  Timer? _userSeekTimer;
  double _lastAppliedVersion = double.negativeInfinity;
  int? _lastMediaGen;
  int _lastReportMs = 0;
  int _lastHardSeekAtMs = 0;

  Timer? _controlLoop;
  final List<void Function()> _unsubs = [];
  StreamSubscription<bool>? _playingSub;

  final _scheduleCtrl = StreamController<SyncSchedule>.broadcast();
  final _driftCtrl = StreamController<Duration>.broadcast();

  static const int _reportMs = 1000;

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
  }) async {
    await detach();
    _player = player;
    _socket = socket;
    _canControl = canControl;

    final clock = _injectedClock ??
        (clockFactory?.call(socket) ?? SocketServerClock(socket));
    _clock = clock;
    if (clock is SocketServerClock) clock.start();

    _unsubs.add(socket.on(ServerEvent.syncSchedule, _onSchedule));
    _unsubs.add(socket.on(ServerEvent.syncHostGone, (_) => _onHostGone()));

    // Author play/pause from the player's own transitions (the Dart analog of
    // the web media element's 'play'/'pause' events wired to request*).
    _playingSub = player.playing.listen(_onPlayingChanged);

    // Ask the server for the current timeline once we're listening (avoids the
    // race where a pushed schedule arrives before we subscribed).
    socket.emit(ClientEvent.syncHello);

    _controlLoop = Timer.periodic(
        const Duration(milliseconds: controlMs), (_) => _tick());
  }

  @override
  Future<void> detach() async {
    _controlLoop?.cancel();
    _controlLoop = null;
    for (final u in _unsubs) {
      u();
    }
    _unsubs.clear();
    await _playingSub?.cancel();
    _playingSub = null;
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
    _player = null;
    _socket = null;
    _schedule = null;
    _lastAppliedVersion = double.negativeInfinity;
    _lastMediaGen = null;
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
  double _serverNow() => _clock?.serverNow() ?? _nowMs();
  bool _clockReady() => _clock?.ready ?? false;

  void _notifyUserSeeking() {
    _userSeeking = true;
    _userSeekTimer?.cancel();
    _userSeekTimer =
        Timer(const Duration(seconds: 3), () => _userSeeking = false);
  }

  // ── Incoming server schedule ─────────────────────────────────────────────
  void _onSchedule(dynamic data) {
    if (data is! Map) return;
    final s = SyncSchedule.fromJson(Map<String, dynamic>.from(data));

    // Reset the version baseline on a media-generation change (new media /
    // back-to-lobby); schedule.version keeps climbing across generations
    // within one party session, it does not restart.
    final gen = s.mediaGeneration;
    if (gen != _lastMediaGen) {
      _lastMediaGen = gen;
      _lastAppliedVersion = double.negativeInfinity;
    }
    // Drop a stale/duplicate/out-of-order schedule — only ever move forward.
    if (s.version <= _lastAppliedVersion) return;
    _lastAppliedVersion = s.version.toDouble();

    _schedule = s;
    _userSeeking = false;
    _userSeekTimer?.cancel();
    _scheduleCtrl.add(s);

    _kickHostPlay();
  }

  void _onHostGone() {
    final p = _player;
    if (p != null) {
      _markApplying();
      p.pause();
    }
  }

  // ── Host authoring from the player's own play/pause transitions ──────────
  void _onPlayingChanged(bool playing) {
    if (!_canControl) return;
    if (_applying > 0) return; // our own applied change — don't echo it back
    final phase = _schedule?.phase;
    final posTicks = (_player?.positionNow.inMilliseconds ?? 0) * ticksPerMs;
    if (playing && phase != 'playing') {
      _emitPlay(posTicks);
    } else if (!playing && phase == 'playing') {
      _emitPause(posTicks);
    }
  }

  // Idempotently (re)start a hopping host's own player. decideSyncAction returns
  // null for a hopping host, so this is the only thing that honors a 'playing'
  // schedule which arrived before playback started (e.g. party:selectMedia
  // authors an immediately-playing schedule so muted guests can autoplay).
  void _kickHostPlay() {
    final p = _player;
    if (p == null) return;
    if (!(_isHost &&
        _mode != 'dragging' &&
        _schedule?.phase == 'playing' &&
        !p.isPlayingNow)) {
      return;
    }
    p.play();
  }

  // ── Control loop (200ms), port of the useSyncPlay setInterval ────────────
  void _tick() {
    final p = _player;
    final s = _schedule;
    if (p == null || s == null) return;
    // A locally-authored command is in flight and hasn't round-tripped yet —
    // scheduleRef is still stale. Skip so our own change isn't fought.
    if (_applying > 0) return;

    _kickHostPlay();

    final intent = decideSyncAction(
      schedule: s,
      serverNowMs: _serverNow,
      clockReady: _clockReady,
      currentTime: p.positionNow.inMilliseconds / 1000.0,
      paused: !p.isPlayingNow,
      isHost: _isHost,
      mode: _mode,
      userSeeking: _userSeeking,
      suppressHardSeek: _nowMs() - _lastHardSeekAtMs < hardSeekCooldownMs,
    );
    if (intent == null) return;

    // Guest hopping hard catch-up. On non-HLS media_kit this is a guarded
    // seek(+resume); the cooldown prevents re-entry from stale drift.
    if (intent.hardSeek && !_isHost && _mode == 'hopping') {
      _lastHardSeekAtMs = _nowMs().toInt();
      _hardSeek(p, intent);
      return;
    }

    // Guest positioned while the timeline is paused/stalled → seek onto the
    // frozen frame, never resume.
    if (intent.pausedSeek && !_isHost) {
      if (intent.seekToSec != null) {
        _markApplying();
        p.seek(_sec(intent.seekToSec!));
      }
      if (intent.pause && p.isPlayingNow) {
        _markApplying();
        p.pause();
      }
      return;
    }

    if (intent.seekToSec != null) {
      _markApplying();
      p.seek(_sec(intent.seekToSec!));
    }
    if (intent.rate != null) p.setRate(intent.rate!);
    if (intent.play) {
      _markApplying();
      p.play();
    }
    if (intent.pause && p.isPlayingNow) {
      _markApplying();
      p.pause();
    }

    // Drift telemetry — guests only (a hopping host returned null above).
    if (!_isHost && intent.drift != null) {
      _driftCtrl.add(_sec(intent.drift!));
      final now = _nowMs();
      if (now - _lastReportMs >= _reportMs) {
        _lastReportMs = now.toInt();
        _socket?.emit(ClientEvent.syncReport, {
          'position': p.positionNow.inMilliseconds / 1000.0,
          'drift': intent.drift,
          'rate': intent.rate ?? 1,
        });
      }
    }
  }

  void _hardSeek(PlayerController p, SyncIntent intent) {
    _markApplying();
    if (intent.seekToSec != null) p.seek(_sec(intent.seekToSec!));
    p.setRate(1);
    if (_schedule?.phase == 'playing') {
      _markApplying();
      p.play();
    }
  }

  Duration _sec(double s) => Duration(milliseconds: (s * 1000).round());

  // ── canControl gate ──────────────────────────────────────────────────────
  @override
  bool get canControl => _canControl;
  @override
  set canControl(bool value) => _canControl = value;

  /// Host toggles hopping ↔ dragging (E5.2 wires party:setSyncMode). Kept off
  /// the frozen interface; the engine reads it in the control loop.
  set syncMode(String mode) => _mode = mode == 'dragging' ? 'dragging' : 'hopping';
  String get syncMode => _mode;

  // ── Local user intents (only take effect while canControl) ───────────────
  void _emitPlay(int positionTicks) {
    _socket?.emit(ClientEvent.syncPlay,
        {'positionTicks': positionTicks, 't0': _serverNow()});
  }

  void _emitPause(int positionTicks) {
    _socket?.emit(ClientEvent.syncPause, {'positionTicks': positionTicks});
  }

  @override
  Future<void> requestPlay() async {
    if (_applying > 0 || !_canControl) return;
    _emitPlay((_player?.positionNow.inMilliseconds ?? 0) * ticksPerMs);
  }

  @override
  Future<void> requestPause() async {
    if (_applying > 0 || !_canControl) return;
    _emitPause((_player?.positionNow.inMilliseconds ?? 0) * ticksPerMs);
  }

  @override
  Future<void> requestSeek(Duration position) async {
    if (_applying > 0 || !_canControl) return;
    _notifyUserSeeking();
    _socket?.emit(ClientEvent.syncSeek, {
      'positionTicks': position.inMilliseconds * ticksPerMs,
      't0': _serverNow(),
    });
  }

  @override
  SyncSchedule get currentSchedule => _schedule ?? const SyncSchedule();

  @override
  Stream<SyncSchedule> get scheduleStream => _scheduleCtrl.stream;

  @override
  Stream<Duration> get drift => _driftCtrl.stream;
}
