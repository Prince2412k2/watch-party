// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'library_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

UserItemData _$UserItemDataFromJson(Map<String, dynamic> json) {
  return _UserItemData.fromJson(json);
}

/// @nodoc
mixin _$UserItemData {
  @JsonKey(name: 'PlaybackPositionTicks')
  int get playbackPositionTicks => throw _privateConstructorUsedError;
  @JsonKey(name: 'PlayedPercentage')
  double? get playedPercentage => throw _privateConstructorUsedError;
  @JsonKey(name: 'Played')
  bool get played => throw _privateConstructorUsedError;
  @JsonKey(name: 'PlayCount')
  int get playCount => throw _privateConstructorUsedError;
  @JsonKey(name: 'IsFavorite')
  bool get isFavorite => throw _privateConstructorUsedError;
  @JsonKey(name: 'UnplayedItemCount')
  int? get unplayedItemCount => throw _privateConstructorUsedError;

  /// Serializes this UserItemData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UserItemData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserItemDataCopyWith<UserItemData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserItemDataCopyWith<$Res> {
  factory $UserItemDataCopyWith(
    UserItemData value,
    $Res Function(UserItemData) then,
  ) = _$UserItemDataCopyWithImpl<$Res, UserItemData>;
  @useResult
  $Res call({
    @JsonKey(name: 'PlaybackPositionTicks') int playbackPositionTicks,
    @JsonKey(name: 'PlayedPercentage') double? playedPercentage,
    @JsonKey(name: 'Played') bool played,
    @JsonKey(name: 'PlayCount') int playCount,
    @JsonKey(name: 'IsFavorite') bool isFavorite,
    @JsonKey(name: 'UnplayedItemCount') int? unplayedItemCount,
  });
}

/// @nodoc
class _$UserItemDataCopyWithImpl<$Res, $Val extends UserItemData>
    implements $UserItemDataCopyWith<$Res> {
  _$UserItemDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserItemData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? playbackPositionTicks = null,
    Object? playedPercentage = freezed,
    Object? played = null,
    Object? playCount = null,
    Object? isFavorite = null,
    Object? unplayedItemCount = freezed,
  }) {
    return _then(
      _value.copyWith(
            playbackPositionTicks: null == playbackPositionTicks
                ? _value.playbackPositionTicks
                : playbackPositionTicks // ignore: cast_nullable_to_non_nullable
                      as int,
            playedPercentage: freezed == playedPercentage
                ? _value.playedPercentage
                : playedPercentage // ignore: cast_nullable_to_non_nullable
                      as double?,
            played: null == played
                ? _value.played
                : played // ignore: cast_nullable_to_non_nullable
                      as bool,
            playCount: null == playCount
                ? _value.playCount
                : playCount // ignore: cast_nullable_to_non_nullable
                      as int,
            isFavorite: null == isFavorite
                ? _value.isFavorite
                : isFavorite // ignore: cast_nullable_to_non_nullable
                      as bool,
            unplayedItemCount: freezed == unplayedItemCount
                ? _value.unplayedItemCount
                : unplayedItemCount // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UserItemDataImplCopyWith<$Res>
    implements $UserItemDataCopyWith<$Res> {
  factory _$$UserItemDataImplCopyWith(
    _$UserItemDataImpl value,
    $Res Function(_$UserItemDataImpl) then,
  ) = __$$UserItemDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'PlaybackPositionTicks') int playbackPositionTicks,
    @JsonKey(name: 'PlayedPercentage') double? playedPercentage,
    @JsonKey(name: 'Played') bool played,
    @JsonKey(name: 'PlayCount') int playCount,
    @JsonKey(name: 'IsFavorite') bool isFavorite,
    @JsonKey(name: 'UnplayedItemCount') int? unplayedItemCount,
  });
}

