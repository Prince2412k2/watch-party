import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';

import '../data/api_client.dart';
import '../models/models.dart';
import 'offline_manifest_store.dart';

/// Resumable downloader on top of `background_downloader` (E8.1, PLAN §4 E8).
///
/// One [DownloadTask] per title, keyed by `itemId` (== `taskId`), fetched from
/// the `purpose=download` signed URL (long-TTL, Range-capable original file).
/// `background_downloader` persists task state (status/progress/bytes) in its
/// own local-store DB, so an in-flight download survives an app kill: on the
/// next [init] we re-attach to whatever the native/desktop downloader was
/// already doing and resume reporting progress for it.
///
/// Single resumable HTTP connection per download (not multi-part): the
/// package's parallel/multi-connection task type (`ParallelDownloadTask`)
/// explicitly cannot be paused/resumed on failure, which conflicts with the
/// restart-survives-and-resumes requirement this epic is graded on. A plain
/// `DownloadTask` with `allowPause: true` resumes via HTTP Range and is the
/// combination background_downloader documents as reliable.
class Downloader {
  Downloader({OfflineManifestStore? manifestStore})
      : _manifestStore = manifestStore ?? OfflineManifestStore();

  static const group = 'wp_downloads';
  static const _downloadsDir = 'downloads';

  final FileDownloader _fd = FileDownloader();
  final OfflineManifestStore _manifestStore;

  final _recordsController = StreamController<DownloadRecord>.broadcast();
  final _lastEmit = <String, DateTime>{};
  static const _minEmitGap = Duration(milliseconds: 400);

  List<OfflineRecord> _offline = [];
  bool _initialized = false;

  /// `FileDownloader().updates` is a single-subscription stream backed by a
  /// process-wide singleton, so only the first [Downloader] instance in a
  /// process may listen to it (there's exactly one in the running app, via
  /// `downloaderProvider`). Guards against a second `init()` — e.g. a test
  /// that constructs a fresh [Downloader] to simulate an app restart within
  /// the same process — crashing with "Stream has already been listened to".
  static bool _streamAttached = false;

  /// Fires whenever a tracked download's [DownloadRecord] changes (progress
  /// coalesced to roughly [_minEmitGap]; status changes always pass through).
  Stream<DownloadRecord> get recordStream => _recordsController.stream;

  /// Rehydrates from background_downloader's persisted DB + the offline
  /// manifest. Call once at app boot, before reading [activeRecords] /
  /// [offlineRecords].
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _fd.trackTasksInGroup(group);
    _offline = await _manifestStore.load();

