// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DownloadRecordImpl _$$DownloadRecordImplFromJson(Map<String, dynamic> json) =>
    _$DownloadRecordImpl(
      itemId: json['itemId'] as String,
      title: json['title'] as String,
      taskId: json['taskId'] as String,
      filePath: json['filePath'] as String?,
      status:
          $enumDecodeNullable(_$DownloadStatusEnumMap, json['status']) ??
          DownloadStatus.enqueued,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      bytesDownloaded: (json['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      posterTag: json['posterTag'] as String?,
      error: json['error'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$DownloadRecordImplToJson(
  _$DownloadRecordImpl instance,
) => <String, dynamic>{
  'itemId': instance.itemId,
  'title': instance.title,
  'taskId': instance.taskId,
  'filePath': instance.filePath,
  'status': _$DownloadStatusEnumMap[instance.status]!,
  'progress': instance.progress,
  'bytesDownloaded': instance.bytesDownloaded,
  'totalBytes': instance.totalBytes,
  'posterTag': instance.posterTag,
  'error': instance.error,
  'updatedAt': instance.updatedAt,
};

const _$DownloadStatusEnumMap = {
  DownloadStatus.enqueued: 'enqueued',
  DownloadStatus.running: 'running',
  DownloadStatus.paused: 'paused',
  DownloadStatus.complete: 'complete',
  DownloadStatus.failed: 'failed',
  DownloadStatus.canceled: 'canceled',
};
