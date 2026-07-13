// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_stream.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

MediaStream _$MediaStreamFromJson(Map<String, dynamic> json) {
  return _MediaStream.fromJson(json);
}

/// @nodoc
mixin _$MediaStream {
  /// Stream index within the container (Jellyfin `Index`).
  @JsonKey(name: 'Index')
  int? get index => throw _privateConstructorUsedError;

  /// 'Video' | 'Audio' | 'Subtitle' | 'EmbeddedImage' ...
  @JsonKey(name: 'Type')
  String? get type => throw _privateConstructorUsedError;
  @JsonKey(name: 'Codec')
  String? get codec => throw _privateConstructorUsedError;
  @JsonKey(name: 'Language')
  String? get language => throw _privateConstructorUsedError;
  @JsonKey(name: 'DisplayTitle')
  String? get displayTitle => throw _privateConstructorUsedError;
  @JsonKey(name: 'Title')
  String? get title => throw _privateConstructorUsedError;
  @JsonKey(name: 'Channels')
  int? get channels => throw _privateConstructorUsedError;
  @JsonKey(name: 'Height')
  int? get height => throw _privateConstructorUsedError;
  @JsonKey(name: 'Width')
  int? get width => throw _privateConstructorUsedError;
  @JsonKey(name: 'VideoRange')
  String? get videoRange => throw _privateConstructorUsedError;
  @JsonKey(name: 'IsDefault')
  bool get isDefault => throw _privateConstructorUsedError;
  @JsonKey(name: 'IsForced')
  bool get isForced => throw _privateConstructorUsedError;
  @JsonKey(name: 'IsExternal')
  bool get isExternal => throw _privateConstructorUsedError;

  /// Serializes this MediaStream to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MediaStream
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MediaStreamCopyWith<MediaStream> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MediaStreamCopyWith<$Res> {
  factory $MediaStreamCopyWith(
    MediaStream value,
    $Res Function(MediaStream) then,
  ) = _$MediaStreamCopyWithImpl<$Res, MediaStream>;
  @useResult
  $Res call({
    @JsonKey(name: 'Index') int? index,
    @JsonKey(name: 'Type') String? type,
    @JsonKey(name: 'Codec') String? codec,
    @JsonKey(name: 'Language') String? language,
    @JsonKey(name: 'DisplayTitle') String? displayTitle,
    @JsonKey(name: 'Title') String? title,
    @JsonKey(name: 'Channels') int? channels,
    @JsonKey(name: 'Height') int? height,
    @JsonKey(name: 'Width') int? width,
    @JsonKey(name: 'VideoRange') String? videoRange,
    @JsonKey(name: 'IsDefault') bool isDefault,
    @JsonKey(name: 'IsForced') bool isForced,
    @JsonKey(name: 'IsExternal') bool isExternal,
  });
}

/// @nodoc
class _$MediaStreamCopyWithImpl<$Res, $Val extends MediaStream>
    implements $MediaStreamCopyWith<$Res> {
  _$MediaStreamCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MediaStream
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = freezed,
    Object? type = freezed,
    Object? codec = freezed,
    Object? language = freezed,
    Object? displayTitle = freezed,
    Object? title = freezed,
    Object? channels = freezed,
    Object? height = freezed,
    Object? width = freezed,
    Object? videoRange = freezed,
    Object? isDefault = null,
    Object? isForced = null,
    Object? isExternal = null,
  }) {
    return _then(
      _value.copyWith(
            index: freezed == index
                ? _value.index
                : index // ignore: cast_nullable_to_non_nullable
                      as int?,
            type: freezed == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String?,
            codec: freezed == codec
                ? _value.codec
                : codec // ignore: cast_nullable_to_non_nullable
                      as String?,
            language: freezed == language
                ? _value.language
                : language // ignore: cast_nullable_to_non_nullable
                      as String?,
            displayTitle: freezed == displayTitle
                ? _value.displayTitle
                : displayTitle // ignore: cast_nullable_to_non_nullable
                      as String?,
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            channels: freezed == channels
                ? _value.channels
                : channels // ignore: cast_nullable_to_non_nullable
                      as int?,
            height: freezed == height
                ? _value.height
                : height // ignore: cast_nullable_to_non_nullable
                      as int?,
            width: freezed == width
                ? _value.width
                : width // ignore: cast_nullable_to_non_nullable
                      as int?,
            videoRange: freezed == videoRange
                ? _value.videoRange
                : videoRange // ignore: cast_nullable_to_non_nullable
                      as String?,
            isDefault: null == isDefault
                ? _value.isDefault
                : isDefault // ignore: cast_nullable_to_non_nullable
                      as bool,
            isForced: null == isForced
                ? _value.isForced
                : isForced // ignore: cast_nullable_to_non_nullable
                      as bool,
            isExternal: null == isExternal
                ? _value.isExternal
                : isExternal // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MediaStreamImplCopyWith<$Res>
    implements $MediaStreamCopyWith<$Res> {
  factory _$$MediaStreamImplCopyWith(
    _$MediaStreamImpl value,
    $Res Function(_$MediaStreamImpl) then,
  ) = __$$MediaStreamImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'Index') int? index,
    @JsonKey(name: 'Type') String? type,
    @JsonKey(name: 'Codec') String? codec,
    @JsonKey(name: 'Language') String? language,
    @JsonKey(name: 'DisplayTitle') String? displayTitle,
    @JsonKey(name: 'Title') String? title,
    @JsonKey(name: 'Channels') int? channels,
    @JsonKey(name: 'Height') int? height,
    @JsonKey(name: 'Width') int? width,
    @JsonKey(name: 'VideoRange') String? videoRange,
    @JsonKey(name: 'IsDefault') bool isDefault,
    @JsonKey(name: 'IsForced') bool isForced,
    @JsonKey(name: 'IsExternal') bool isExternal,
  });
}

