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
  DownloadsNotifier(this._fillController, this._offlineNotifier)
      : super(const []);

  final CacheFillController _fillController;
  final OfflineNotifier _offlineNotifier;

  final Map<String, _Meta> _meta = {};
  final Map<String, VoidCallback> _listeners = {};

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
    _attachListener(itemId);

    unawaited(_fillController.start(itemId));

    final record = _recordFor(itemId, _fillController.progressFor(itemId).value);
    upsert(record);
    return record;
  }

  Future<void> pause(String itemId) async => _fillController.pause(itemId);

  /// `api` is accepted for call-site compatibility; unused (see [start]).
  Future<void> resume(String itemId, {ApiClient? api}) async {
    _attachListener(itemId);
    await _fillController.resume(itemId);
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
    }
  }

  Future<void> _onComplete(String itemId) async {
    final meta = _meta[itemId];
    await _offlineNotifier.markComplete(
      itemId: itemId,
      title: meta?.title ?? itemId,
      posterTag: meta?.posterTag,
      runTimeTicks: meta?.runTimeTicks ?? 0,
    );
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
