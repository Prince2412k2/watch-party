// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stream_url.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$StreamUrlImpl _$$StreamUrlImplFromJson(Map<String, dynamic> json) =>
    _$StreamUrlImpl(
      url: json['url'] as String,
      expiresAt: (json['expiresAt'] as num).toInt(),
    );

Map<String, dynamic> _$$StreamUrlImplToJson(_$StreamUrlImpl instance) =>
    <String, dynamic>{'url': instance.url, 'expiresAt': instance.expiresAt};
