// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'stream_url.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

StreamUrl _$StreamUrlFromJson(Map<String, dynamic> json) {
  return _StreamUrl.fromJson(json);
}

/// @nodoc
mixin _$StreamUrl {
  String get url => throw _privateConstructorUsedError;
  int get expiresAt => throw _privateConstructorUsedError;

  /// Serializes this StreamUrl to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of StreamUrl
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StreamUrlCopyWith<StreamUrl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StreamUrlCopyWith<$Res> {
  factory $StreamUrlCopyWith(StreamUrl value, $Res Function(StreamUrl) then) =
      _$StreamUrlCopyWithImpl<$Res, StreamUrl>;
  @useResult
  $Res call({String url, int expiresAt});
}

/// @nodoc
class _$StreamUrlCopyWithImpl<$Res, $Val extends StreamUrl>
    implements $StreamUrlCopyWith<$Res> {
  _$StreamUrlCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StreamUrl
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? url = null, Object? expiresAt = null}) {
    return _then(
      _value.copyWith(
            url: null == url
                ? _value.url
                : url // ignore: cast_nullable_to_non_nullable
                      as String,
            expiresAt: null == expiresAt
                ? _value.expiresAt
                : expiresAt // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$StreamUrlImplCopyWith<$Res>
    implements $StreamUrlCopyWith<$Res> {
  factory _$$StreamUrlImplCopyWith(
    _$StreamUrlImpl value,
    $Res Function(_$StreamUrlImpl) then,
  ) = __$$StreamUrlImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String url, int expiresAt});
}

/// @nodoc
class __$$StreamUrlImplCopyWithImpl<$Res>
    extends _$StreamUrlCopyWithImpl<$Res, _$StreamUrlImpl>
    implements _$$StreamUrlImplCopyWith<$Res> {
  __$$StreamUrlImplCopyWithImpl(
    _$StreamUrlImpl _value,
    $Res Function(_$StreamUrlImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StreamUrl
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? url = null, Object? expiresAt = null}) {
    return _then(
      _$StreamUrlImpl(
        url: null == url
            ? _value.url
            : url // ignore: cast_nullable_to_non_nullable
                  as String,
        expiresAt: null == expiresAt
            ? _value.expiresAt
            : expiresAt // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$StreamUrlImpl implements _StreamUrl {
  const _$StreamUrlImpl({required this.url, required this.expiresAt});

  factory _$StreamUrlImpl.fromJson(Map<String, dynamic> json) =>
      _$$StreamUrlImplFromJson(json);

  @override
  final String url;
  @override
  final int expiresAt;

  @override
  String toString() {
    return 'StreamUrl(url: $url, expiresAt: $expiresAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StreamUrlImpl &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.expiresAt, expiresAt) ||
                other.expiresAt == expiresAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, url, expiresAt);

  /// Create a copy of StreamUrl
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StreamUrlImplCopyWith<_$StreamUrlImpl> get copyWith =>
      __$$StreamUrlImplCopyWithImpl<_$StreamUrlImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$StreamUrlImplToJson(this);
  }
}

abstract class _StreamUrl implements StreamUrl {
  const factory _StreamUrl({
    required final String url,
    required final int expiresAt,
  }) = _$StreamUrlImpl;

  factory _StreamUrl.fromJson(Map<String, dynamic> json) =
      _$StreamUrlImpl.fromJson;

  @override
  String get url;
  @override
  int get expiresAt;

  /// Create a copy of StreamUrl
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StreamUrlImplCopyWith<_$StreamUrlImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
