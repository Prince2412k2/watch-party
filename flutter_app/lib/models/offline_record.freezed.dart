// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'offline_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

OfflineRecord _$OfflineRecordFromJson(Map<String, dynamic> json) {
  return _OfflineRecord.fromJson(json);
}

/// @nodoc
mixin _$OfflineRecord {
  String get itemId => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;

  /// Absolute local path to the original media file.
  String get filePath => throw _privateConstructorUsedError;
  int get sizeBytes => throw _privateConstructorUsedError;
  int get runTimeTicks => throw _privateConstructorUsedError;
  String? get posterTag => throw _privateConstructorUsedError;
  String? get container => throw _privateConstructorUsedError;

  /// Epoch-ms the download completed.
  int get downloadedAt => throw _privateConstructorUsedError;

  /// Serializes this OfflineRecord to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OfflineRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OfflineRecordCopyWith<OfflineRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OfflineRecordCopyWith<$Res> {
  factory $OfflineRecordCopyWith(
    OfflineRecord value,
    $Res Function(OfflineRecord) then,
  ) = _$OfflineRecordCopyWithImpl<$Res, OfflineRecord>;
  @useResult
  $Res call({
    String itemId,
    String title,
    String filePath,
    int sizeBytes,
    int runTimeTicks,
    String? posterTag,
    String? container,
    int downloadedAt,
  });
}

