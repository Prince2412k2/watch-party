import 'package:freezed_annotation/freezed_annotation.dart';

part 'offline_record.freezed.dart';
part 'offline_record.g.dart';

/// A fully-downloaded title available for offline playback. media_kit opens
/// [filePath] directly when present (E8.3).
@freezed
class OfflineRecord with _$OfflineRecord {
  const factory OfflineRecord({
    required String itemId,
    required String title,
    /// Absolute local path to the original media file.
    required String filePath,
    @Default(0) int sizeBytes,
    @Default(0) int runTimeTicks,
    String? posterTag,
    String? container,
    /// Epoch-ms the download completed.
    required int downloadedAt,
  }) = _OfflineRecord;

  factory OfflineRecord.fromJson(Map<String, dynamic> json) =>
      _$OfflineRecordFromJson(json);
}
