import 'dart:async';

/// One best-effort warm-up: a stable [key] naming what it warms, and the work.
typedef WarmTask = ({String key, Future<void> Function() run});

/// A bounded, replaceable queue of best-effort warm-ups.
///
/// Prefetching has one hard requirement beyond doing the work: it must never
/// compete with what the user is actually looking at. Two rules carry that, and
/// both live here rather than being reinvented by each prefetcher.
///
/// * **Bounded concurrency.** At most [maxConcurrent] warms run at once, so a
///   rail forty items long cannot starve the visible items' own loads.
/// * **Replacement, not accumulation.** [replace] swaps out everything queued
///   under a slot instead of appending to it, so a fast scroll leaves a queue
///   the size of one window rather than fifty stale ones stacked up. Work
///   already handed to the network cannot be recalled, which is the other
///   reason [maxConcurrent] is small: it is also the ceiling on how much stale
///   work a scroll can strand.
///
/// Slots exist because one prefetcher warms several things that move together
/// but supersede separately — a rail's posters and the stage backdrop both
/// follow focus, yet a new poster window must not cancel the backdrop window.
///
/// Failures are swallowed. A warm that fails is a non-event: whatever it was
/// warming simply loads normally when it is really needed.
class WarmQueue {
  WarmQueue({this.maxConcurrent = 2, this.recentLimit = 512})
    : assert(maxConcurrent > 0);

  /// How many warms may be in flight at once.
  final int maxConcurrent;

  /// How many finished keys are remembered, so a rail scrolled back and forth
  /// does not re-warm what it just warmed. Bounded on purpose: this is a hint
  /// that saves a round trip, not a second cache.
  final int recentLimit;

  final List<({String slot, WarmTask task})> _queue = [];
  final Set<String> _running = {};

  /// Insertion-ordered, so the oldest key is `_recent.first` to evict.
  final Set<String> _recent = {};

  Completer<void>? _idle;
  var _disposed = false;

  /// Warms running right now — never above [maxConcurrent].
  int get inFlight => _running.length;

  /// Warms accepted but not started.
  int get pending => _queue.length;

  /// Whether [key] was warmed (or failed) recently enough that asking again
  /// would be wasted work.
  bool warmed(String key) => _recent.contains(key);

  /// Replace everything queued under [slot] with [tasks], skipping whatever is
  /// already running or recently done.
  void replace(String slot, Iterable<WarmTask> tasks) {
    if (_disposed) return;
    _queue.removeWhere((entry) => entry.slot == slot);
    for (final task in tasks) {
      if (_running.contains(task.key) || _recent.contains(task.key)) continue;
      if (_queue.any((entry) => entry.task.key == task.key)) continue;
      _queue.add((slot: slot, task: task));
    }
    _pump();
  }

  /// Drop what is queued under [slot], leaving anything already in flight to
  /// finish.
  void clear(String slot) {
    _queue.removeWhere((entry) => entry.slot == slot);
    _signalIdle();
  }

  /// Completes once nothing is queued or in flight. For callers that need to
  /// wait a warm out before measuring what it left behind.
  Future<void> settle() {
    if (_queue.isEmpty && _running.isEmpty) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// Stop accepting and starting work. In-flight warms are left to finish —
  /// their results still land in the caches they were filling.
  void dispose() {
    _disposed = true;
    _queue.clear();
    _signalIdle();
  }

  void _pump() {
    while (!_disposed && _running.length < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeAt(0).task;
      _running.add(task.key);
      unawaited(_run(task));
    }
    _signalIdle();
  }

  Future<void> _run(WarmTask task) async {
    try {
      await task.run();
    } catch (_) {
      // Best-effort by construction: a warm that throws is not an error
      // surface. Whatever it was warming loads normally on demand.
    } finally {
      _running.remove(task.key);
      _remember(task.key);
      _pump();
    }
  }

  void _remember(String key) {
    _recent.remove(key);
    _recent.add(key);
    while (_recent.length > recentLimit) {
      _recent.remove(_recent.first);
    }
  }

  void _signalIdle() {
    if (_queue.isNotEmpty || _running.isNotEmpty) return;
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }
}
