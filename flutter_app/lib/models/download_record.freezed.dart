// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'download_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

DownloadRecord _$DownloadRecordFromJson(Map<String, dynamic> json) {
  return _DownloadRecord.fromJson(json);
}

/// @nodoc
mixin _$DownloadRecord {
  /// Jellyfin item id being downloaded.
  String get itemId => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;

  /// background_downloader task id.
  String get taskId => throw _privateConstructorUsedError;

  /// Absolute local path once (partially) written.
  String? get filePath => throw _privateConstructorUsedError;
  DownloadStatus get status => throw _privateConstructorUsedError;

  /// 0.0–1.0.
  double get progress => throw _privateConstructorUsedError;
  int get bytesDownloaded => throw _privateConstructorUsedError;
  int get totalBytes => throw _privateConstructorUsedError;
  String? get posterTag => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;
  int? get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this DownloadRecord to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DownloadRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DownloadRecordCopyWith<DownloadRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DownloadRecordCopyWith<$Res> {
  factory $DownloadRecordCopyWith(
    DownloadRecord value,
    $Res Function(DownloadRecord) then,
  ) = _$DownloadRecordCopyWithImpl<$Res, DownloadRecord>;
  @useResult
  $Res call({
    String itemId,
    String title,
    String taskId,
    String? filePath,
    DownloadStatus status,
    double progress,
    int bytesDownloaded,
    int totalBytes,
    String? posterTag,
    String? error,
    int? updatedAt,
  });
}

/// @nodoc
class _$DownloadRecordCopyWithImpl<$Res, $Val extends DownloadRecord>
    implements $DownloadRecordCopyWith<$Res> {
  _$DownloadRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DownloadRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? itemId = null,
    Object? title = null,
    Object? taskId = null,
    Object? filePath = freezed,
    Object? status = null,
    Object? progress = null,
    Object? bytesDownloaded = null,
    Object? totalBytes = null,
    Object? posterTag = freezed,
    Object? error = freezed,
    Object? updatedAt = freezed,
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
            taskId: null == taskId
                ? _value.taskId
                : taskId // ignore: cast_nullable_to_non_nullable
                      as String,
            filePath: freezed == filePath
                ? _value.filePath
                : filePath // ignore: cast_nullable_to_non_nullable
                      as String?,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as DownloadStatus,
            progress: null == progress
                ? _value.progress
                : progress // ignore: cast_nullable_to_non_nullable
                      as double,
            bytesDownloaded: null == bytesDownloaded
                ? _value.bytesDownloaded
                : bytesDownloaded // ignore: cast_nullable_to_non_nullable
                      as int,
            totalBytes: null == totalBytes
                ? _value.totalBytes
                : totalBytes // ignore: cast_nullable_to_non_nullable
                      as int,
            posterTag: freezed == posterTag
                ? _value.posterTag
                : posterTag // ignore: cast_nullable_to_non_nullable
                      as String?,
            error: freezed == error
                ? _value.error
                : error // ignore: cast_nullable_to_non_nullable
                      as String?,
            updatedAt: freezed == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DownloadRecordImplCopyWith<$Res>
    implements $DownloadRecordCopyWith<$Res> {
  factory _$$DownloadRecordImplCopyWith(
    _$DownloadRecordImpl value,
    $Res Function(_$DownloadRecordImpl) then,
  ) = __$$DownloadRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String itemId,
    String title,
    String taskId,
    String? filePath,
    DownloadStatus status,
    double progress,
    int bytesDownloaded,
    int totalBytes,
    String? posterTag,
    String? error,
    int? updatedAt,
  });
}

