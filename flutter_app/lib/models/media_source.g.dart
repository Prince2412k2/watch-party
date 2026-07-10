// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_source.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MediaSourceImpl _$$MediaSourceImplFromJson(Map<String, dynamic> json) =>
    _$MediaSourceImpl(
      id: json['Id'] as String,
      protocol: json['Protocol'] as String?,
      container: json['Container'] as String?,
      path: json['Path'] as String?,
      name: json['Name'] as String?,
      size: (json['Size'] as num?)?.toInt(),
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? false,
      supportsDirectStream: json['SupportsDirectStream'] as bool? ?? false,
      supportsTranscoding: json['SupportsTranscoding'] as bool? ?? false,
      mediaStreams:
          (json['MediaStreams'] as List<dynamic>?)
              ?.map((e) => MediaStream.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <MediaStream>[],
    );

Map<String, dynamic> _$$MediaSourceImplToJson(_$MediaSourceImpl instance) =>
    <String, dynamic>{
      'Id': instance.id,
      'Protocol': instance.protocol,
      'Container': instance.container,
      'Path': instance.path,
      'Name': instance.name,
      'Size': instance.size,
      'RunTimeTicks': instance.runTimeTicks,
      'SupportsDirectPlay': instance.supportsDirectPlay,
      'SupportsDirectStream': instance.supportsDirectStream,
      'SupportsTranscoding': instance.supportsTranscoding,
      'MediaStreams': instance.mediaStreams,
    };
