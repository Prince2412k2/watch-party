import 'dart:async';

import '../net/events.dart';
import '../net/socket_client.dart';

/// NTP-lite clock sync. Direct port of `useServerClock.js`: estimate this
/// client's offset from the server clock so every client agrees on
/// [serverNow] within a few ms. Keeps a rolling window of samples and trusts
/// the offset from the lowest-RTT one (least noise).
///
/// Split into an interface so the sync engine can be tested against a fake
/// clock without a live socket round-trip (the wire path uses `clock:ping`).
abstract class ServerClock {
  /// Server-aligned now, in epoch milliseconds.
  double serverNow();

  /// Whether the offset estimate is trustworthy yet (≥1 sample landed).
  bool get ready;
}

/// A manually-driven clock for tests / headless callers. [offsetMs] is added to
/// the injected [nowMs] source.
class ManualServerClock implements ServerClock {
  ManualServerClock({double Function()? nowMs, this.offsetMs = 0, this.ready = true})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch.toDouble());

  final double Function() _nowMs;
  double offsetMs;

  @override
  bool ready;

  @override
  double serverNow() => _nowMs() + offsetMs;
}

class _Sample {
  const _Sample(this.rtt, this.offset);
  final double rtt;
  final double offset;
}

/// Socket-backed [ServerClock] driving `clock:ping` against the backend.
/// Sampling cadence mirrors the web hook: an initial ping, a 5-shot burst at
/// 500ms, then a steady 5s drift resample. The offset used is the one from the
/// lowest-RTT sample of the last 12.
class SocketServerClock implements ServerClock {
  SocketServerClock(this._socket);

  final SocketClient _socket;
  final List<_Sample> _samples = [];
  double _offset = 0;
  bool _ready = false;
  Timer? _burst;
  Timer? _drift;
  int _burstCount = 0;
  bool _stopped = false;

  @override
  double serverNow() =>
      DateTime.now().millisecondsSinceEpoch.toDouble() + _offset;

  @override
  bool get ready => _ready;

  /// Begin sampling. Idempotent-ish: call once per attach.
  void start() {
    _stopped = false;
    _sample();
    _burstCount = 0;
    _burst = Timer.periodic(const Duration(milliseconds: 500), (t) {
      _sample();
      if (++_burstCount >= 5) t.cancel();
    });
    _drift = Timer.periodic(const Duration(seconds: 5), (_) => _sample());
  }

  void stop() {
    _stopped = true;
    _burst?.cancel();
    _drift?.cancel();
    _burst = null;
    _drift = null;
  }

  Future<void> _sample() async {
    final t1 = DateTime.now().millisecondsSinceEpoch.toDouble();
    dynamic resp;
    try {
      resp = await _socket
          .emitWithAck(ClientEvent.clockPing, t1)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return; // timeout / disconnected — skip this sample
    }
    if (_stopped) return;
    final serverTs = (resp is num) ? resp.toDouble() : null;
    if (serverTs == null) return;
    final t4 = DateTime.now().millisecondsSinceEpoch.toDouble();
    final rtt = t4 - t1;
    // add to local clock → server clock
    final offset = serverTs - (t1 + t4) / 2;
    _samples.add(_Sample(rtt, offset));
    if (_samples.length > 12) _samples.removeAt(0);
    var best = _samples.first;
    for (final s in _samples) {
      if (s.rtt < best.rtt) best = s;
    }
    _offset = best.offset;
    _ready = true;
  }
}