/// @nodoc
class __$$DownloadRecordImplCopyWithImpl<$Res>
    extends _$DownloadRecordCopyWithImpl<$Res, _$DownloadRecordImpl>
    implements _$$DownloadRecordImplCopyWith<$Res> {
  __$$DownloadRecordImplCopyWithImpl(
    _$DownloadRecordImpl _value,
    $Res Function(_$DownloadRecordImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DownloadRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? itemId = null,
    Object? title = null,
    Object? taskId = null,
    Object? filePath = freezed,
    Object? status = null,
    Object? progress = null,
    Object? bytesDownloaded = null,
    Object? totalBytes = null,
    Object? posterTag = freezed,
    Object? error = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _$DownloadRecordImpl(
        itemId: null == itemId
            ? _value.itemId
            : itemId // ignore: cast_nullable_to_non_nullable
                  as String,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        taskId: null == taskId
            ? _value.taskId
            : taskId // ignore: cast_nullable_to_non_nullable
                  as String,
        filePath: freezed == filePath
            ? _value.filePath
            : filePath // ignore: cast_nullable_to_non_nullable
                  as String?,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as DownloadStatus,
        progress: null == progress
            ? _value.progress
            : progress // ignore: cast_nullable_to_non_nullable
                  as double,
        bytesDownloaded: null == bytesDownloaded
            ? _value.bytesDownloaded
            : bytesDownloaded // ignore: cast_nullable_to_non_nullable
                  as int,
        totalBytes: null == totalBytes
            ? _value.totalBytes
            : totalBytes // ignore: cast_nullable_to_non_nullable
                  as int,
        posterTag: freezed == posterTag
            ? _value.posterTag
            : posterTag // ignore: cast_nullable_to_non_nullable
                  as String?,
        error: freezed == error
            ? _value.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
        updatedAt: freezed == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$DownloadRecordImpl implements _DownloadRecord {
  const _$DownloadRecordImpl({
    required this.itemId,
    required this.title,
    required this.taskId,
    this.filePath,
    this.status = DownloadStatus.enqueued,
    this.progress = 0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.posterTag,
    this.error,
    this.updatedAt,
  });

  factory _$DownloadRecordImpl.fromJson(Map<String, dynamic> json) =>
      _$$DownloadRecordImplFromJson(json);

  /// Jellyfin item id being downloaded.
  @override
  final String itemId;
  @override
  final String title;

  /// background_downloader task id.
  @override
  final String taskId;

  /// Absolute local path once (partially) written.
  @override
  final String? filePath;
  @override
  @JsonKey()
  final DownloadStatus status;

  /// 0.0–1.0.
  @override
  @JsonKey()
  final double progress;
  @override
  @JsonKey()
  final int bytesDownloaded;
  @override
  @JsonKey()
  final int totalBytes;
  @override
  final String? posterTag;
  @override
  final String? error;
  @override
  final int? updatedAt;

  @override
  String toString() {
    return 'DownloadRecord(itemId: $itemId, title: $title, taskId: $taskId, filePath: $filePath, status: $status, progress: $progress, bytesDownloaded: $bytesDownloaded, totalBytes: $totalBytes, posterTag: $posterTag, error: $error, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DownloadRecordImpl &&
            (identical(other.itemId, itemId) || other.itemId == itemId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.taskId, taskId) || other.taskId == taskId) &&
            (identical(other.filePath, filePath) ||
                other.filePath == filePath) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.progress, progress) ||
                other.progress == progress) &&
            (identical(other.bytesDownloaded, bytesDownloaded) ||
                other.bytesDownloaded == bytesDownloaded) &&
            (identical(other.totalBytes, totalBytes) ||
                other.totalBytes == totalBytes) &&
            (identical(other.posterTag, posterTag) ||
                other.posterTag == posterTag) &&
            (identical(other.error, error) || other.error == error) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    itemId,
    title,
    taskId,
    filePath,
    status,
    progress,
    bytesDownloaded,
    totalBytes,
    posterTag,
    error,
    updatedAt,
  );

  /// Create a copy of DownloadRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DownloadRecordImplCopyWith<_$DownloadRecordImpl> get copyWith =>
      __$$DownloadRecordImplCopyWithImpl<_$DownloadRecordImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$DownloadRecordImplToJson(this);
  }
}

abstract class _DownloadRecord implements DownloadRecord {
  const factory _DownloadRecord({
    required final String itemId,
    required final String title,
    required final String taskId,
    final String? filePath,
    final DownloadStatus status,
    final double progress,
    final int bytesDownloaded,
    final int totalBytes,
    final String? posterTag,
    final String? error,
    final int? updatedAt,
  }) = _$DownloadRecordImpl;

  factory _DownloadRecord.fromJson(Map<String, dynamic> json) =
      _$DownloadRecordImpl.fromJson;

  /// Jellyfin item id being downloaded.
  @override
  String get itemId;
  @override
  String get title;

  /// background_downloader task id.
  @override
  String get taskId;

  /// Absolute local path once (partially) written.
  @override
  String? get filePath;
  @override
  DownloadStatus get status;

  /// 0.0–1.0.
  @override
  double get progress;
  @override
  int get bytesDownloaded;
  @override
  int get totalBytes;
  @override
  String? get posterTag;
  @override
  String? get error;
  @override
  int? get updatedAt;

  /// Create a copy of DownloadRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DownloadRecordImplCopyWith<_$DownloadRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