/// @nodoc
class __$$UserItemDataImplCopyWithImpl<$Res>
    extends _$UserItemDataCopyWithImpl<$Res, _$UserItemDataImpl>
    implements _$$UserItemDataImplCopyWith<$Res> {
  __$$UserItemDataImplCopyWithImpl(
    _$UserItemDataImpl _value,
    $Res Function(_$UserItemDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UserItemData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? playbackPositionTicks = null,
    Object? playedPercentage = freezed,
    Object? played = null,
    Object? playCount = null,
    Object? isFavorite = null,
    Object? unplayedItemCount = freezed,
  }) {
    return _then(
      _$UserItemDataImpl(
        playbackPositionTicks: null == playbackPositionTicks
            ? _value.playbackPositionTicks
            : playbackPositionTicks // ignore: cast_nullable_to_non_nullable
                  as int,
        playedPercentage: freezed == playedPercentage
            ? _value.playedPercentage
            : playedPercentage // ignore: cast_nullable_to_non_nullable
                  as double?,
        played: null == played
            ? _value.played
            : played // ignore: cast_nullable_to_non_nullable
                  as bool,
        playCount: null == playCount
            ? _value.playCount
            : playCount // ignore: cast_nullable_to_non_nullable
                  as int,
        isFavorite: null == isFavorite
            ? _value.isFavorite
            : isFavorite // ignore: cast_nullable_to_non_nullable
                  as bool,
        unplayedItemCount: freezed == unplayedItemCount
            ? _value.unplayedItemCount
            : unplayedItemCount // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$UserItemDataImpl implements _UserItemData {
  const _$UserItemDataImpl({
    @JsonKey(name: 'PlaybackPositionTicks') this.playbackPositionTicks = 0,
    @JsonKey(name: 'PlayedPercentage') this.playedPercentage,
    @JsonKey(name: 'Played') this.played = false,
    @JsonKey(name: 'PlayCount') this.playCount = 0,
    @JsonKey(name: 'IsFavorite') this.isFavorite = false,
    @JsonKey(name: 'UnplayedItemCount') this.unplayedItemCount,
  });

  factory _$UserItemDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserItemDataImplFromJson(json);

  @override
  @JsonKey(name: 'PlaybackPositionTicks')
  final int playbackPositionTicks;
  @override
  @JsonKey(name: 'PlayedPercentage')
  final double? playedPercentage;
  @override
  @JsonKey(name: 'Played')
  final bool played;
  @override
  @JsonKey(name: 'PlayCount')
  final int playCount;
  @override
  @JsonKey(name: 'IsFavorite')
  final bool isFavorite;
  @override
  @JsonKey(name: 'UnplayedItemCount')
  final int? unplayedItemCount;

  @override
  String toString() {
    return 'UserItemData(playbackPositionTicks: $playbackPositionTicks, playedPercentage: $playedPercentage, played: $played, playCount: $playCount, isFavorite: $isFavorite, unplayedItemCount: $unplayedItemCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserItemDataImpl &&
            (identical(other.playbackPositionTicks, playbackPositionTicks) ||
                other.playbackPositionTicks == playbackPositionTicks) &&
            (identical(other.playedPercentage, playedPercentage) ||
                other.playedPercentage == playedPercentage) &&
            (identical(other.played, played) || other.played == played) &&
            (identical(other.playCount, playCount) ||
                other.playCount == playCount) &&
            (identical(other.isFavorite, isFavorite) ||
                other.isFavorite == isFavorite) &&
            (identical(other.unplayedItemCount, unplayedItemCount) ||
                other.unplayedItemCount == unplayedItemCount));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    playbackPositionTicks,
    playedPercentage,
    played,
    playCount,
    isFavorite,
    unplayedItemCount,
  );

  /// Create a copy of UserItemData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserItemDataImplCopyWith<_$UserItemDataImpl> get copyWith =>
      __$$UserItemDataImplCopyWithImpl<_$UserItemDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UserItemDataImplToJson(this);
  }
}

abstract class _UserItemData implements UserItemData {
  const factory _UserItemData({
    @JsonKey(name: 'PlaybackPositionTicks') final int playbackPositionTicks,
    @JsonKey(name: 'PlayedPercentage') final double? playedPercentage,
    @JsonKey(name: 'Played') final bool played,
    @JsonKey(name: 'PlayCount') final int playCount,
    @JsonKey(name: 'IsFavorite') final bool isFavorite,
    @JsonKey(name: 'UnplayedItemCount') final int? unplayedItemCount,
  }) = _$UserItemDataImpl;

  factory _UserItemData.fromJson(Map<String, dynamic> json) =
      _$UserItemDataImpl.fromJson;

  @override
  @JsonKey(name: 'PlaybackPositionTicks')
  int get playbackPositionTicks;
  @override
  @JsonKey(name: 'PlayedPercentage')
  double? get playedPercentage;
  @override
  @JsonKey(name: 'Played')
  bool get played;
  @override
  @JsonKey(name: 'PlayCount')
  int get playCount;
  @override
  @JsonKey(name: 'IsFavorite')
  bool get isFavorite;
  @override
  @JsonKey(name: 'UnplayedItemCount')
  int? get unplayedItemCount;

  /// Create a copy of UserItemData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserItemDataImplCopyWith<_$UserItemDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

LibraryItem _$LibraryItemFromJson(Map<String, dynamic> json) {
  return _LibraryItem.fromJson(json);
}

/// @nodoc
mixin _$LibraryItem {
  @JsonKey(name: 'Id')
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'Name')
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'Type')
  String? get type => throw _privateConstructorUsedError;
  @JsonKey(name: 'CollectionType')
  String? get collectionType => throw _privateConstructorUsedError;
  @JsonKey(name: 'ServerId')
  String? get serverId => throw _privateConstructorUsedError;
  @JsonKey(name: 'Overview')
  String? get overview => throw _privateConstructorUsedError;
  @JsonKey(name: 'ProductionYear')
  int? get productionYear => throw _privateConstructorUsedError;
  @JsonKey(name: 'PremiereDate')
  String? get premiereDate => throw _privateConstructorUsedError;
  @JsonKey(name: 'OfficialRating')
  String? get officialRating => throw _privateConstructorUsedError;
  @JsonKey(name: 'CommunityRating')
  double? get communityRating => throw _privateConstructorUsedError;
  @JsonKey(name: 'CriticRating')
  double? get criticRating => throw _privateConstructorUsedError;
  @JsonKey(name: 'RunTimeTicks')
  int? get runTimeTicks => throw _privateConstructorUsedError;
  @JsonKey(name: 'Container')
  String? get container => throw _privateConstructorUsedError;
  @JsonKey(name: 'ImageTags')
  Map<String, String>? get imageTags => throw _privateConstructorUsedError;
  @JsonKey(name: 'BackdropImageTags')
  List<String> get backdropImageTags => throw _privateConstructorUsedError;
  @JsonKey(name: 'Genres')
  List<String> get genres => throw _privateConstructorUsedError;
  @JsonKey(name: 'Taglines')
  List<String> get taglines => throw _privateConstructorUsedError;
  @JsonKey(name: 'MediaSources')
  List<MediaSource> get mediaSources => throw _privateConstructorUsedError;
  @JsonKey(name: 'UserData')
  UserItemData? get userData => throw _privateConstructorUsedError; // Series/episode hierarchy hints.
  @JsonKey(name: 'SeriesId')
  String? get seriesId => throw _privateConstructorUsedError;
  @JsonKey(name: 'SeriesName')
  String? get seriesName => throw _privateConstructorUsedError;
  @JsonKey(name: 'ParentId')
  String? get parentId => throw _privateConstructorUsedError;
  @JsonKey(name: 'IndexNumber')
  int? get indexNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'ParentIndexNumber')
  int? get parentIndexNumber => throw _privateConstructorUsedError; // Detail-page hero: cast/crew and external (IMDb/TMDb) links.
  @JsonKey(name: 'People')
  List<Person> get people => throw _privateConstructorUsedError;
  @JsonKey(name: 'ProviderIds')
  Map<String, String> get providerIds => throw _privateConstructorUsedError;

  /// Serializes this LibraryItem to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of LibraryItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $LibraryItemCopyWith<LibraryItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LibraryItemCopyWith<$Res> {
  factory $LibraryItemCopyWith(
    LibraryItem value,
    $Res Function(LibraryItem) then,
  ) = _$LibraryItemCopyWithImpl<$Res, LibraryItem>;
  @useResult
  $Res call({
    @JsonKey(name: 'Id') String id,
    @JsonKey(name: 'Name') String name,
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
    @JsonKey(name: 'BackdropImageTags') List<String> backdropImageTags,
    @JsonKey(name: 'Genres') List<String> genres,
    @JsonKey(name: 'Taglines') List<String> taglines,
    @JsonKey(name: 'MediaSources') List<MediaSource> mediaSources,
    @JsonKey(name: 'UserData') UserItemData? userData,
    @JsonKey(name: 'SeriesId') String? seriesId,
    @JsonKey(name: 'SeriesName') String? seriesName,
    @JsonKey(name: 'ParentId') String? parentId,
    @JsonKey(name: 'IndexNumber') int? indexNumber,
    @JsonKey(name: 'ParentIndexNumber') int? parentIndexNumber,
    @JsonKey(name: 'People') List<Person> people,
    @JsonKey(name: 'ProviderIds') Map<String, String> providerIds,
  });

  $UserItemDataCopyWith<$Res>? get userData;
}

