import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'livekit_provider.dart';
import 'party_provider.dart';
import 'providers.dart';

/// Whether the party connection is currently lost, and what is being done
/// about it.
class PartyConnection {
  const PartyConnection({
    this.lost = false,
    this.attempt = 0,
    this.minimised = false,
  });

  /// The socket is down while a party is (or was) open. Not merely "the socket
  /// is down": with no party there is nothing to be cut off from.
  final bool lost;

  /// Retries made since the drop. Shown so a long outage reads as effort
  /// rather than as a spinner that might have given up.
  final int attempt;

  /// The reconnect surface has been sent to the corner with Back. The retrying
  /// itself is unaffected — this is only where it is drawn.
  final bool minimised;

  PartyConnection copyWith({bool? lost, int? attempt, bool? minimised}) =>
      PartyConnection(
        lost: lost ?? this.lost,
        attempt: attempt ?? this.attempt,
        minimised: minimised ?? this.minimised,
      );
}

/// How long to wait before the nth retry: 1s, 2s, 4s, 8s, then every 15s.
///
/// Fast at the start because most drops are a blip and the first retry usually
/// wins; capped because after half a minute the cause is not something a
/// tighter loop fixes, and hammering a server that is down is how a brief
/// outage becomes a longer one.
Duration partyRetryBackoff(int attempt) {
  if (attempt <= 0) return const Duration(seconds: 1);
  final seconds = math.min(15, 1 << math.min(attempt, 4));
  return Duration(seconds: seconds);
}

/// Keeps a party connected without anyone pressing anything.
///
/// Two connections can drop, and they are not the same failure:
///
///   * **The socket** carries party state, chat and playback sync. Losing it
///     cuts you out of the room, so it raises the reconnect surface and retries
///     until it is back.
///   * **LiveKit** carries camera and mic. Losing it costs you A/V and nothing
///     else — the film plays on, in sync — so it retries QUIETLY. Throwing a
///     full-window page over a film someone is still watching, because a camera
///     blipped, would be worse than the bug this fixes.
///
/// Neither needed a person before this: the A/V one had a Reconnect button in
/// the party panel and the socket one had nothing at all, so a drop was
/// something you noticed by realising nobody had spoken for a while.
class PartyConnectionNotifier extends StateNotifier<PartyConnection> {
  PartyConnectionNotifier(this._ref) : super(const PartyConnection());

  final Ref _ref;

  Timer? _retry;
  Timer? _avRetry;
  int _avAttempt = 0;
  bool _started = false;

  /// Begin watching both connections. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    _ref.listen<AsyncValue<bool>>(
      socketConnectedProvider,
      (_, connected) => _onSocket(connected.valueOrNull ?? false),
    );
    // Leaving the party — by any route, including the one on this surface —
    // ends the retrying with it. Otherwise a "leave" that happened while
    // offline would keep dialling a room nobody is in.
    _ref.listen<PartyState?>(partyProvider, (_, party) {
      if (party == null) _settle();
    });
    _ref.listen<LiveKitState>(
      livekitProvider,
      (_, live) => _onLiveKit(live),
    );
  }

  // ── The socket: the one that raises the surface ────────────────────────────

  void _onSocket(bool connected) {
    if (connected) {
      if (state.lost) _settle();
      return;
    }
    // Being in a party is the entire condition. An earlier version also
    // required having SEEN the socket come up, which sounds like the same
    // thing and is not: joining while already connected emits no further
    // "connected" event, so that flag never armed on the ordinary path — app
    // connects, then you join — and every drop after it was ignored. Holding a
    // party at all means the socket was up, because joining needed it.
    if (_ref.read(partyProvider) == null || state.lost) return;
    state = const PartyConnection(lost: true);
    _scheduleRetry();
  }

  void _settle() {
    _retry?.cancel();
    _retry = null;
    if (state.lost || state.minimised) state = const PartyConnection();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(partyRetryBackoff(state.attempt), _attempt);
  }

  Future<void> _attempt() async {
    if (!mounted || !state.lost) return;
    state = state.copyWith(attempt: state.attempt + 1);
    try {
      await _ref.read(partyProvider.notifier).retryConnection();
    } catch (_) {
      // Expected while whatever broke is still broken. The schedule below is
      // what makes this a retry rather than a one-shot.
    }
    if (!mounted || !state.lost) return;
    // Not conditional on the attempt failing: a connect that "succeeded"
    // without the socket coming up must still be followed by another, or a
    // half-open link would leave this waiting forever on a timer that has
    // already fired.
    _scheduleRetry();
  }

  // ── LiveKit: retried without saying anything ───────────────────────────────

  void _onLiveKit(LiveKitState live) {
    final inParty = _ref.read(partyProvider) != null;
    if (!inParty || live.connected) {
      _avRetry?.cancel();
      _avRetry = null;
      _avAttempt = 0;
      return;
    }
    if (live.connecting || _avRetry != null) return;
    _avRetry = Timer(partyRetryBackoff(_avAttempt), () async {
      _avRetry = null;
      _avAttempt++;
      if (!mounted || _ref.read(partyProvider) == null) return;
      if (_ref.read(livekitProvider).connected) return;
      await _ref.read(partyProvider.notifier).reconnectAv();
      // Whatever happened, re-reading the state schedules the next attempt if
      // it is still down — the listener above does not fire for an unchanged
      // state, so the loop has to re-enter itself.
      if (mounted) _onLiveKit(_ref.read(livekitProvider));
    });
  }

  // ── What the surface can do ────────────────────────────────────────────────

  /// Send the surface to the corner. Retrying continues.
  void minimise() => state = state.copyWith(minimised: true);

  /// Bring it back to full window.
  void expand() => state = state.copyWith(minimised: false);

  /// Stop trying and leave the party — the cross in the corner.
  Future<void> stopAndLeave() async {
    _retry?.cancel();
    _retry = null;
    _avRetry?.cancel();
    _avRetry = null;
    state = const PartyConnection();
    await _ref.read(partyProvider.notifier).leave();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _avRetry?.cancel();
    super.dispose();
  }
}

final partyConnectionProvider =
    StateNotifierProvider<PartyConnectionNotifier, PartyConnection>(
      (ref) => PartyConnectionNotifier(ref),
    );
