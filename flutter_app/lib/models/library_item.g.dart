// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserItemDataImpl _$$UserItemDataImplFromJson(Map<String, dynamic> json) =>
    _$UserItemDataImpl(
      playbackPositionTicks:
          (json['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
      playedPercentage: (json['PlayedPercentage'] as num?)?.toDouble(),
      played: json['Played'] as bool? ?? false,
      playCount: (json['PlayCount'] as num?)?.toInt() ?? 0,
      isFavorite: json['IsFavorite'] as bool? ?? false,
      unplayedItemCount: (json['UnplayedItemCount'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$UserItemDataImplToJson(_$UserItemDataImpl instance) =>
    <String, dynamic>{
      'PlaybackPositionTicks': instance.playbackPositionTicks,
      'PlayedPercentage': instance.playedPercentage,
      'Played': instance.played,
      'PlayCount': instance.playCount,
      'IsFavorite': instance.isFavorite,
      'UnplayedItemCount': instance.unplayedItemCount,
    };

_$LibraryItemImpl _$$LibraryItemImplFromJson(
  Map<String, dynamic> json,
) => _$LibraryItemImpl(
  id: json['Id'] as String,
  name: json['Name'] as String? ?? '',
  type: json['Type'] as String?,
  collectionType: json['CollectionType'] as String?,
  serverId: json['ServerId'] as String?,
  overview: json['Overview'] as String?,
  productionYear: (json['ProductionYear'] as num?)?.toInt(),
  premiereDate: json['PremiereDate'] as String?,
  officialRating: json['OfficialRating'] as String?,
  communityRating: (json['CommunityRating'] as num?)?.toDouble(),
  criticRating: (json['CriticRating'] as num?)?.toDouble(),
  runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
  container: json['Container'] as String?,
  imageTags: (json['ImageTags'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  ),
  backdropImageTags:
      (json['BackdropImageTags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  genres:
      (json['Genres'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  taglines:
      (json['Taglines'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  mediaSources:
      (json['MediaSources'] as List<dynamic>?)
          ?.map((e) => MediaSource.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MediaSource>[],
  userData: json['UserData'] == null
      ? null
      : UserItemData.fromJson(json['UserData'] as Map<String, dynamic>),
  seriesId: json['SeriesId'] as String?,
  seriesName: json['SeriesName'] as String?,
  parentId: json['ParentId'] as String?,
  indexNumber: (json['IndexNumber'] as num?)?.toInt(),
  parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
);

Map<String, dynamic> _$$LibraryItemImplToJson(_$LibraryItemImpl instance) =>
    <String, dynamic>{
      'Id': instance.id,
      'Name': instance.name,
      'Type': instance.type,
      'CollectionType': instance.collectionType,
      'ServerId': instance.serverId,
      'Overview': instance.overview,
      'ProductionYear': instance.productionYear,
      'PremiereDate': instance.premiereDate,
      'OfficialRating': instance.officialRating,
      'CommunityRating': instance.communityRating,
      'CriticRating': instance.criticRating,
      'RunTimeTicks': instance.runTimeTicks,
      'Container': instance.container,
      'ImageTags': instance.imageTags,
      'BackdropImageTags': instance.backdropImageTags,
      'Genres': instance.genres,
      'Taglines': instance.taglines,
      'MediaSources': instance.mediaSources,
      'UserData': instance.userData,
      'SeriesId': instance.seriesId,
      'SeriesName': instance.seriesName,
      'ParentId': instance.parentId,
      'IndexNumber': instance.indexNumber,
      'ParentIndexNumber': instance.parentIndexNumber,
    };