/// @nodoc
class _$LibraryItemCopyWithImpl<$Res, $Val extends LibraryItem>
    implements $LibraryItemCopyWith<$Res> {
  _$LibraryItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of LibraryItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = freezed,
    Object? collectionType = freezed,
    Object? serverId = freezed,
    Object? overview = freezed,
    Object? productionYear = freezed,
    Object? premiereDate = freezed,
    Object? officialRating = freezed,
    Object? communityRating = freezed,
    Object? criticRating = freezed,
    Object? runTimeTicks = freezed,
    Object? container = freezed,
    Object? imageTags = freezed,
    Object? backdropImageTags = null,
    Object? genres = null,
    Object? taglines = null,
    Object? mediaSources = null,
    Object? userData = freezed,
    Object? seriesId = freezed,
    Object? seriesName = freezed,
    Object? parentId = freezed,
    Object? indexNumber = freezed,
    Object? parentIndexNumber = freezed,
    Object? people = null,
    Object? providerIds = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            type: freezed == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String?,
            collectionType: freezed == collectionType
                ? _value.collectionType
                : collectionType // ignore: cast_nullable_to_non_nullable
                      as String?,
            serverId: freezed == serverId
                ? _value.serverId
                : serverId // ignore: cast_nullable_to_non_nullable
                      as String?,
            overview: freezed == overview
                ? _value.overview
                : overview // ignore: cast_nullable_to_non_nullable
                      as String?,
            productionYear: freezed == productionYear
                ? _value.productionYear
                : productionYear // ignore: cast_nullable_to_non_nullable
                      as int?,
            premiereDate: freezed == premiereDate
                ? _value.premiereDate
                : premiereDate // ignore: cast_nullable_to_non_nullable
                      as String?,
            officialRating: freezed == officialRating
                ? _value.officialRating
                : officialRating // ignore: cast_nullable_to_non_nullable
                      as String?,
            communityRating: freezed == communityRating
                ? _value.communityRating
                : communityRating // ignore: cast_nullable_to_non_nullable
                      as double?,
            criticRating: freezed == criticRating
                ? _value.criticRating
                : criticRating // ignore: cast_nullable_to_non_nullable
                      as double?,
            runTimeTicks: freezed == runTimeTicks
                ? _value.runTimeTicks
                : runTimeTicks // ignore: cast_nullable_to_non_nullable
                      as int?,
            container: freezed == container
                ? _value.container
                : container // ignore: cast_nullable_to_non_nullable
                      as String?,
            imageTags: freezed == imageTags
                ? _value.imageTags
                : imageTags // ignore: cast_nullable_to_non_nullable
                      as Map<String, String>?,
            backdropImageTags: null == backdropImageTags
                ? _value.backdropImageTags
                : backdropImageTags // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            genres: null == genres
                ? _value.genres
                : genres // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            taglines: null == taglines
                ? _value.taglines
                : taglines // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            mediaSources: null == mediaSources
                ? _value.mediaSources
                : mediaSources // ignore: cast_nullable_to_non_nullable
                      as List<MediaSource>,
            userData: freezed == userData
                ? _value.userData
                : userData // ignore: cast_nullable_to_non_nullable
                      as UserItemData?,
            seriesId: freezed == seriesId
                ? _value.seriesId
                : seriesId // ignore: cast_nullable_to_non_nullable
                      as String?,
            seriesName: freezed == seriesName
                ? _value.seriesName
                : seriesName // ignore: cast_nullable_to_non_nullable
                      as String?,
            parentId: freezed == parentId
                ? _value.parentId
                : parentId // ignore: cast_nullable_to_non_nullable
                      as String?,
            indexNumber: freezed == indexNumber
                ? _value.indexNumber
                : indexNumber // ignore: cast_nullable_to_non_nullable
                      as int?,
            parentIndexNumber: freezed == parentIndexNumber
                ? _value.parentIndexNumber
                : parentIndexNumber // ignore: cast_nullable_to_non_nullable
                      as int?,
            people: null == people
                ? _value.people
                : people // ignore: cast_nullable_to_non_nullable
                      as List<Person>,
            providerIds: null == providerIds
                ? _value.providerIds
                : providerIds // ignore: cast_nullable_to_non_nullable
                      as Map<String, String>,
          )
          as $Val,
    );
  }

  /// Create a copy of LibraryItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $UserItemDataCopyWith<$Res>? get userData {
    if (_value.userData == null) {
      return null;
    }

    return $UserItemDataCopyWith<$Res>(_value.userData!, (value) {
      return _then(_value.copyWith(userData: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$LibraryItemImplCopyWith<$Res>
    implements $LibraryItemCopyWith<$Res> {
  factory _$$LibraryItemImplCopyWith(
    _$LibraryItemImpl value,
    $Res Function(_$LibraryItemImpl) then,
  ) = __$$LibraryItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'Id') String id,
    @JsonKey(name: 'Name') String name,
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
    @JsonKey(name: 'BackdropImageTags') List<String> backdropImageTags,
    @JsonKey(name: 'Genres') List<String> genres,
    @JsonKey(name: 'Taglines') List<String> taglines,
    @JsonKey(name: 'MediaSources') List<MediaSource> mediaSources,
    @JsonKey(name: 'UserData') UserItemData? userData,
    @JsonKey(name: 'SeriesId') String? seriesId,
    @JsonKey(name: 'SeriesName') String? seriesName,
    @JsonKey(name: 'ParentId') String? parentId,
    @JsonKey(name: 'IndexNumber') int? indexNumber,
    @JsonKey(name: 'ParentIndexNumber') int? parentIndexNumber,
    @JsonKey(name: 'People') List<Person> people,
    @JsonKey(name: 'ProviderIds') Map<String, String> providerIds,
  });

  @override
  $UserItemDataCopyWith<$Res>? get userData;
}

/// @nodoc
class __$$LibraryItemImplCopyWithImpl<$Res>
    extends _$LibraryItemCopyWithImpl<$Res, _$LibraryItemImpl>
    implements _$$LibraryItemImplCopyWith<$Res> {
  __$$LibraryItemImplCopyWithImpl(
    _$LibraryItemImpl _value,
    $Res Function(_$LibraryItemImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of LibraryItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = freezed,
    Object? collectionType = freezed,
    Object? serverId = freezed,
    Object? overview = freezed,
    Object? productionYear = freezed,
    Object? premiereDate = freezed,
    Object? officialRating = freezed,
    Object? communityRating = freezed,
    Object? criticRating = freezed,
    Object? runTimeTicks = freezed,
    Object? container = freezed,
    Object? imageTags = freezed,
    Object? backdropImageTags = null,
    Object? genres = null,
    Object? taglines = null,
    Object? mediaSources = null,
    Object? userData = freezed,
    Object? seriesId = freezed,
    Object? seriesName = freezed,
    Object? parentId = freezed,
    Object? indexNumber = freezed,
    Object? parentIndexNumber = freezed,
    Object? people = null,
    Object? providerIds = null,
  }) {
    return _then(
      _$LibraryItemImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        type: freezed == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String?,
        collectionType: freezed == collectionType
            ? _value.collectionType
            : collectionType // ignore: cast_nullable_to_non_nullable
                  as String?,
        serverId: freezed == serverId
            ? _value.serverId
            : serverId // ignore: cast_nullable_to_non_nullable
                  as String?,
        overview: freezed == overview
            ? _value.overview
            : overview // ignore: cast_nullable_to_non_nullable
                  as String?,
        productionYear: freezed == productionYear
            ? _value.productionYear
            : productionYear // ignore: cast_nullable_to_non_nullable
                  as int?,
        premiereDate: freezed == premiereDate
            ? _value.premiereDate
            : premiereDate // ignore: cast_nullable_to_non_nullable
                  as String?,
        officialRating: freezed == officialRating
            ? _value.officialRating
            : officialRating // ignore: cast_nullable_to_non_nullable
                  as String?,
        communityRating: freezed == communityRating
            ? _value.communityRating
            : communityRating // ignore: cast_nullable_to_non_nullable
                  as double?,
        criticRating: freezed == criticRating
            ? _value.criticRating
            : criticRating // ignore: cast_nullable_to_non_nullable
                  as double?,
        runTimeTicks: freezed == runTimeTicks
            ? _value.runTimeTicks
            : runTimeTicks // ignore: cast_nullable_to_non_nullable
                  as int?,
        container: freezed == container
            ? _value.container
            : container // ignore: cast_nullable_to_non_nullable
                  as String?,
        imageTags: freezed == imageTags
            ? _value._imageTags
            : imageTags // ignore: cast_nullable_to_non_nullable
                  as Map<String, String>?,
        backdropImageTags: null == backdropImageTags
            ? _value._backdropImageTags
            : backdropImageTags // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        genres: null == genres
            ? _value._genres
            : genres // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        taglines: null == taglines
            ? _value._taglines
            : taglines // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        mediaSources: null == mediaSources
            ? _value._mediaSources
            : mediaSources // ignore: cast_nullable_to_non_nullable
                  as List<MediaSource>,
        userData: freezed == userData
            ? _value.userData
            : userData // ignore: cast_nullable_to_non_nullable
                  as UserItemData?,
        seriesId: freezed == seriesId
            ? _value.seriesId
            : seriesId // ignore: cast_nullable_to_non_nullable
                  as String?,
        seriesName: freezed == seriesName
            ? _value.seriesName
            : seriesName // ignore: cast_nullable_to_non_nullable
                  as String?,
        parentId: freezed == parentId
            ? _value.parentId
            : parentId // ignore: cast_nullable_to_non_nullable
                  as String?,
        indexNumber: freezed == indexNumber
            ? _value.indexNumber
            : indexNumber // ignore: cast_nullable_to_non_nullable
                  as int?,
        parentIndexNumber: freezed == parentIndexNumber
            ? _value.parentIndexNumber
            : parentIndexNumber // ignore: cast_nullable_to_non_nullable
                  as int?,
        people: null == people
            ? _value._people
            : people // ignore: cast_nullable_to_non_nullable
                  as List<Person>,
        providerIds: null == providerIds
            ? _value._providerIds
            : providerIds // ignore: cast_nullable_to_non_nullable
                  as Map<String, String>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$LibraryItemImpl implements _LibraryItem {
  const _$LibraryItemImpl({
    @JsonKey(name: 'Id') required this.id,
    @JsonKey(name: 'Name') this.name = '',
    @JsonKey(name: 'Type') this.type,
    @JsonKey(name: 'CollectionType') this.collectionType,
    @JsonKey(name: 'ServerId') this.serverId,
    @JsonKey(name: 'Overview') this.overview,
    @JsonKey(name: 'ProductionYear') this.productionYear,
    @JsonKey(name: 'PremiereDate') this.premiereDate,
    @JsonKey(name: 'OfficialRating') this.officialRating,
    @JsonKey(name: 'CommunityRating') this.communityRating,
    @JsonKey(name: 'CriticRating') this.criticRating,
    @JsonKey(name: 'RunTimeTicks') this.runTimeTicks,
    @JsonKey(name: 'Container') this.container,
    @JsonKey(name: 'ImageTags') final Map<String, String>? imageTags,
    @JsonKey(name: 'BackdropImageTags')
    final List<String> backdropImageTags = const <String>[],
    @JsonKey(name: 'Genres') final List<String> genres = const <String>[],
    @JsonKey(name: 'Taglines') final List<String> taglines = const <String>[],
    @JsonKey(name: 'MediaSources')
    final List<MediaSource> mediaSources = const <MediaSource>[],
    @JsonKey(name: 'UserData') this.userData,
    @JsonKey(name: 'SeriesId') this.seriesId,
    @JsonKey(name: 'SeriesName') this.seriesName,
    @JsonKey(name: 'ParentId') this.parentId,
    @JsonKey(name: 'IndexNumber') this.indexNumber,
    @JsonKey(name: 'ParentIndexNumber') this.parentIndexNumber,
    @JsonKey(name: 'People') final List<Person> people = const <Person>[],
    @JsonKey(name: 'ProviderIds')
    final Map<String, String> providerIds = const <String, String>{},
  }) : _imageTags = imageTags,
       _backdropImageTags = backdropImageTags,
       _genres = genres,
       _taglines = taglines,
       _mediaSources = mediaSources,
       _people = people,
       _providerIds = providerIds;

  factory _$LibraryItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$LibraryItemImplFromJson(json);

  @override
  @JsonKey(name: 'Id')
  final String id;
  @override
  @JsonKey(name: 'Name')
  final String name;
  @override
  @JsonKey(name: 'Type')
  final String? type;
  @override
  @JsonKey(name: 'CollectionType')
  final String? collectionType;
  @override
  @JsonKey(name: 'ServerId')
  final String? serverId;
  @override
  @JsonKey(name: 'Overview')
  final String? overview;
  @override
  @JsonKey(name: 'ProductionYear')
  final int? productionYear;
  @override
  @JsonKey(name: 'PremiereDate')
  final String? premiereDate;
  @override
  @JsonKey(name: 'OfficialRating')
  final String? officialRating;
  @override
  @JsonKey(name: 'CommunityRating')
  final double? communityRating;
  @override
  @JsonKey(name: 'CriticRating')
  final double? criticRating;
  @override
  @JsonKey(name: 'RunTimeTicks')
  final int? runTimeTicks;
  @override
  @JsonKey(name: 'Container')
  final String? container;
  final Map<String, String>? _imageTags;
  @override
  @JsonKey(name: 'ImageTags')
  Map<String, String>? get imageTags {
    final value = _imageTags;
    if (value == null) return null;
    if (_imageTags is EqualUnmodifiableMapView) return _imageTags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  final List<String> _backdropImageTags;
  @override
  @JsonKey(name: 'BackdropImageTags')
  List<String> get backdropImageTags {
    if (_backdropImageTags is EqualUnmodifiableListView)
      return _backdropImageTags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_backdropImageTags);
  }

  final List<String> _genres;
  @override
  @JsonKey(name: 'Genres')
  List<String> get genres {
    if (_genres is EqualUnmodifiableListView) return _genres;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_genres);
  }

  final List<String> _taglines;
  @override
  @JsonKey(name: 'Taglines')
  List<String> get taglines {
    if (_taglines is EqualUnmodifiableListView) return _taglines;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_taglines);
  }

  final List<MediaSource> _mediaSources;
  @override
  @JsonKey(name: 'MediaSources')
  List<MediaSource> get mediaSources {
    if (_mediaSources is EqualUnmodifiableListView) return _mediaSources;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_mediaSources);
  }

  @override
  @JsonKey(name: 'UserData')
  final UserItemData? userData;
  // Series/episode hierarchy hints.
  @override
  @JsonKey(name: 'SeriesId')
  final String? seriesId;
  @override
  @JsonKey(name: 'SeriesName')
  final String? seriesName;
  @override
  @JsonKey(name: 'ParentId')
  final String? parentId;
  @override
  @JsonKey(name: 'IndexNumber')
  final int? indexNumber;
  @override
  @JsonKey(name: 'ParentIndexNumber')
  final int? parentIndexNumber;
  // Detail-page hero: cast/crew and external (IMDb/TMDb) links.
  final List<Person> _people;
  // Detail-page hero: cast/crew and external (IMDb/TMDb) links.
  @override
  @JsonKey(name: 'People')
  List<Person> get people {
    if (_people is EqualUnmodifiableListView) return _people;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_people);
  }

  final Map<String, String> _providerIds;
  @override
  @JsonKey(name: 'ProviderIds')
  Map<String, String> get providerIds {
    if (_providerIds is EqualUnmodifiableMapView) return _providerIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_providerIds);
  }

  @override
  String toString() {
    return 'LibraryItem(id: $id, name: $name, type: $type, collectionType: $collectionType, serverId: $serverId, overview: $overview, productionYear: $productionYear, premiereDate: $premiereDate, officialRating: $officialRating, communityRating: $communityRating, criticRating: $criticRating, runTimeTicks: $runTimeTicks, container: $container, imageTags: $imageTags, backdropImageTags: $backdropImageTags, genres: $genres, taglines: $taglines, mediaSources: $mediaSources, userData: $userData, seriesId: $seriesId, seriesName: $seriesName, parentId: $parentId, indexNumber: $indexNumber, parentIndexNumber: $parentIndexNumber, people: $people, providerIds: $providerIds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LibraryItemImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.collectionType, collectionType) ||
                other.collectionType == collectionType) &&
            (identical(other.serverId, serverId) ||
                other.serverId == serverId) &&
            (identical(other.overview, overview) ||
                other.overview == overview) &&
            (identical(other.productionYear, productionYear) ||
                other.productionYear == productionYear) &&
            (identical(other.premiereDate, premiereDate) ||
                other.premiereDate == premiereDate) &&
            (identical(other.officialRating, officialRating) ||
                other.officialRating == officialRating) &&
            (identical(other.communityRating, communityRating) ||
                other.communityRating == communityRating) &&
            (identical(other.criticRating, criticRating) ||
                other.criticRating == criticRating) &&
            (identical(other.runTimeTicks, runTimeTicks) ||
                other.runTimeTicks == runTimeTicks) &&
            (identical(other.container, container) ||
                other.container == container) &&
            const DeepCollectionEquality().equals(
              other._imageTags,
              _imageTags,
            ) &&
            const DeepCollectionEquality().equals(
              other._backdropImageTags,
              _backdropImageTags,
            ) &&
            const DeepCollectionEquality().equals(other._genres, _genres) &&
            const DeepCollectionEquality().equals(other._taglines, _taglines) &&
            const DeepCollectionEquality().equals(
              other._mediaSources,
              _mediaSources,
            ) &&
            (identical(other.userData, userData) ||
                other.userData == userData) &&
            (identical(other.seriesId, seriesId) ||
                other.seriesId == seriesId) &&
            (identical(other.seriesName, seriesName) ||
                other.seriesName == seriesName) &&
            (identical(other.parentId, parentId) ||
                other.parentId == parentId) &&
            (identical(other.indexNumber, indexNumber) ||
                other.indexNumber == indexNumber) &&
            (identical(other.parentIndexNumber, parentIndexNumber) ||
                other.parentIndexNumber == parentIndexNumber) &&
            const DeepCollectionEquality().equals(other._people, _people) &&
            const DeepCollectionEquality().equals(
              other._providerIds,
              _providerIds,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    id,
    name,
    type,
    collectionType,
    serverId,
    overview,
    productionYear,
    premiereDate,
    officialRating,
    communityRating,
    criticRating,
    runTimeTicks,
    container,
    const DeepCollectionEquality().hash(_imageTags),
    const DeepCollectionEquality().hash(_backdropImageTags),
    const DeepCollectionEquality().hash(_genres),
    const DeepCollectionEquality().hash(_taglines),
    const DeepCollectionEquality().hash(_mediaSources),
    userData,
    seriesId,
    seriesName,
    parentId,
    indexNumber,
    parentIndexNumber,
    const DeepCollectionEquality().hash(_people),
    const DeepCollectionEquality().hash(_providerIds),
  ]);

  /// Create a copy of LibraryItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$LibraryItemImplCopyWith<_$LibraryItemImpl> get copyWith =>
      __$$LibraryItemImplCopyWithImpl<_$LibraryItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$LibraryItemImplToJson(this);
  }
}

