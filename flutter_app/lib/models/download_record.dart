import 'package:freezed_annotation/freezed_annotation.dart';

part 'download_record.freezed.dart';
part 'download_record.g.dart';

/// Status of a resumable download task (maps to background_downloader states).
enum DownloadStatus {
  enqueued,
  running,
  paused,
  complete,
  failed,
  canceled,
}

/// A tracked download of a title (via `purpose=download` signed URLs). Owned by
/// E8; Phase 0 defines the persisted shape.
@freezed
class DownloadRecord with _$DownloadRecord {
  const factory DownloadRecord({
    /// Jellyfin item id being downloaded.
    required String itemId,
    required String title,
    /// background_downloader task id.
    required String taskId,
    /// Absolute local path once (partially) written.
    String? filePath,
    @Default(DownloadStatus.enqueued) DownloadStatus status,
    /// 0.0–1.0.
    @Default(0) double progress,
    @Default(0) int bytesDownloaded,
    @Default(0) int totalBytes,
    String? posterTag,
    String? error,
    int? updatedAt,
  }) = _DownloadRecord;

  factory DownloadRecord.fromJson(Map<String, dynamic> json) =>
      _$DownloadRecordFromJson(json);
}
