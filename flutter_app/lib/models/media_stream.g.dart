// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_stream.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MediaStreamImpl _$$MediaStreamImplFromJson(Map<String, dynamic> json) =>
    _$MediaStreamImpl(
      index: (json['Index'] as num?)?.toInt(),
      type: json['Type'] as String?,
      codec: json['Codec'] as String?,
      language: json['Language'] as String?,
      displayTitle: json['DisplayTitle'] as String?,
      title: json['Title'] as String?,
      channels: (json['Channels'] as num?)?.toInt(),
      height: (json['Height'] as num?)?.toInt(),
      width: (json['Width'] as num?)?.toInt(),
      isDefault: json['IsDefault'] as bool? ?? false,
      isForced: json['IsForced'] as bool? ?? false,
      isExternal: json['IsExternal'] as bool? ?? false,
    );

Map<String, dynamic> _$$MediaStreamImplToJson(_$MediaStreamImpl instance) =>
    <String, dynamic>{
      'Index': instance.index,
      'Type': instance.type,
      'Codec': instance.codec,
      'Language': instance.language,
      'DisplayTitle': instance.displayTitle,
      'Title': instance.title,
      'Channels': instance.channels,
      'Height': instance.height,
      'Width': instance.width,
      'IsDefault': instance.isDefault,
      'IsForced': instance.isForced,
      'IsExternal': instance.isExternal,
    };
