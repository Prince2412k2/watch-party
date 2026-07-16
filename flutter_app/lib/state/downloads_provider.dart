import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../download/downloader.dart';
import '../models/models.dart';
import 'providers.dart';

/// In-flight downloads (PLAN §3.8 / E8.1). Backed by [Downloader], which
/// wraps `background_downloader` for resumable, restart-surviving downloads.
/// [init] rehydrates from the persisted task DB so a killed-and-relaunched
/// app doesn't lose track of what was downloading.
class DownloadsNotifier extends StateNotifier<List<DownloadRecord>> {
  DownloadsNotifier(this._downloader) : super(const []) {
    _sub = _downloader.recordStream.listen(upsert);
    _rehydrate();
  }

  final Downloader _downloader;
  late final StreamSubscription<DownloadRecord> _sub;

  Future<void> _rehydrate() async {
    await _downloader.init();
    state = await _downloader.activeRecords();
  }

  void upsert(DownloadRecord record) {
    state = [
      ...state.where((r) => r.taskId != record.taskId),
      record,
    ];
  }

  void remove(String taskId) =>
      state = state.where((r) => r.taskId != taskId).toList();

  void clear() => state = const [];

  Future<DownloadRecord> start({
    required ApiClient api,
    required String itemId,
    required String title,
    String? posterTag,
    int? runTimeTicks,
    String? container,
  }) async {
    final record = await _downloader.startDownload(
      api: api,
      itemId: itemId,
      title: title,
      posterTag: posterTag,
      runTimeTicks: runTimeTicks,
      container: container,
    );
    upsert(record);
    return record;
  }

  Future<void> pause(String taskId) => _downloader.pause(taskId);
  Future<void> resume(String taskId, {required ApiClient api}) =>
      _downloader.resume(taskId, api: api);
  Future<void> cancel(String taskId) async {
    await _downloader.cancel(taskId);
    remove(taskId);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadRecord>>(
        (ref) => DownloadsNotifier(ref.watch(downloaderProvider)));
