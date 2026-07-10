// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_source.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

MediaSource _$MediaSourceFromJson(Map<String, dynamic> json) {
  return _MediaSource.fromJson(json);
}

/// @nodoc
mixin _$MediaSource {
  @JsonKey(name: 'Id')
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'Protocol')
  String? get protocol => throw _privateConstructorUsedError;
  @JsonKey(name: 'Container')
  String? get container => throw _privateConstructorUsedError;
  @JsonKey(name: 'Path')
  String? get path => throw _privateConstructorUsedError;
  @JsonKey(name: 'Name')
  String? get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'Size')
  int? get size => throw _privateConstructorUsedError;
  @JsonKey(name: 'RunTimeTicks')
  int? get runTimeTicks => throw _privateConstructorUsedError;
  @JsonKey(name: 'SupportsDirectPlay')
  bool get supportsDirectPlay => throw _privateConstructorUsedError;
  @JsonKey(name: 'SupportsDirectStream')
  bool get supportsDirectStream => throw _privateConstructorUsedError;
  @JsonKey(name: 'SupportsTranscoding')
  bool get supportsTranscoding => throw _privateConstructorUsedError;
  @JsonKey(name: 'MediaStreams')
  List<MediaStream> get mediaStreams => throw _privateConstructorUsedError;

  /// Serializes this MediaSource to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MediaSource
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MediaSourceCopyWith<MediaSource> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MediaSourceCopyWith<$Res> {
  factory $MediaSourceCopyWith(
    MediaSource value,
    $Res Function(MediaSource) then,
  ) = _$MediaSourceCopyWithImpl<$Res, MediaSource>;
  @useResult
  $Res call({
    @JsonKey(name: 'Id') String id,
    @JsonKey(name: 'Protocol') String? protocol,
    @JsonKey(name: 'Container') String? container,
    @JsonKey(name: 'Path') String? path,
    @JsonKey(name: 'Name') String? name,
    @JsonKey(name: 'Size') int? size,
    @JsonKey(name: 'RunTimeTicks') int? runTimeTicks,
    @JsonKey(name: 'SupportsDirectPlay') bool supportsDirectPlay,
    @JsonKey(name: 'SupportsDirectStream') bool supportsDirectStream,
    @JsonKey(name: 'SupportsTranscoding') bool supportsTranscoding,
    @JsonKey(name: 'MediaStreams') List<MediaStream> mediaStreams,
  });
}

/// @nodoc
class _$MediaSourceCopyWithImpl<$Res, $Val extends MediaSource>
    implements $MediaSourceCopyWith<$Res> {
  _$MediaSourceCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MediaSource
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? protocol = freezed,
    Object? container = freezed,
    Object? path = freezed,
    Object? name = freezed,
    Object? size = freezed,
    Object? runTimeTicks = freezed,
    Object? supportsDirectPlay = null,
    Object? supportsDirectStream = null,
    Object? supportsTranscoding = null,
    Object? mediaStreams = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            protocol: freezed == protocol
                ? _value.protocol
                : protocol // ignore: cast_nullable_to_non_nullable
                      as String?,
            container: freezed == container
                ? _value.container
                : container // ignore: cast_nullable_to_non_nullable
                      as String?,
            path: freezed == path
                ? _value.path
                : path // ignore: cast_nullable_to_non_nullable
                      as String?,
            name: freezed == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String?,
            size: freezed == size
                ? _value.size
                : size // ignore: cast_nullable_to_non_nullable
                      as int?,
            runTimeTicks: freezed == runTimeTicks
                ? _value.runTimeTicks
                : runTimeTicks // ignore: cast_nullable_to_non_nullable
                      as int?,
            supportsDirectPlay: null == supportsDirectPlay
                ? _value.supportsDirectPlay
                : supportsDirectPlay // ignore: cast_nullable_to_non_nullable
                      as bool,
            supportsDirectStream: null == supportsDirectStream
                ? _value.supportsDirectStream
                : supportsDirectStream // ignore: cast_nullable_to_non_nullable
                      as bool,
            supportsTranscoding: null == supportsTranscoding
                ? _value.supportsTranscoding
                : supportsTranscoding // ignore: cast_nullable_to_non_nullable
                      as bool,
            mediaStreams: null == mediaStreams
                ? _value.mediaStreams
                : mediaStreams // ignore: cast_nullable_to_non_nullable
                      as List<MediaStream>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MediaSourceImplCopyWith<$Res>
    implements $MediaSourceCopyWith<$Res> {
  factory _$$MediaSourceImplCopyWith(
    _$MediaSourceImpl value,
    $Res Function(_$MediaSourceImpl) then,
  ) = __$$MediaSourceImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'Id') String id,
    @JsonKey(name: 'Protocol') String? protocol,
    @JsonKey(name: 'Container') String? container,
    @JsonKey(name: 'Path') String? path,
    @JsonKey(name: 'Name') String? name,
    @JsonKey(name: 'Size') int? size,
    @JsonKey(name: 'RunTimeTicks') int? runTimeTicks,
    @JsonKey(name: 'SupportsDirectPlay') bool supportsDirectPlay,
    @JsonKey(name: 'SupportsDirectStream') bool supportsDirectStream,
    @JsonKey(name: 'SupportsTranscoding') bool supportsTranscoding,
    @JsonKey(name: 'MediaStreams') List<MediaStream> mediaStreams,
  });
}