abstract class _LibraryItem implements LibraryItem {
  const factory _LibraryItem({
    @JsonKey(name: 'Id') required final String id,
    @JsonKey(name: 'Name') final String name,
    @JsonKey(name: 'Type') final String? type,
    @JsonKey(name: 'CollectionType') final String? collectionType,
    @JsonKey(name: 'ServerId') final String? serverId,
    @JsonKey(name: 'Overview') final String? overview,
    @JsonKey(name: 'ProductionYear') final int? productionYear,
    @JsonKey(name: 'PremiereDate') final String? premiereDate,
    @JsonKey(name: 'OfficialRating') final String? officialRating,
    @JsonKey(name: 'CommunityRating') final double? communityRating,
    @JsonKey(name: 'CriticRating') final double? criticRating,
    @JsonKey(name: 'RunTimeTicks') final int? runTimeTicks,
    @JsonKey(name: 'Container') final String? container,
    @JsonKey(name: 'ImageTags') final Map<String, String>? imageTags,
    @JsonKey(name: 'BackdropImageTags') final List<String> backdropImageTags,
    @JsonKey(name: 'Genres') final List<String> genres,
    @JsonKey(name: 'Taglines') final List<String> taglines,
    @JsonKey(name: 'MediaSources') final List<MediaSource> mediaSources,
    @JsonKey(name: 'UserData') final UserItemData? userData,
    @JsonKey(name: 'SeriesId') final String? seriesId,
    @JsonKey(name: 'SeriesName') final String? seriesName,
    @JsonKey(name: 'ParentId') final String? parentId,
    @JsonKey(name: 'IndexNumber') final int? indexNumber,
    @JsonKey(name: 'ParentIndexNumber') final int? parentIndexNumber,
    @JsonKey(name: 'People') final List<Person> people,
    @JsonKey(name: 'ProviderIds') final Map<String, String> providerIds,
  }) = _$LibraryItemImpl;