/// @nodoc
class _$OfflineRecordCopyWithImpl<$Res, $Val extends OfflineRecord>
    implements $OfflineRecordCopyWith<$Res> {
  _$OfflineRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OfflineRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? itemId = null,
    Object? title = null,
    Object? filePath = null,
    Object? sizeBytes = null,
    Object? runTimeTicks = null,
    Object? posterTag = freezed,
    Object? container = freezed,
    Object? downloadedAt = null,
  }) {
    return _then(
      _value.copyWith(
            itemId: null == itemId
                ? _value.itemId
                : itemId // ignore: cast_nullable_to_non_nullable
                      as String,
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            filePath: null == filePath
                ? _value.filePath
                : filePath // ignore: cast_nullable_to_non_nullable
                      as String,
            sizeBytes: null == sizeBytes
                ? _value.sizeBytes
                : sizeBytes // ignore: cast_nullable_to_non_nullable
                      as int,
            runTimeTicks: null == runTimeTicks
                ? _value.runTimeTicks
                : runTimeTicks // ignore: cast_nullable_to_non_nullable
                      as int,
            posterTag: freezed == posterTag
                ? _value.posterTag
                : posterTag // ignore: cast_nullable_to_non_nullable
                      as String?,
            container: freezed == container
                ? _value.container
                : container // ignore: cast_nullable_to_non_nullable
                      as String?,
            downloadedAt: null == downloadedAt
                ? _value.downloadedAt
                : downloadedAt // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OfflineRecordImplCopyWith<$Res>
    implements $OfflineRecordCopyWith<$Res> {
  factory _$$OfflineRecordImplCopyWith(
    _$OfflineRecordImpl value,
    $Res Function(_$OfflineRecordImpl) then,
  ) = __$$OfflineRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String itemId,
    String title,
    String filePath,
    int sizeBytes,
    int runTimeTicks,
    String? posterTag,
    String? container,
    int downloadedAt,
  });
}

/// @nodoc
class __$$OfflineRecordImplCopyWithImpl<$Res>
    extends _$OfflineRecordCopyWithImpl<$Res, _$OfflineRecordImpl>
    implements _$$OfflineRecordImplCopyWith<$Res> {
  __$$OfflineRecordImplCopyWithImpl(
    _$OfflineRecordImpl _value,
    $Res Function(_$OfflineRecordImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OfflineRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? itemId = null,
    Object? title = null,
    Object? filePath = null,
    Object? sizeBytes = null,
    Object? runTimeTicks = null,
    Object? posterTag = freezed,
    Object? container = freezed,
    Object? downloadedAt = null,
  }) {
    return _then(
      _$OfflineRecordImpl(
        itemId: null == itemId
            ? _value.itemId
            : itemId // ignore: cast_nullable_to_non_nullable
                  as String,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        filePath: null == filePath
            ? _value.filePath
            : filePath // ignore: cast_nullable_to_non_nullable
                  as String,
        sizeBytes: null == sizeBytes
            ? _value.sizeBytes
            : sizeBytes // ignore: cast_nullable_to_non_nullable
                  as int,
        runTimeTicks: null == runTimeTicks
            ? _value.runTimeTicks
            : runTimeTicks // ignore: cast_nullable_to_non_nullable
                  as int,
        posterTag: freezed == posterTag
            ? _value.posterTag
            : posterTag // ignore: cast_nullable_to_non_nullable
                  as String?,
        container: freezed == container
            ? _value.container
            : container // ignore: cast_nullable_to_non_nullable
                  as String?,
        downloadedAt: null == downloadedAt
            ? _value.downloadedAt
            : downloadedAt // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OfflineRecordImpl implements _OfflineRecord {
  const _$OfflineRecordImpl({
    required this.itemId,
    required this.title,
    required this.filePath,
    this.sizeBytes = 0,
    this.runTimeTicks = 0,
    this.posterTag,
    this.container,
    required this.downloadedAt,
  });

  factory _$OfflineRecordImpl.fromJson(Map<String, dynamic> json) =>
      _$$OfflineRecordImplFromJson(json);

  @override
  final String itemId;
  @override
  final String title;

  /// Absolute local path to the original media file.
  @override
  final String filePath;
  @override
  @JsonKey()
  final int sizeBytes;
  @override
  @JsonKey()
  final int runTimeTicks;
  @override
  final String? posterTag;
  @override
  final String? container;

  /// Epoch-ms the download completed.
  @override
  final int downloadedAt;

  @override
  String toString() {
    return 'OfflineRecord(itemId: $itemId, title: $title, filePath: $filePath, sizeBytes: $sizeBytes, runTimeTicks: $runTimeTicks, posterTag: $posterTag, container: $container, downloadedAt: $downloadedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OfflineRecordImpl &&
            (identical(other.itemId, itemId) || other.itemId == itemId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.filePath, filePath) ||
                other.filePath == filePath) &&
            (identical(other.sizeBytes, sizeBytes) ||
                other.sizeBytes == sizeBytes) &&
            (identical(other.runTimeTicks, runTimeTicks) ||
                other.runTimeTicks == runTimeTicks) &&
            (identical(other.posterTag, posterTag) ||
                other.posterTag == posterTag) &&
            (identical(other.container, container) ||
                other.container == container) &&
            (identical(other.downloadedAt, downloadedAt) ||
                other.downloadedAt == downloadedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    itemId,
    title,
    filePath,
    sizeBytes,
    runTimeTicks,
    posterTag,
    container,
    downloadedAt,
  );

  /// Create a copy of OfflineRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OfflineRecordImplCopyWith<_$OfflineRecordImpl> get copyWith =>
      __$$OfflineRecordImplCopyWithImpl<_$OfflineRecordImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OfflineRecordImplToJson(this);
  }
}

abstract class _OfflineRecord implements OfflineRecord {
  const factory _OfflineRecord({
    required final String itemId,
    required final String title,
    required final String filePath,
    final int sizeBytes,
    final int runTimeTicks,
    final String? posterTag,
    final String? container,
    required final int downloadedAt,
  }) = _$OfflineRecordImpl;

  factory _OfflineRecord.fromJson(Map<String, dynamic> json) =
      _$OfflineRecordImpl.fromJson;

  @override
  String get itemId;
  @override
  String get title;

  /// Absolute local path to the original media file.
  @override
  String get filePath;
  @override
  int get sizeBytes;
  @override
  int get runTimeTicks;
  @override
  String? get posterTag;
  @override
  String? get container;

  /// Epoch-ms the download completed.
  @override
  int get downloadedAt;

  /// Create a copy of OfflineRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OfflineRecordImplCopyWith<_$OfflineRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
