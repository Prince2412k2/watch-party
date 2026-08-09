import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/cache_fill_controller.dart';
import '../data/api_client.dart';
import '../models/models.dart';
import 'offline_provider.dart';
import 'providers.dart';

/// Metadata captured at [DownloadsNotifier.start] time — a [FillProgress]
/// carries only bytes/state, not the title-level info the UI (and, on
/// completion, the offline manifest) needs.
class _Meta {
  const _Meta({required this.title, this.posterTag, this.runTimeTicks});
  final String title;
  final String? posterTag;
  final int? runTimeTicks;
}

/// In-flight downloads (PLAN §3.8 / E8.1), now backed by [CacheFillController]
/// (Phase 3b-wiring) instead of `background_downloader` — "download" is just
/// proactively filling the same on-device cache playback already streams
/// through, so a title is watchable mid-download and offline the moment its
/// cache entry is complete. Each tracked item listens to
/// `CacheFillController.progressFor(itemId)` and maps its [FillProgress] onto
/// the [DownloadRecord] shape the existing UI (`DownloadButton`,
/// `DownloadsScreen`) already reads.
class DownloadsNotifier extends StateNotifier<List<DownloadRecord>> {
  DownloadsNotifier(
    this._fillController,
    this._offlineNotifier, {
    Duration Function(int attempt)? backoff,
  })  : _backoff = backoff ?? retryDelay,
        super(const []);

  /// Injectable so a test can exercise the retry without spending the real
  /// first backoff. Waiting two wall-clock seconds made the test pass alone and
  /// fail under load, which is worse than not testing it.
  final Duration Function(int attempt) _backoff;

  final CacheFillController _fillController;
  final OfflineNotifier _offlineNotifier;

  final Map<String, _Meta> _meta = {};
  final Map<String, VoidCallback> _listeners = {};

  /// Retries already spent per item, and the timers waiting to spend the next.
  ///
  /// A download failing is overwhelmingly a network blip — the link dropped,
  /// the server hiccuped, the laptop lid closed. Every one of those used to
  /// leave a dead row wearing a Retry button, so an overnight download of six
  /// titles came back in the morning with five failures that a single tap each
  /// would have fixed. The machine can press that button.
  final Map<String, int> _attempts = {};
  final Map<String, Timer> _retryTimers = {};

  /// Give up after this many. Past it the failure is not a blip — the file is
  /// gone from the server, the disk is full, the token is refused — and
  /// retrying forever would hide a real problem behind a spinner.
  static const int maxAutoRetries = 5;

  /// 2s, 4s, 8s, 16s, 32s. Backed off so a server that is down does not take a
  /// hammering from every client that wanted a file from it.
  static Duration retryDelay(int attempt) =>
      Duration(seconds: 2 << attempt.clamp(0, 4));

  void upsert(DownloadRecord record) {
    state = [
      ...state.where((r) => r.itemId != record.itemId),
      record,
    ];
  }

  void remove(String itemId) {
    final listener = _listeners.remove(itemId);
    if (listener != null) {
      _fillController.progressFor(itemId).removeListener(listener);
    }
    _retryTimers.remove(itemId)?.cancel();
    _attempts.remove(itemId);
    state = state.where((r) => r.itemId != itemId).toList();
  }

  void clear() => state = const [];

  /// Starts (or restarts) filling [itemId]'s cache. `api` is accepted for
  /// call-site compatibility with the previous background_downloader-backed
  /// signature but unused — [CacheFillController]/`MediaCacheProxy` mint their
  /// own signed URLs internally.
  Future<DownloadRecord> start({
    ApiClient? api,
    required String itemId,
    required String title,
    String? posterTag,
    int? runTimeTicks,
    String? container,
  }) async {
    _meta[itemId] = _Meta(title: title, posterTag: posterTag, runTimeTicks: runTimeTicks);
    // A hand-started download is a fresh intent: whatever the last attempt
    // spent, this one starts its retry budget over.
    _attempts.remove(itemId);
    _retryTimers.remove(itemId)?.cancel();
    _attachListener(itemId);

    unawaited(_runFill(() => _fillController.start(itemId), itemId));

    final record = _recordFor(itemId, _fillController.progressFor(itemId).value);
    upsert(record);
    return record;
  }

  Future<void> pause(String itemId) async => _fillController.pause(itemId);

  /// `api` is accepted for call-site compatibility; unused (see [start]).
  Future<void> resume(String itemId, {ApiClient? api}) async {
    _attachListener(itemId);
    await _runFill(() => _fillController.resume(itemId), itemId);
  }