/// @nodoc
class __$$MediaStreamImplCopyWithImpl<$Res>
    extends _$MediaStreamCopyWithImpl<$Res, _$MediaStreamImpl>
    implements _$$MediaStreamImplCopyWith<$Res> {
  __$$MediaStreamImplCopyWithImpl(
    _$MediaStreamImpl _value,
    $Res Function(_$MediaStreamImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MediaStream
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = freezed,
    Object? type = freezed,
    Object? codec = freezed,
    Object? language = freezed,
    Object? displayTitle = freezed,
    Object? title = freezed,
    Object? channels = freezed,
    Object? height = freezed,
    Object? width = freezed,
    Object? videoRange = freezed,
    Object? isDefault = null,
    Object? isForced = null,
    Object? isExternal = null,
  }) {
    return _then(
      _$MediaStreamImpl(
        index: freezed == index
            ? _value.index
            : index // ignore: cast_nullable_to_non_nullable
                  as int?,
        type: freezed == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String?,
        codec: freezed == codec
            ? _value.codec
            : codec // ignore: cast_nullable_to_non_nullable
                  as String?,
        language: freezed == language
            ? _value.language
            : language // ignore: cast_nullable_to_non_nullable
                  as String?,
        displayTitle: freezed == displayTitle
            ? _value.displayTitle
            : displayTitle // ignore: cast_nullable_to_non_nullable
                  as String?,
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        channels: freezed == channels
            ? _value.channels
            : channels // ignore: cast_nullable_to_non_nullable
                  as int?,
        height: freezed == height
            ? _value.height
            : height // ignore: cast_nullable_to_non_nullable
                  as int?,
        width: freezed == width
            ? _value.width
            : width // ignore: cast_nullable_to_non_nullable
                  as int?,
        videoRange: freezed == videoRange
            ? _value.videoRange
            : videoRange // ignore: cast_nullable_to_non_nullable
                  as String?,
        isDefault: null == isDefault
            ? _value.isDefault
            : isDefault // ignore: cast_nullable_to_non_nullable
                  as bool,
        isForced: null == isForced
            ? _value.isForced
            : isForced // ignore: cast_nullable_to_non_nullable
                  as bool,
        isExternal: null == isExternal
            ? _value.isExternal
            : isExternal // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$MediaStreamImpl implements _MediaStream {
  const _$MediaStreamImpl({
    @JsonKey(name: 'Index') this.index,
    @JsonKey(name: 'Type') this.type,
    @JsonKey(name: 'Codec') this.codec,
    @JsonKey(name: 'Language') this.language,
    @JsonKey(name: 'DisplayTitle') this.displayTitle,
    @JsonKey(name: 'Title') this.title,
    @JsonKey(name: 'Channels') this.channels,
    @JsonKey(name: 'Height') this.height,
    @JsonKey(name: 'Width') this.width,
    @JsonKey(name: 'VideoRange') this.videoRange,
    @JsonKey(name: 'IsDefault') this.isDefault = false,
    @JsonKey(name: 'IsForced') this.isForced = false,
    @JsonKey(name: 'IsExternal') this.isExternal = false,
  });

  factory _$MediaStreamImpl.fromJson(Map<String, dynamic> json) =>
      _$$MediaStreamImplFromJson(json);

  /// Stream index within the container (Jellyfin `Index`).
  @override
  @JsonKey(name: 'Index')
  final int? index;

  /// 'Video' | 'Audio' | 'Subtitle' | 'EmbeddedImage' ...
  @override
  @JsonKey(name: 'Type')
  final String? type;
  @override
  @JsonKey(name: 'Codec')
  final String? codec;
  @override
  @JsonKey(name: 'Language')
  final String? language;
  @override
  @JsonKey(name: 'DisplayTitle')
  final String? displayTitle;
  @override
  @JsonKey(name: 'Title')
  final String? title;
  @override
  @JsonKey(name: 'Channels')
  final int? channels;
  @override
  @JsonKey(name: 'Height')
  final int? height;
  @override
  @JsonKey(name: 'Width')
  final int? width;
  @override
  @JsonKey(name: 'VideoRange')
  final String? videoRange;
  @override
  @JsonKey(name: 'IsDefault')
  final bool isDefault;
  @override
  @JsonKey(name: 'IsForced')
  final bool isForced;
  @override
  @JsonKey(name: 'IsExternal')
  final bool isExternal;

  @override
  String toString() {
    return 'MediaStream(index: $index, type: $type, codec: $codec, language: $language, displayTitle: $displayTitle, title: $title, channels: $channels, height: $height, width: $width, videoRange: $videoRange, isDefault: $isDefault, isForced: $isForced, isExternal: $isExternal)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaStreamImpl &&
            (identical(other.index, index) || other.index == index) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.codec, codec) || other.codec == codec) &&
            (identical(other.language, language) ||
                other.language == language) &&
            (identical(other.displayTitle, displayTitle) ||
                other.displayTitle == displayTitle) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.channels, channels) ||
                other.channels == channels) &&
            (identical(other.height, height) || other.height == height) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.videoRange, videoRange) ||
                other.videoRange == videoRange) &&
            (identical(other.isDefault, isDefault) ||
                other.isDefault == isDefault) &&
            (identical(other.isForced, isForced) ||
                other.isForced == isForced) &&
            (identical(other.isExternal, isExternal) ||
                other.isExternal == isExternal));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    index,
    type,
    codec,
    language,
    displayTitle,
    title,
    channels,
    height,
    width,
    videoRange,
    isDefault,
    isForced,
    isExternal,
  );

  /// Create a copy of MediaStream
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaStreamImplCopyWith<_$MediaStreamImpl> get copyWith =>
      __$$MediaStreamImplCopyWithImpl<_$MediaStreamImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MediaStreamImplToJson(this);
  }
}