/// @nodoc
class __$$MediaSourceImplCopyWithImpl<$Res>
    extends _$MediaSourceCopyWithImpl<$Res, _$MediaSourceImpl>
    implements _$$MediaSourceImplCopyWith<$Res> {
  __$$MediaSourceImplCopyWithImpl(
    _$MediaSourceImpl _value,
    $Res Function(_$MediaSourceImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MediaSource
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? protocol = freezed,
    Object? container = freezed,
    Object? path = freezed,
    Object? name = freezed,
    Object? size = freezed,
    Object? runTimeTicks = freezed,
    Object? supportsDirectPlay = null,
    Object? supportsDirectStream = null,
    Object? supportsTranscoding = null,
    Object? mediaStreams = null,
  }) {
    return _then(
      _$MediaSourceImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        protocol: freezed == protocol
            ? _value.protocol
            : protocol // ignore: cast_nullable_to_non_nullable
                  as String?,
        container: freezed == container
            ? _value.container
            : container // ignore: cast_nullable_to_non_nullable
                  as String?,
        path: freezed == path
            ? _value.path
            : path // ignore: cast_nullable_to_non_nullable
                  as String?,
        name: freezed == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String?,
        size: freezed == size
            ? _value.size
            : size // ignore: cast_nullable_to_non_nullable
                  as int?,
        runTimeTicks: freezed == runTimeTicks
            ? _value.runTimeTicks
            : runTimeTicks // ignore: cast_nullable_to_non_nullable
                  as int?,
        supportsDirectPlay: null == supportsDirectPlay
            ? _value.supportsDirectPlay
            : supportsDirectPlay // ignore: cast_nullable_to_non_nullable
                  as bool,
        supportsDirectStream: null == supportsDirectStream
            ? _value.supportsDirectStream
            : supportsDirectStream // ignore: cast_nullable_to_non_nullable
                  as bool,
        supportsTranscoding: null == supportsTranscoding
            ? _value.supportsTranscoding
            : supportsTranscoding // ignore: cast_nullable_to_non_nullable
                  as bool,
        mediaStreams: null == mediaStreams
            ? _value._mediaStreams
            : mediaStreams // ignore: cast_nullable_to_non_nullable
                  as List<MediaStream>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$MediaSourceImpl implements _MediaSource {
  const _$MediaSourceImpl({
    @JsonKey(name: 'Id') required this.id,
    @JsonKey(name: 'Protocol') this.protocol,
    @JsonKey(name: 'Container') this.container,
    @JsonKey(name: 'Path') this.path,
    @JsonKey(name: 'Name') this.name,
    @JsonKey(name: 'Size') this.size,
    @JsonKey(name: 'RunTimeTicks') this.runTimeTicks,
    @JsonKey(name: 'SupportsDirectPlay') this.supportsDirectPlay = false,
    @JsonKey(name: 'SupportsDirectStream') this.supportsDirectStream = false,
    @JsonKey(name: 'SupportsTranscoding') this.supportsTranscoding = false,
    @JsonKey(name: 'MediaStreams')
    final List<MediaStream> mediaStreams = const <MediaStream>[],
  }) : _mediaStreams = mediaStreams;

  factory _$MediaSourceImpl.fromJson(Map<String, dynamic> json) =>
      _$$MediaSourceImplFromJson(json);

  @override
  @JsonKey(name: 'Id')
  final String id;
  @override
  @JsonKey(name: 'Protocol')
  final String? protocol;
  @override
  @JsonKey(name: 'Container')
  final String? container;
  @override
  @JsonKey(name: 'Path')
  final String? path;
  @override
  @JsonKey(name: 'Name')
  final String? name;
  @override
  @JsonKey(name: 'Size')
  final int? size;
  @override
  @JsonKey(name: 'RunTimeTicks')
  final int? runTimeTicks;
  @override
  @JsonKey(name: 'SupportsDirectPlay')
  final bool supportsDirectPlay;
  @override
  @JsonKey(name: 'SupportsDirectStream')
  final bool supportsDirectStream;
  @override
  @JsonKey(name: 'SupportsTranscoding')
  final bool supportsTranscoding;
  final List<MediaStream> _mediaStreams;
  @override
  @JsonKey(name: 'MediaStreams')
  List<MediaStream> get mediaStreams {
    if (_mediaStreams is EqualUnmodifiableListView) return _mediaStreams;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_mediaStreams);
  }

  @override
  String toString() {
    return 'MediaSource(id: $id, protocol: $protocol, container: $container, path: $path, name: $name, size: $size, runTimeTicks: $runTimeTicks, supportsDirectPlay: $supportsDirectPlay, supportsDirectStream: $supportsDirectStream, supportsTranscoding: $supportsTranscoding, mediaStreams: $mediaStreams)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaSourceImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.protocol, protocol) ||
                other.protocol == protocol) &&
            (identical(other.container, container) ||
                other.container == container) &&
            (identical(other.path, path) || other.path == path) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.size, size) || other.size == size) &&
            (identical(other.runTimeTicks, runTimeTicks) ||
                other.runTimeTicks == runTimeTicks) &&
            (identical(other.supportsDirectPlay, supportsDirectPlay) ||
                other.supportsDirectPlay == supportsDirectPlay) &&
            (identical(other.supportsDirectStream, supportsDirectStream) ||
                other.supportsDirectStream == supportsDirectStream) &&
            (identical(other.supportsTranscoding, supportsTranscoding) ||
                other.supportsTranscoding == supportsTranscoding) &&
            const DeepCollectionEquality().equals(
              other._mediaStreams,
              _mediaStreams,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    protocol,
    container,
    path,
    name,
    size,
    runTimeTicks,
    supportsDirectPlay,
    supportsDirectStream,
    supportsTranscoding,
    const DeepCollectionEquality().hash(_mediaStreams),
  );

  /// Create a copy of MediaSource
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaSourceImplCopyWith<_$MediaSourceImpl> get copyWith =>
      __$$MediaSourceImplCopyWithImpl<_$MediaSourceImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MediaSourceImplToJson(this);
  }
}

