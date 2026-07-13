// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'person.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PersonImpl _$$PersonImplFromJson(Map<String, dynamic> json) => _$PersonImpl(
  id: json['Id'] as String,
  name: json['Name'] as String? ?? '',
  role: json['Role'] as String?,
  type: json['Type'] as String?,
);

Map<String, dynamic> _$$PersonImplToJson(_$PersonImpl instance) =>
    <String, dynamic>{
      'Id': instance.id,
      'Name': instance.name,
      'Role': instance.role,
      'Type': instance.type,
    };
