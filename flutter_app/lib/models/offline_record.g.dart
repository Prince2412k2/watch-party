// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OfflineRecordImpl _$$OfflineRecordImplFromJson(Map<String, dynamic> json) =>
    _$OfflineRecordImpl(
      itemId: json['itemId'] as String,
      title: json['title'] as String,
      filePath: json['filePath'] as String,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      runTimeTicks: (json['runTimeTicks'] as num?)?.toInt() ?? 0,
      posterTag: json['posterTag'] as String?,
      container: json['container'] as String?,
      downloadedAt: (json['downloadedAt'] as num).toInt(),
    );

Map<String, dynamic> _$$OfflineRecordImplToJson(_$OfflineRecordImpl instance) =>
    <String, dynamic>{
      'itemId': instance.itemId,
      'title': instance.title,
      'filePath': instance.filePath,
      'sizeBytes': instance.sizeBytes,
      'runTimeTicks': instance.runTimeTicks,
      'posterTag': instance.posterTag,
      'container': instance.container,
      'downloadedAt': instance.downloadedAt,
    };
