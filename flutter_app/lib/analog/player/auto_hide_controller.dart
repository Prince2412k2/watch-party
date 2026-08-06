// One clock for control auto-hide.
//
// There used to be two: the player chrome ran its own idle Timer, and the party
// screen ran a second one whenever it passed `PlayerChrome.visible` — with the
// hide rule, the "stay up while chat is open" exception and the "stay up while
// paused" exception written out separately in each. This wraps the shared
// analog/player_core.dart state machine in a real Timer so both callers get the
// same rule from the same code.
//
// player_core owns every transition. This class only decides WHEN to sample it.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ui/analog_tokens.dart';
import '../player_core.dart' as core;

export '../player_core.dart' show PlayerInputKind;

class AnalogAutoHideController extends ChangeNotifier {
  AnalogAutoHideController({bool playing = true}) {
    _state = core.AutoHideState.initial(playing: playing);
    // Arm immediately: chrome that mounts over running playback and is never
    // touched still has to hide.
    _arm();
  }

  static final int _intervalMs = AnalogTiming.chromeAutoHideMs.inMilliseconds;

  /// A LOGICAL clock, advanced only by this controller's own timer firing.
  ///
  /// Wall time is deliberately never consulted. The only interval that matters
  /// is the one the timer measures, so the arithmetic player_core does is
  /// exact, a suspended machine cannot produce a bogus elapsed, and the rule
  /// stays drivable from `tester.pump` under fake async.
  int _nowMs = 0;

  late core.AutoHideState _state;
  Timer? _timer;

  bool get visible => _state.visible;

  /// The reasons the chrome is currently pinned open. Exposed for tests and for
  /// callers that need to know whether a hold is already taken.
  List<String> get holds => List.unmodifiable(_state.holds);

  /// Any relevant input reveals the chrome and restarts the three second timer.
  void noteInput(core.PlayerInputKind kind) =>
      _apply(core.noteInput(_state, kind, _nowMs));

  /// Pin the chrome open for as long as [reason] is held — scrubbing, an open
  /// settings stack, chat. Idempotent.
  void hold(String reason) => _apply(core.holdControls(_state, reason));

  /// Releasing grants the FULL three seconds again rather than hiding instantly,
  /// so closing a menu does not make the chrome disappear under the cursor.
  void release(String reason) =>
      _apply(core.releaseControls(_state, reason, _nowMs));

  void setPlaying(bool playing) =>
      _apply(core.setPlaying(_state, playing, _nowMs));

  void _apply(core.AutoHideState next) {
    final wasVisible = _state.visible;
    _state = core.tickAutoHide(next, _nowMs);
    _arm();
    if (_state.visible != wasVisible) notifyListeners();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (!_state.visible) return;
    if (_state.holds.isNotEmpty || !_state.playing) return;
    final remaining = _intervalMs - (_nowMs - _state.lastInputAtMs);
    _timer = Timer(
      Duration(milliseconds: remaining < 0 ? 0 : remaining),
      _onTimeout,
    );
  }

  void _onTimeout() {
    _timer = null;
    _nowMs = _state.lastInputAtMs + _intervalMs;
    _state = core.tickAutoHide(_state, _nowMs);
    if (_state.visible) {
      // A hold was taken while the timer was in flight.
      _arm();
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
