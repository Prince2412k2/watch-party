import '../analog/browse_core.dart';
import 'artwork_cache.dart';
import 'warm_queue.dart';

/// Warms artwork bytes for the items a rail is about to slide into view.
///
/// [ArtworkCache] already solves storage — a memory LRU, disk eviction,
/// stale-while-revalidate delivery, in-flight dedup. What it does not do is
/// decide *when* to fetch: every byte it holds got there because something on
/// screen asked for it, which means the first sight of any poster still costs
/// a round trip. This is the other half. It asks for artwork the user has not
/// reached yet, so by the time a card arrives the bytes are already decoded in
/// memory and `AuthedNetworkImage` paints on its first frame.
///
/// Which items those are is not a judgement call made here: it is
/// `railWindow(...).prefetch` from `lib/analog/browse_core.dart`, the window
/// the React client computes identically from the same inputs. "Snappy" is
/// therefore a contract both clients hold rather than each one guessing its own
/// lookahead.
class ArtworkPrefetcher {
  ArtworkPrefetcher(this._cache, {int maxConcurrent = 2})
    : _queue = WarmQueue(maxConcurrent: maxConcurrent);

  final ArtworkCache _cache;
  final WarmQueue _queue;

  /// Warms in flight right now. Bounded by the queue's concurrency cap, which
  /// is what stops a warm from starving the visible items' own loads.
  int get inFlight => _queue.inFlight;

  /// Warms accepted but not started.
  int get pending => _queue.pending;

  /// Completes when the queue has drained.
  Future<void> settle() => _queue.settle();

  void dispose() => _queue.dispose();

  /// Warm the artwork behind exactly `railWindow(...).prefetch`: the items past
  /// the last visible slot, plus the couple behind the cursor so scrolling back
  /// is not a stall either.
  ///
  /// [urlsFor] is asked only for those indices, and everything one index
  /// returns is queued before the next index's. The order is the shared core's
  /// own — behind the cursor first, then ahead — and is deliberately not
  /// re-sorted: the items behind were on screen a moment ago, so their bytes
  /// are normally still resident and get skipped for free.
  ///
  /// [slot] keeps independent windows from cancelling each other; see
  /// [WarmQueue].
  void warmRail({
    required String slot,
    required int total,
    required int offset,
    required int slots,
    required Iterable<String> Function(int index) urlsFor,
    int lookahead = kRailLookahead,
    int behind = kRailBehind,
  }) {
    final window = railWindow(
      RailWindowInput(
        total: total,
        offset: offset,
        slots: slots,
        lookahead: lookahead,
        behind: behind,
      ),
    );
    warm([for (final index in window.prefetch) ...urlsFor(index)], slot: slot);
  }

  /// Warm [urls], superseding whatever [slot] was warming before.
  void warm(Iterable<String> urls, {required String slot}) {
    final tasks = <WarmTask>[];
    for (final url in urls) {
      if (url.isEmpty) continue;
      // Already decoded and resident: there is nothing left to warm.
      if (_cache.peek(url) != null) continue;
      // ArtworkCache refuses a cross-origin URL outright rather than carrying
      // the session cookie off-origin, so a warm must not even ask: a queue
      // slot spent on a guaranteed StateError is a slot the real artwork
      // wanted.
      if (!_cache.isSameOrigin(url)) continue;
      tasks.add((key: url, run: () => _warm(url)));
    }
    _queue.replace(slot, tasks);
  }

  /// Take the first emission and stop.
  ///
  /// `ArtworkCache.load` is stale-while-revalidate: it yields whatever it holds
  /// locally and then re-fetches to check. That is right for something on
  /// screen and wrong for a warm — cancelling after the first event unwinds the
  /// generator before it reaches the fetch, so artwork already on disk costs a
  /// disk read and no request at all.
  Future<void> _warm(String url) async {
    await _cache.load(url).first;
  }
}