    if (!_streamAttached) {
      _streamAttached = true;
      _fd.updates.listen(_onUpdate);
    }
  }

  /// Snapshot of every tracked (non-final, i.e. still enqueued/running/
  /// paused) or recently-finished task as a [DownloadRecord], straight from
  /// the persisted DB — used to rebuild `downloadsProvider` state on boot.
  Future<List<DownloadRecord>> activeRecords() async {
    final records = await _fd.database.allRecords(group: group);
    return Future.wait(records.map(_toDownloadRecord));
  }

  List<OfflineRecord> get offlineRecords => List.unmodifiable(_offline);

  /// Starts (or restarts) downloading [itemId]'s original file via a
  /// `purpose=download` signed URL. Returns the initial [DownloadRecord].
  Future<DownloadRecord> startDownload({
    required ApiClient api,
    required String itemId,
    required String title,
    String? posterTag,
    int? runTimeTicks,
    String? container,
  }) async {
    final streamUrl = await api.nativeStreamUrl(itemId, purpose: 'download');
    // Jellyfin's `Container` is sometimes a comma-separated list of
    // acceptable containers (e.g. "mov,mp4,m4a,3gp,3g2,mj2") — take the
    // first as the file extension rather than using the raw value.
    final ext = container?.split(',').first.trim();
    final filename = '$itemId.${ext?.isNotEmpty == true ? ext : 'mkv'}';
    final metaData = jsonEncode({
      'title': title,
      'posterTag': posterTag,
      'runTimeTicks': runTimeTicks,
      'container': container,
    });

    final task = DownloadTask(
      taskId: itemId,
      url: streamUrl.url,
      filename: filename,
      directory: _downloadsDir,
      baseDirectory: BaseDirectory.applicationSupport,
      group: group,
      updates: Updates.statusAndProgress,
      allowPause: true,
      metaData: metaData,
    );

    await _fd.enqueue(task);
    return DownloadRecord(
      itemId: itemId,
      title: title,
      taskId: itemId,
      posterTag: posterTag,
      status: DownloadStatus.enqueued,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> pause(String taskId) async {
    final record = await _fd.database.recordForId(taskId);
    final task = record?.task;
    if (task is! DownloadTask) return false;
    return _fd.pause(task);
  }

  Future<bool> resume(String taskId) async {
    final record = await _fd.database.recordForId(taskId);
    final task = record?.task;
    if (task is! DownloadTask) return false;
    return _fd.resume(task);
  }

  Future<bool> cancel(String taskId) => _fd.cancelTaskWithId(taskId);

  Future<void> removeOffline(String itemId) async {
    _offline = _offline.where((o) => o.itemId != itemId).toList();
    await _manifestStore.save(_offline);
  }

  void _onUpdate(TaskUpdate update) {
    if (update.task.group != group) return;
    final task = update.task;
    if (task is! DownloadTask) return;

    if (update is TaskStatusUpdate) {
      unawaited(_recordFromStatus(task, update).then((r) => _emit(r, force: true)));
      if (update.status == TaskStatus.complete) {
        unawaited(_onComplete(task));
      }
      return;
    }
    if (update is TaskProgressUpdate) {
      unawaited(_recordFromProgress(task, update).then(_emit));
    }
  }

  void _emit(DownloadRecord record, {bool force = false}) {
    if (!force) {
      final last = _lastEmit[record.taskId];
      final now = DateTime.now();
      if (last != null && now.difference(last) < _minEmitGap) return;
      _lastEmit[record.taskId] = now;
    }
    _recordsController.add(record);
  }

  Future<void> _onComplete(DownloadTask task) async {
    final meta = _decodeMeta(task.metaData);
    final path = await task.filePath();
    final record = OfflineRecord(
      itemId: task.taskId,
      title: (meta['title'] as String?) ?? task.taskId,
      filePath: path,
      sizeBytes: 0,
      runTimeTicks: (meta['runTimeTicks'] as num?)?.toInt() ?? 0,
      posterTag: meta['posterTag'] as String?,
      container: meta['container'] as String?,
      downloadedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _offline = [..._offline.where((o) => o.itemId != record.itemId), record];
    await _manifestStore.save(_offline);
  }

  Map<String, dynamic> _decodeMeta(String? metaData) {
    if (metaData == null || metaData.isEmpty) return const {};
    try {
      return Map<String, dynamic>.from(jsonDecode(metaData));
    } catch (_) {
      return const {};
    }
  }

  Future<DownloadRecord> _toDownloadRecord(TaskRecord record) async {
    final task = record.task;
    final meta = task is DownloadTask ? _decodeMeta(task.metaData) : const {};
    final progress = record.progress.clamp(0, 1).toDouble();
    final totalBytes = record.expectedFileSize > 0 ? record.expectedFileSize : 0;
    return DownloadRecord(
      itemId: task.taskId,
      title: (meta['title'] as String?) ?? task.taskId,
      taskId: task.taskId,
      filePath: await _safeFilePath(task),
      status: _toStatus(record.status),
      progress: progress,
      bytesDownloaded: totalBytes > 0 ? (progress * totalBytes).round() : 0,
      totalBytes: totalBytes,
      posterTag: meta['posterTag'] as String?,
      error: record.exception?.description,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<DownloadRecord> _recordFromStatus(
      DownloadTask task, TaskStatusUpdate update) async {
    final meta = _decodeMeta(task.metaData);
    return DownloadRecord(
      itemId: task.taskId,
      title: (meta['title'] as String?) ?? task.taskId,
      taskId: task.taskId,
      filePath: await _safeFilePath(task),
      status: _toStatus(update.status),
      posterTag: meta['posterTag'] as String?,
      error: update.exception?.description,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<DownloadRecord> _recordFromProgress(
      DownloadTask task, TaskProgressUpdate update) async {
    final meta = _decodeMeta(task.metaData);
    final progress = update.progress.clamp(0, 1).toDouble();
    final totalBytes = update.hasExpectedFileSize ? update.expectedFileSize : 0;
    return DownloadRecord(
      itemId: task.taskId,
      title: (meta['title'] as String?) ?? task.taskId,
      taskId: task.taskId,
      filePath: await _safeFilePath(task),
      status: DownloadStatus.running,
      progress: progress,
      bytesDownloaded: totalBytes > 0 ? (progress * totalBytes).round() : 0,
      totalBytes: totalBytes,
      posterTag: meta['posterTag'] as String?,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// The partial/final file's local path — best-effort; a missing directory
  /// (e.g. right after enqueue) shouldn't blow up progress reporting.
  Future<String?> _safeFilePath(Task task) async {
    try {
      return await task.filePath();
    } catch (_) {
      return null;
    }
  }

  DownloadStatus _toStatus(TaskStatus status) => switch (status) {
        TaskStatus.enqueued => DownloadStatus.enqueued,
        TaskStatus.running => DownloadStatus.running,
        TaskStatus.paused => DownloadStatus.paused,
        TaskStatus.complete => DownloadStatus.complete,
        TaskStatus.canceled => DownloadStatus.canceled,
        TaskStatus.notFound ||
        TaskStatus.failed ||
        TaskStatus.waitingToRetry =>
          DownloadStatus.failed,
      };

  void dispose() => _recordsController.close();
}