abstract class _MediaSource implements MediaSource {
  const factory _MediaSource({
    @JsonKey(name: 'Id') required final String id,
    @JsonKey(name: 'Protocol') final String? protocol,
    @JsonKey(name: 'Container') final String? container,
    @JsonKey(name: 'Path') final String? path,
    @JsonKey(name: 'Name') final String? name,
    @JsonKey(name: 'Size') final int? size,
    @JsonKey(name: 'RunTimeTicks') final int? runTimeTicks,
    @JsonKey(name: 'SupportsDirectPlay') final bool supportsDirectPlay,
    @JsonKey(name: 'SupportsDirectStream') final bool supportsDirectStream,
    @JsonKey(name: 'SupportsTranscoding') final bool supportsTranscoding,
    @JsonKey(name: 'MediaStreams') final List<MediaStream> mediaStreams,
  }) = _$MediaSourceImpl;

  factory _MediaSource.fromJson(Map<String, dynamic> json) =
      _$MediaSourceImpl.fromJson;

  @override
  @JsonKey(name: 'Id')
  String get id;
  @override
  @JsonKey(name: 'Protocol')
  String? get protocol;
  @override
  @JsonKey(name: 'Container')
  String? get container;
  @override
  @JsonKey(name: 'Path')
  String? get path;
  @override
  @JsonKey(name: 'Name')
  String? get name;
  @override
  @JsonKey(name: 'Size')
  int? get size;
  @override
  @JsonKey(name: 'RunTimeTicks')
  int? get runTimeTicks;
  @override
  @JsonKey(name: 'SupportsDirectPlay')
  bool get supportsDirectPlay;
  @override
  @JsonKey(name: 'SupportsDirectStream')
  bool get supportsDirectStream;
  @override
  @JsonKey(name: 'SupportsTranscoding')
  bool get supportsTranscoding;
  @override
  @JsonKey(name: 'MediaStreams')
  List<MediaStream> get mediaStreams;

  /// Create a copy of MediaSource
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MediaSourceImplCopyWith<_$MediaSourceImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