abstract class _MediaStream implements MediaStream {
  const factory _MediaStream({
    @JsonKey(name: 'Index') final int? index,
    @JsonKey(name: 'Type') final String? type,
    @JsonKey(name: 'Codec') final String? codec,
    @JsonKey(name: 'Language') final String? language,
    @JsonKey(name: 'DisplayTitle') final String? displayTitle,
    @JsonKey(name: 'Title') final String? title,
    @JsonKey(name: 'Channels') final int? channels,
    @JsonKey(name: 'Height') final int? height,
    @JsonKey(name: 'Width') final int? width,
    @JsonKey(name: 'VideoRange') final String? videoRange,
    @JsonKey(name: 'IsDefault') final bool isDefault,
    @JsonKey(name: 'IsForced') final bool isForced,
    @JsonKey(name: 'IsExternal') final bool isExternal,
  }) = _$MediaStreamImpl;

  factory _MediaStream.fromJson(Map<String, dynamic> json) =
      _$MediaStreamImpl.fromJson;

  /// Stream index within the container (Jellyfin `Index`).
  @override
  @JsonKey(name: 'Index')
  int? get index;

  /// 'Video' | 'Audio' | 'Subtitle' | 'EmbeddedImage' ...
  @override
  @JsonKey(name: 'Type')
  String? get type;
  @override
  @JsonKey(name: 'Codec')
  String? get codec;
  @override
  @JsonKey(name: 'Language')
  String? get language;
  @override
  @JsonKey(name: 'DisplayTitle')
  String? get displayTitle;
  @override
  @JsonKey(name: 'Title')
  String? get title;
  @override
  @JsonKey(name: 'Channels')
  int? get channels;
  @override
  @JsonKey(name: 'Height')
  int? get height;
  @override
  @JsonKey(name: 'Width')
  int? get width;
  @override
  @JsonKey(name: 'VideoRange')
  String? get videoRange;
  @override
  @JsonKey(name: 'IsDefault')
  bool get isDefault;
  @override
  @JsonKey(name: 'IsForced')
  bool get isForced;
  @override
  @JsonKey(name: 'IsExternal')
  bool get isExternal;

  /// Create a copy of MediaStream
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MediaStreamImplCopyWith<_$MediaStreamImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