  /// Runs a fill's [begin] (start/resume) so a failure *before* the fill loop
  /// gets going still lands in the UI. Everything the loop itself hits reaches
  /// the record through `FillProgress.state`, but a throw out of the opening
  /// steps (opening the cache entry, probing the total length, minting a signed
  /// URL) escaped the `unawaited` call as an unhandled async error and left the
  /// record sitting at "enqueued" forever, with no way to retry it.
  Future<void> _runFill(Future<void> Function() begin, String itemId) async {
    try {
      await begin();
    } catch (_) {
      if (!mounted) return;
      upsert(_recordFor(
        itemId,
        _fillController
            .progressFor(itemId)
            .value
            .copyWith(state: FillState.error),
      ));
    }
  }

  Future<void> cancel(String itemId) async {
    _fillController.cancel(itemId);
    remove(itemId);
  }

  void _attachListener(String itemId) {
    if (_listeners.containsKey(itemId)) return;
    final listenable = _fillController.progressFor(itemId);
    void listener() => _onProgress(itemId, listenable.value);
    listenable.addListener(listener);
    _listeners[itemId] = listener;
  }

  void _onProgress(String itemId, FillProgress progress) {
    upsert(_recordFor(itemId, progress));
    if (progress.state == FillState.complete) {
      unawaited(_onComplete(itemId));
      return;
    }
    if (progress.state == FillState.error) _scheduleRetry(itemId);
  }

  /// Queue another attempt after a backoff, unless the budget is spent.
  ///
  /// A fill resumes from the bytes already on disk, so a retry costs only what
  /// is left — this is not re-downloading the film five times.
  void _scheduleRetry(String itemId) {
    if (_retryTimers.containsKey(itemId)) return; // one in flight already
    final spent = _attempts[itemId] ?? 0;
    if (spent >= maxAutoRetries) return;
    _attempts[itemId] = spent + 1;
    _retryTimers[itemId] = Timer(_backoff(spent), () {
      _retryTimers.remove(itemId);
      if (!mounted) return;
      // Cancelled or removed while the timer was pending — a retry now would
      // resurrect a download the user got rid of.
      if (!state.any((r) => r.itemId == itemId)) return;
      unawaited(_runFill(() => _fillController.resume(itemId), itemId));
    });
  }

  /// How many automatic attempts [itemId] has spent, for the UI to say so.
  int attemptsFor(String itemId) => _attempts[itemId] ?? 0;

  /// True when the retries are used up and the row genuinely needs a human.
  bool exhausted(String itemId) => (_attempts[itemId] ?? 0) >= maxAutoRetries;

  Future<void> _onComplete(String itemId) async {
    final meta = _meta[itemId];
    await _offlineNotifier.markComplete(
      itemId: itemId,
      title: meta?.title ?? itemId,
      posterTag: meta?.posterTag,
      runTimeTicks: meta?.runTimeTicks ?? 0,
    );
    // The manifest write is an await, and this whole method runs unawaited off
    // a progress callback — so the notifier can be disposed (logout teardown,
    // the container going away) between a fill finishing and this line. Writing
    // `state` then throws "Tried to use DownloadsNotifier after dispose" out of
    // a future nobody is holding. The offline record is already persisted
    // above; there is simply no longer any in-flight list to take it out of.
    if (!mounted) return;
    remove(itemId);
  }

  DownloadRecord _recordFor(String itemId, FillProgress progress) {
    final meta = _meta[itemId];
    final total = progress.totalBytes ?? 0;
    return DownloadRecord(
      itemId: itemId,
      title: meta?.title ?? itemId,
      taskId: itemId,
      status: statusForFillState(progress.state),
      progress: progress.fraction ?? 0,
      bytesDownloaded: progress.cachedBytes,
      totalBytes: total,
      posterTag: meta?.posterTag,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  void dispose() {
    for (final entry in _listeners.entries) {
      _fillController.progressFor(entry.key).removeListener(entry.value);
    }
    for (final t in _retryTimers.values) {
      t.cancel();
    }
    _retryTimers.clear();
    super.dispose();
  }
}

/// Maps [FillProgress.state] onto the [DownloadStatus] the existing
/// download UI already switches on. Top-level and pure so it's covered by a
/// focused unit test without any provider wiring.
DownloadStatus statusForFillState(FillState state) => switch (state) {
      FillState.idle => DownloadStatus.enqueued,
      FillState.running => DownloadStatus.running,
      FillState.paused => DownloadStatus.paused,
      FillState.complete => DownloadStatus.complete,
      FillState.error => DownloadStatus.failed,
      FillState.cancelled => DownloadStatus.canceled,
    };

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadRecord>>(
        (ref) => DownloadsNotifier(
              ref.watch(cacheFillControllerProvider),
              ref.watch(offlineProvider.notifier),
            ));
