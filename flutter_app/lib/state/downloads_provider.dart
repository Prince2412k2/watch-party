import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

/// Downloads + offline library (PLAN §3.8). Phase 0 holds in-memory lists; E8
/// wires background_downloader (resumable, restart-surviving) + offline records.
class DownloadsNotifier extends StateNotifier<List<DownloadRecord>> {
  DownloadsNotifier() : super(const []);

  void upsert(DownloadRecord record) {
    state = [
      ...state.where((r) => r.taskId != record.taskId),
      record,
    ];
  }

  void remove(String taskId) =>
      state = state.where((r) => r.taskId != taskId).toList();

  void clear() => state = const [];
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadRecord>>(
        (ref) => DownloadsNotifier());

/// The offline (fully-downloaded) library.
class OfflineNotifier extends StateNotifier<List<OfflineRecord>> {
  OfflineNotifier() : super(const []);

  void upsert(OfflineRecord record) {
    state = [
      ...state.where((r) => r.itemId != record.itemId),
      record,
    ];
  }

  void remove(String itemId) =>
      state = state.where((r) => r.itemId != itemId).toList();
}

final offlineProvider =
    StateNotifierProvider<OfflineNotifier, List<OfflineRecord>>(
        (ref) => OfflineNotifier());