  factory _LibraryItem.fromJson(Map<String, dynamic> json) =
      _$LibraryItemImpl.fromJson;

  @override
  @JsonKey(name: 'Id')
  String get id;
  @override
  @JsonKey(name: 'Name')
  String get name;
  @override
  @JsonKey(name: 'Type')
  String? get type;
  @override
  @JsonKey(name: 'CollectionType')
  String? get collectionType;
  @override
  @JsonKey(name: 'ServerId')
  String? get serverId;
  @override
  @JsonKey(name: 'Overview')
  String? get overview;
  @override
  @JsonKey(name: 'ProductionYear')
  int? get productionYear;
  @override
  @JsonKey(name: 'PremiereDate')
  String? get premiereDate;
  @override
  @JsonKey(name: 'OfficialRating')
  String? get officialRating;
  @override
  @JsonKey(name: 'CommunityRating')
  double? get communityRating;
  @override
  @JsonKey(name: 'CriticRating')
  double? get criticRating;
  @override
  @JsonKey(name: 'RunTimeTicks')
  int? get runTimeTicks;
  @override
  @JsonKey(name: 'Container')
  String? get container;
  @override
  @JsonKey(name: 'ImageTags')
  Map<String, String>? get imageTags;
  @override
  @JsonKey(name: 'BackdropImageTags')
  List<String> get backdropImageTags;
  @override
  @JsonKey(name: 'Genres')
  List<String> get genres;
  @override
  @JsonKey(name: 'Taglines')
  List<String> get taglines;
  @override
  @JsonKey(name: 'MediaSources')
  List<MediaSource> get mediaSources;
  @override
  @JsonKey(name: 'UserData')
  UserItemData? get userData; // Series/episode hierarchy hints.
  @override
  @JsonKey(name: 'SeriesId')
  String? get seriesId;
  @override
  @JsonKey(name: 'SeriesName')
  String? get seriesName;
  @override
  @JsonKey(name: 'ParentId')
  String? get parentId;
  @override
  @JsonKey(name: 'IndexNumber')
  int? get indexNumber;
  @override
  @JsonKey(name: 'ParentIndexNumber')
  int? get parentIndexNumber; // Detail-page hero: cast/crew and external (IMDb/TMDb) links.
  @override
  @JsonKey(name: 'People')
  List<Person> get people;
  @override
  @JsonKey(name: 'ProviderIds')
  Map<String, String> get providerIds;

  /// Create a copy of LibraryItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$LibraryItemImplCopyWith<_$LibraryItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
