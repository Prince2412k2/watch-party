import 'dart:async';

import 'package:flutter/foundation.dart';

import 'media_cache_proxy.dart';
import 'range_cache_store.dart';

/// Lifecycle of one title's proactive cache-fill ("download").
enum FillState { idle, running, paused, complete, error, cancelled }

/// A snapshot of one title's fill progress, as observed through
/// [CacheFillController.progressFor].
@immutable
class FillProgress {
  const FillProgress({
    required this.cachedBytes,
    required this.totalBytes,
    required this.state,
  });

  static const initial = FillProgress(
    cachedBytes: 0,
    totalBytes: null,
    state: FillState.idle,
  );

  final int cachedBytes;
  final int? totalBytes;
  final FillState state;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return cachedBytes / total;
  }

  FillProgress copyWith({int? cachedBytes, int? totalBytes, FillState? state}) {
    return FillProgress(
      cachedBytes: cachedBytes ?? this.cachedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      state: state ?? this.state,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FillProgress &&
      other.cachedBytes == cachedBytes &&
      other.totalBytes == totalBytes &&
      other.state == state;

  @override
  int get hashCode => Object.hash(cachedBytes, totalBytes, state);

  @override
  String toString() =>
      'FillProgress(cachedBytes: $cachedBytes, totalBytes: $totalBytes, state: $state)';
}

/// The "fetch a byte range and store it" seam a fill needs — defaults to
/// [MediaCacheProxy.fetchAndStore] but is injectable so tests can drive the
/// fill loop's control flow (pause/resume/cancel/progress) without any real
/// network or [MediaCacheProxy] at all.
typedef RangeFetcher = Future<void> Function(
  CacheEntry entry,
  int start,
  int end,
);

/// Per-itemId bookkeeping for an in-progress (or paused/finished) fill.
class _Fill {
  _Fill(this.entry, this.progress);

  final CacheEntry entry;
  final ValueNotifier<FillProgress> progress;

  /// Cooperative cancellation: checked between chunks. `true` pauses the
  /// loop after the current chunk finishes; the loop itself exits and a
  /// later [CacheFillController.resume] starts a fresh loop.
  bool pauseRequested = false;
  bool cancelRequested = false;

  /// Guards against two concurrent loops for the same itemId (e.g. a rapid
  /// resume-before-the-old-loop-noticed-pause).
  bool loopRunning = false;
}

/// Proactively fills a title's entire on-device cache — the "download"
/// engine sitting underneath (but decoupled from) the existing download
/// UI/providers. Fetches whatever [CacheEntry.missingRanges] reports missing
/// across the *whole* file, in [MediaCacheProxy._fetchChunkSize]-ish pieces,
/// sequentially, one active fill per itemId.
///
/// This class does not know about `background_downloader`, the offline
/// manifest, or any UI state — it only knows how to make one title's
/// [RangeCacheStore] entry fully present, with pausable/resumable/cancelable
/// progress. Wiring this into the existing download flow is a separate step.
class CacheFillController {
  CacheFillController({
    required MediaCacheProxy proxy,
    int chunkSize = MediaCacheProxy.fetchChunkSize,
  })  : _proxy = proxy,
        _chunkSize = chunkSize;

  final MediaCacheProxy _proxy;
  final int _chunkSize;

  final Map<String, _Fill> _fills = {};

  /// Progress notifiers for itemIds that have never had [start]/[resume]
  /// called yet — [progressFor] hands these out so a UI can attach a
  /// listener before a fill exists, then [start] adopts the same notifier
  /// instead of creating a second one.
  final Map<String, ValueNotifier<FillProgress>> _idleProgress = {};

  /// Progress for [itemId] as a [ValueListenable] — safe to call before any
  /// fill has started (returns an idle, zero-byte snapshot that later
  /// updates in place once [start] runs).
  ValueListenable<FillProgress> progressFor(String itemId) {
    final fill = _fills[itemId];
    if (fill != null) return fill.progress;
    return _idleProgress.putIfAbsent(
      itemId,
      () => ValueNotifier(FillProgress.initial),
    );
  }

  int _cachedBytesOf(CacheEntry entry) =>
      entry.rangeSet.intervals.fold<int>(0, (sum, iv) => sum + (iv[1] - iv[0]));

  /// Starts (or resumes, if already paused) filling [itemId]'s entire cache.
  /// Idempotent while already running.
  Future<void> start(String itemId, {RangeFetcher? fetcher}) async {
    final entry = await _openEntry(itemId);
    final fill = _fills.putIfAbsent(itemId, () {
      final notifier = _idleProgress.remove(itemId) ??
          ValueNotifier(FillProgress.initial);
      notifier.value = notifier.value.copyWith(
        cachedBytes: _cachedBytesOf(entry),
        totalBytes: entry.totalLength,
      );
      return _Fill(entry, notifier);
    });
    if (fill.loopRunning) return;

    fill.pauseRequested = false;
    fill.cancelRequested = false;

    final total = await _proxy.ensureTotalLength(itemId, entry);
    if (total == null) {
      fill.progress.value = fill.progress.value.copyWith(state: FillState.error);
      return;
    }

    await _runLoop(itemId, fill, total, fetcher ?? _defaultFetcher(itemId));
  }

  RangeFetcher _defaultFetcher(String itemId) =>
      (entry, start, end) => _proxy.fetchAndStore(itemId, entry, start, end);

  Future<CacheEntry> _openEntry(String itemId) => _proxy.openEntry(itemId);

  Future<void> _runLoop(
    String itemId,
    _Fill fill,
    int total,
    RangeFetcher fetch,
  ) async {
    fill.loopRunning = true;
    fill.progress.value = fill.progress.value.copyWith(
      state: FillState.running,
      totalBytes: total,
    );

    try {
      while (true) {
        if (fill.cancelRequested) {
          fill.progress.value = fill.progress.value.copyWith(state: FillState.cancelled);
          return;
        }
        if (fill.pauseRequested) {
          fill.progress.value = fill.progress.value.copyWith(state: FillState.paused);
          return;
        }

        final gaps = fill.entry.missingRanges(0, total);
        if (gaps.isEmpty) {
          await _onComplete(itemId, fill);
          return;
        }

        final gap = gaps.first;
        final chunkEnd =
            (gap.start + _chunkSize) > gap.end ? gap.end : gap.start + _chunkSize;

        try {
          await fetch(fill.entry, gap.start, chunkEnd);
        } catch (_) {
          fill.progress.value = fill.progress.value.copyWith(state: FillState.error);
          return;
        }

        fill.progress.value = fill.progress.value.copyWith(
          cachedBytes: _cachedBytesOf(fill.entry),
        );
      }
    } finally {
      fill.loopRunning = false;
    }
  }

  Future<void> _onComplete(String itemId, _Fill fill) async {
    fill.progress.value = fill.progress.value.copyWith(
      state: FillState.complete,
      cachedBytes: _cachedBytesOf(fill.entry),
    );
    await _proxy.touch(itemId);
    await _proxy.evict(protected: _activeFillItemIds());
  }

  Set<String> _activeFillItemIds() => _fills.entries
      .where((e) => e.value.progress.value.state != FillState.cancelled)
      .map((e) => e.key)
      .toSet();

  /// Requests the fill loop for [itemId] stop after its current chunk.
  /// No-op if there's no active fill.
  void pause(String itemId) {
    _fills[itemId]?.pauseRequested = true;
  }

  /// Resumes a paused (or errored) fill for [itemId] from wherever
  /// [CacheEntry.missingRanges] says it left off. No-op if already running.
  Future<void> resume(String itemId, {RangeFetcher? fetcher}) async {
    final fill = _fills[itemId];
    if (fill == null) {
      await start(itemId, fetcher: fetcher);
      return;
    }
    if (fill.loopRunning) return;

    fill.pauseRequested = false;
    fill.cancelRequested = false;

    final total = await _proxy.ensureTotalLength(itemId, fill.entry);
    if (total == null) {
      fill.progress.value = fill.progress.value.copyWith(state: FillState.error);
      return;
    }

    await _runLoop(itemId, fill, total, fetcher ?? _defaultFetcher(itemId));
  }

  /// Stops filling [itemId] (after the current chunk) and marks it
  /// cancelled. Already-cached bytes are left in place.
  void cancel(String itemId) {
    final fill = _fills[itemId];
    if (fill == null) return;
    fill.cancelRequested = true;
    if (!fill.loopRunning) {
      fill.progress.value = fill.progress.value.copyWith(state: FillState.cancelled);
    }
  }
}
