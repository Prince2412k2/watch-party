import 'package:freezed_annotation/freezed_annotation.dart';

import 'media_source.dart';

part 'library_item.freezed.dart';
part 'library_item.g.dart';

/// Per-user watch state Jellyfin attaches under `UserData`.
@freezed
class UserItemData with _$UserItemData {
  const factory UserItemData({
    @JsonKey(name: 'PlaybackPositionTicks') @Default(0) int playbackPositionTicks,
    @JsonKey(name: 'PlayedPercentage') double? playedPercentage,
    @JsonKey(name: 'Played') @Default(false) bool played,
    @JsonKey(name: 'PlayCount') @Default(0) int playCount,
    @JsonKey(name: 'IsFavorite') @Default(false) bool isFavorite,
    @JsonKey(name: 'UnplayedItemCount') int? unplayedItemCount,
  }) = _UserItemData;

  factory UserItemData.fromJson(Map<String, dynamic> json) =>
      _$UserItemDataFromJson(json);
}

/// A Jellyfin library item (Movie / Series / Episode / CollectionFolder ...).
/// PascalCase keys mirror the raw Jellyfin payload the server forwards
/// (`app/server/jellyfin.js`). Only the fields the UI needs are typed; the rest
/// are ignored on decode.
@freezed
class LibraryItem with _$LibraryItem {
  const factory LibraryItem({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Name') @Default('') String name,
    @JsonKey(name: 'Type') String? type,
    @JsonKey(name: 'CollectionType') String? collectionType,
    @JsonKey(name: 'ServerId') String? serverId,
    @JsonKey(name: 'Overview') String? overview,
    @JsonKey(name: 'ProductionYear') int? productionYear,
    @JsonKey(name: 'PremiereDate') String? premiereDate,
    @JsonKey(name: 'OfficialRating') String? officialRating,
    @JsonKey(name: 'CommunityRating') double? communityRating,
    @JsonKey(name: 'CriticRating') double? criticRating,
    @JsonKey(name: 'RunTimeTicks') int? runTimeTicks,
    @JsonKey(name: 'Container') String? container,
    @JsonKey(name: 'ImageTags') Map<String, String>? imageTags,
    @JsonKey(name: 'BackdropImageTags')
    @Default(<String>[])
    List<String> backdropImageTags,
    @JsonKey(name: 'Genres') @Default(<String>[]) List<String> genres,
    @JsonKey(name: 'Taglines') @Default(<String>[]) List<String> taglines,
    @JsonKey(name: 'MediaSources')
    @Default(<MediaSource>[])
    List<MediaSource> mediaSources,
    @JsonKey(name: 'UserData') UserItemData? userData,
    // Series/episode hierarchy hints.
    @JsonKey(name: 'SeriesId') String? seriesId,
    @JsonKey(name: 'SeriesName') String? seriesName,
    @JsonKey(name: 'ParentId') String? parentId,
    @JsonKey(name: 'IndexNumber') int? indexNumber,
    @JsonKey(name: 'ParentIndexNumber') int? parentIndexNumber,
  }) = _LibraryItem;

  factory LibraryItem.fromJson(Map<String, dynamic> json) =>
      _$LibraryItemFromJson(json);
}
