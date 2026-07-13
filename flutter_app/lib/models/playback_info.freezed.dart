// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playback_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

PlaybackTrack _$PlaybackTrackFromJson(Map<String, dynamic> json) {
  return _PlaybackTrack.fromJson(json);
}

/// @nodoc
mixin _$PlaybackTrack {
  @JsonKey(name: 'index')
  int get index => throw _privateConstructorUsedError;
  @JsonKey(name: 'displayTitle')
  String? get displayTitle => throw _privateConstructorUsedError;
  @JsonKey(name: 'title')
  String? get title => throw _privateConstructorUsedError;
  @JsonKey(name: 'language')
  String? get language => throw _privateConstructorUsedError;
  @JsonKey(name: 'codec')
  String? get codec => throw _privateConstructorUsedError;
  @JsonKey(name: 'isDefault')
  bool get isDefault => throw _privateConstructorUsedError;
  @JsonKey(name: 'isForced')
  bool get isForced => throw _privateConstructorUsedError;
  @JsonKey(name: 'isExternal')
  bool get isExternal => throw _privateConstructorUsedError;
  @JsonKey(name: 'deliveryUrl')
  String? get deliveryUrl => throw _privateConstructorUsedError;

  /// Serializes this PlaybackTrack to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PlaybackTrack
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlaybackTrackCopyWith<PlaybackTrack> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlaybackTrackCopyWith<$Res> {
  factory $PlaybackTrackCopyWith(
    PlaybackTrack value,
    $Res Function(PlaybackTrack) then,
  ) = _$PlaybackTrackCopyWithImpl<$Res, PlaybackTrack>;
  @useResult
  $Res call({
    @JsonKey(name: 'index') int index,
    @JsonKey(name: 'displayTitle') String? displayTitle,
    @JsonKey(name: 'title') String? title,
    @JsonKey(name: 'language') String? language,
    @JsonKey(name: 'codec') String? codec,
    @JsonKey(name: 'isDefault') bool isDefault,
    @JsonKey(name: 'isForced') bool isForced,
    @JsonKey(name: 'isExternal') bool isExternal,
    @JsonKey(name: 'deliveryUrl') String? deliveryUrl,
  });
}

/// @nodoc
class _$PlaybackTrackCopyWithImpl<$Res, $Val extends PlaybackTrack>
    implements $PlaybackTrackCopyWith<$Res> {
  _$PlaybackTrackCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlaybackTrack
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? displayTitle = freezed,
    Object? title = freezed,
    Object? language = freezed,
    Object? codec = freezed,
    Object? isDefault = null,
    Object? isForced = null,
    Object? isExternal = null,
    Object? deliveryUrl = freezed,
  }) {
    return _then(
      _value.copyWith(
            index: null == index
                ? _value.index
                : index // ignore: cast_nullable_to_non_nullable
                      as int,
            displayTitle: freezed == displayTitle
                ? _value.displayTitle
                : displayTitle // ignore: cast_nullable_to_non_nullable
                      as String?,
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            language: freezed == language
                ? _value.language
                : language // ignore: cast_nullable_to_non_nullable
                      as String?,
            codec: freezed == codec
                ? _value.codec
                : codec // ignore: cast_nullable_to_non_nullable
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
            deliveryUrl: freezed == deliveryUrl
                ? _value.deliveryUrl
                : deliveryUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PlaybackTrackImplCopyWith<$Res>
    implements $PlaybackTrackCopyWith<$Res> {
  factory _$$PlaybackTrackImplCopyWith(
    _$PlaybackTrackImpl value,
    $Res Function(_$PlaybackTrackImpl) then,
  ) = __$$PlaybackTrackImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'index') int index,
    @JsonKey(name: 'displayTitle') String? displayTitle,
    @JsonKey(name: 'title') String? title,
    @JsonKey(name: 'language') String? language,
    @JsonKey(name: 'codec') String? codec,
    @JsonKey(name: 'isDefault') bool isDefault,
    @JsonKey(name: 'isForced') bool isForced,
    @JsonKey(name: 'isExternal') bool isExternal,
    @JsonKey(name: 'deliveryUrl') String? deliveryUrl,
  });
}

/// @nodoc
class __$$PlaybackTrackImplCopyWithImpl<$Res>
    extends _$PlaybackTrackCopyWithImpl<$Res, _$PlaybackTrackImpl>
    implements _$$PlaybackTrackImplCopyWith<$Res> {
  __$$PlaybackTrackImplCopyWithImpl(
    _$PlaybackTrackImpl _value,
    $Res Function(_$PlaybackTrackImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlaybackTrack
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? displayTitle = freezed,
    Object? title = freezed,
    Object? language = freezed,
    Object? codec = freezed,
    Object? isDefault = null,
    Object? isForced = null,
    Object? isExternal = null,
    Object? deliveryUrl = freezed,
  }) {
    return _then(
      _$PlaybackTrackImpl(
        index: null == index
            ? _value.index
            : index // ignore: cast_nullable_to_non_nullable
                  as int,
        displayTitle: freezed == displayTitle
            ? _value.displayTitle
            : displayTitle // ignore: cast_nullable_to_non_nullable
                  as String?,
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        language: freezed == language
            ? _value.language
            : language // ignore: cast_nullable_to_non_nullable
                  as String?,
        codec: freezed == codec
            ? _value.codec
            : codec // ignore: cast_nullable_to_non_nullable
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
        deliveryUrl: freezed == deliveryUrl
            ? _value.deliveryUrl
            : deliveryUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$PlaybackTrackImpl implements _PlaybackTrack {
  const _$PlaybackTrackImpl({
    @JsonKey(name: 'index') required this.index,
    @JsonKey(name: 'displayTitle') this.displayTitle,
    @JsonKey(name: 'title') this.title,
    @JsonKey(name: 'language') this.language,
    @JsonKey(name: 'codec') this.codec,
    @JsonKey(name: 'isDefault') this.isDefault = false,
    @JsonKey(name: 'isForced') this.isForced = false,
    @JsonKey(name: 'isExternal') this.isExternal = false,
    @JsonKey(name: 'deliveryUrl') this.deliveryUrl,
  });

  factory _$PlaybackTrackImpl.fromJson(Map<String, dynamic> json) =>
      _$$PlaybackTrackImplFromJson(json);

  @override
  @JsonKey(name: 'index')
  final int index;
  @override
  @JsonKey(name: 'displayTitle')
  final String? displayTitle;
  @override
  @JsonKey(name: 'title')
  final String? title;
  @override
  @JsonKey(name: 'language')
  final String? language;
  @override
  @JsonKey(name: 'codec')
  final String? codec;
  @override
  @JsonKey(name: 'isDefault')
  final bool isDefault;
  @override
  @JsonKey(name: 'isForced')
  final bool isForced;
  @override
  @JsonKey(name: 'isExternal')
  final bool isExternal;
  @override
  @JsonKey(name: 'deliveryUrl')
  final String? deliveryUrl;

  @override
  String toString() {
    return 'PlaybackTrack(index: $index, displayTitle: $displayTitle, title: $title, language: $language, codec: $codec, isDefault: $isDefault, isForced: $isForced, isExternal: $isExternal, deliveryUrl: $deliveryUrl)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaybackTrackImpl &&
            (identical(other.index, index) || other.index == index) &&
            (identical(other.displayTitle, displayTitle) ||
                other.displayTitle == displayTitle) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.language, language) ||
                other.language == language) &&
            (identical(other.codec, codec) || other.codec == codec) &&
            (identical(other.isDefault, isDefault) ||
                other.isDefault == isDefault) &&
            (identical(other.isForced, isForced) ||
                other.isForced == isForced) &&
            (identical(other.isExternal, isExternal) ||
                other.isExternal == isExternal) &&
            (identical(other.deliveryUrl, deliveryUrl) ||
                other.deliveryUrl == deliveryUrl));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    index,
    displayTitle,
    title,
    language,
    codec,
    isDefault,
    isForced,
    isExternal,
    deliveryUrl,
  );

  /// Create a copy of PlaybackTrack
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlaybackTrackImplCopyWith<_$PlaybackTrackImpl> get copyWith =>
      __$$PlaybackTrackImplCopyWithImpl<_$PlaybackTrackImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PlaybackTrackImplToJson(this);
  }
}

abstract class _PlaybackTrack implements PlaybackTrack {
  const factory _PlaybackTrack({
    @JsonKey(name: 'index') required final int index,
    @JsonKey(name: 'displayTitle') final String? displayTitle,
    @JsonKey(name: 'title') final String? title,
    @JsonKey(name: 'language') final String? language,
    @JsonKey(name: 'codec') final String? codec,
    @JsonKey(name: 'isDefault') final bool isDefault,
    @JsonKey(name: 'isForced') final bool isForced,
    @JsonKey(name: 'isExternal') final bool isExternal,
    @JsonKey(name: 'deliveryUrl') final String? deliveryUrl,
  }) = _$PlaybackTrackImpl;

  factory _PlaybackTrack.fromJson(Map<String, dynamic> json) =
      _$PlaybackTrackImpl.fromJson;

  @override
  @JsonKey(name: 'index')
  int get index;
  @override
  @JsonKey(name: 'displayTitle')
  String? get displayTitle;
  @override
  @JsonKey(name: 'title')
  String? get title;
  @override
  @JsonKey(name: 'language')
  String? get language;
  @override
  @JsonKey(name: 'codec')
  String? get codec;
  @override
  @JsonKey(name: 'isDefault')
  bool get isDefault;
  @override
  @JsonKey(name: 'isForced')
  bool get isForced;
  @override
  @JsonKey(name: 'isExternal')
  bool get isExternal;
  @override
  @JsonKey(name: 'deliveryUrl')
  String? get deliveryUrl;

  /// Create a copy of PlaybackTrack
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlaybackTrackImplCopyWith<_$PlaybackTrackImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PlaybackInfo _$PlaybackInfoFromJson(Map<String, dynamic> json) {
  return _PlaybackInfo.fromJson(json);
}

/// @nodoc
mixin _$PlaybackInfo {
  @JsonKey(name: 'mediaSourceId')
  String? get mediaSourceId => throw _privateConstructorUsedError;
  @JsonKey(name: 'audioStreams')
  List<PlaybackTrack> get audioStreams => throw _privateConstructorUsedError;
  @JsonKey(name: 'subtitleStreams')
  List<PlaybackTrack> get subtitleStreams => throw _privateConstructorUsedError;
  @JsonKey(name: 'selectedAudioIndex')
  int? get selectedAudioIndex => throw _privateConstructorUsedError;
  @JsonKey(name: 'selectedSubtitleIndex')
  int? get selectedSubtitleIndex => throw _privateConstructorUsedError;

  /// Serializes this PlaybackInfo to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PlaybackInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlaybackInfoCopyWith<PlaybackInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlaybackInfoCopyWith<$Res> {
  factory $PlaybackInfoCopyWith(
    PlaybackInfo value,
    $Res Function(PlaybackInfo) then,
  ) = _$PlaybackInfoCopyWithImpl<$Res, PlaybackInfo>;
  @useResult
  $Res call({
    @JsonKey(name: 'mediaSourceId') String? mediaSourceId,
    @JsonKey(name: 'audioStreams') List<PlaybackTrack> audioStreams,
    @JsonKey(name: 'subtitleStreams') List<PlaybackTrack> subtitleStreams,
    @JsonKey(name: 'selectedAudioIndex') int? selectedAudioIndex,
    @JsonKey(name: 'selectedSubtitleIndex') int? selectedSubtitleIndex,
  });
}

/// @nodoc
class _$PlaybackInfoCopyWithImpl<$Res, $Val extends PlaybackInfo>
    implements $PlaybackInfoCopyWith<$Res> {
  _$PlaybackInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlaybackInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mediaSourceId = freezed,
    Object? audioStreams = null,
    Object? subtitleStreams = null,
    Object? selectedAudioIndex = freezed,
    Object? selectedSubtitleIndex = freezed,
  }) {
    return _then(
      _value.copyWith(
            mediaSourceId: freezed == mediaSourceId
                ? _value.mediaSourceId
                : mediaSourceId // ignore: cast_nullable_to_non_nullable
                      as String?,
            audioStreams: null == audioStreams
                ? _value.audioStreams
                : audioStreams // ignore: cast_nullable_to_non_nullable
                      as List<PlaybackTrack>,
            subtitleStreams: null == subtitleStreams
                ? _value.subtitleStreams
                : subtitleStreams // ignore: cast_nullable_to_non_nullable
                      as List<PlaybackTrack>,
            selectedAudioIndex: freezed == selectedAudioIndex
                ? _value.selectedAudioIndex
                : selectedAudioIndex // ignore: cast_nullable_to_non_nullable
                      as int?,
            selectedSubtitleIndex: freezed == selectedSubtitleIndex
                ? _value.selectedSubtitleIndex
                : selectedSubtitleIndex // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PlaybackInfoImplCopyWith<$Res>
    implements $PlaybackInfoCopyWith<$Res> {
  factory _$$PlaybackInfoImplCopyWith(
    _$PlaybackInfoImpl value,
    $Res Function(_$PlaybackInfoImpl) then,
  ) = __$$PlaybackInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'mediaSourceId') String? mediaSourceId,
    @JsonKey(name: 'audioStreams') List<PlaybackTrack> audioStreams,
    @JsonKey(name: 'subtitleStreams') List<PlaybackTrack> subtitleStreams,
    @JsonKey(name: 'selectedAudioIndex') int? selectedAudioIndex,
    @JsonKey(name: 'selectedSubtitleIndex') int? selectedSubtitleIndex,
  });
}

/// @nodoc
class __$$PlaybackInfoImplCopyWithImpl<$Res>
    extends _$PlaybackInfoCopyWithImpl<$Res, _$PlaybackInfoImpl>
    implements _$$PlaybackInfoImplCopyWith<$Res> {
  __$$PlaybackInfoImplCopyWithImpl(
    _$PlaybackInfoImpl _value,
    $Res Function(_$PlaybackInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlaybackInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mediaSourceId = freezed,
    Object? audioStreams = null,
    Object? subtitleStreams = null,
    Object? selectedAudioIndex = freezed,
    Object? selectedSubtitleIndex = freezed,
  }) {
    return _then(
      _$PlaybackInfoImpl(
        mediaSourceId: freezed == mediaSourceId
            ? _value.mediaSourceId
            : mediaSourceId // ignore: cast_nullable_to_non_nullable
                  as String?,
        audioStreams: null == audioStreams
            ? _value._audioStreams
            : audioStreams // ignore: cast_nullable_to_non_nullable
                  as List<PlaybackTrack>,
        subtitleStreams: null == subtitleStreams
            ? _value._subtitleStreams
            : subtitleStreams // ignore: cast_nullable_to_non_nullable
                  as List<PlaybackTrack>,
        selectedAudioIndex: freezed == selectedAudioIndex
            ? _value.selectedAudioIndex
            : selectedAudioIndex // ignore: cast_nullable_to_non_nullable
                  as int?,
        selectedSubtitleIndex: freezed == selectedSubtitleIndex
            ? _value.selectedSubtitleIndex
            : selectedSubtitleIndex // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$PlaybackInfoImpl implements _PlaybackInfo {
  const _$PlaybackInfoImpl({
    @JsonKey(name: 'mediaSourceId') this.mediaSourceId,
    @JsonKey(name: 'audioStreams')
    final List<PlaybackTrack> audioStreams = const <PlaybackTrack>[],
    @JsonKey(name: 'subtitleStreams')
    final List<PlaybackTrack> subtitleStreams = const <PlaybackTrack>[],
    @JsonKey(name: 'selectedAudioIndex') this.selectedAudioIndex,
    @JsonKey(name: 'selectedSubtitleIndex') this.selectedSubtitleIndex,
  }) : _audioStreams = audioStreams,
       _subtitleStreams = subtitleStreams;

  factory _$PlaybackInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$PlaybackInfoImplFromJson(json);

  @override
  @JsonKey(name: 'mediaSourceId')
  final String? mediaSourceId;
  final List<PlaybackTrack> _audioStreams;
  @override
  @JsonKey(name: 'audioStreams')
  List<PlaybackTrack> get audioStreams {
    if (_audioStreams is EqualUnmodifiableListView) return _audioStreams;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_audioStreams);
  }

  final List<PlaybackTrack> _subtitleStreams;
  @override
  @JsonKey(name: 'subtitleStreams')
  List<PlaybackTrack> get subtitleStreams {
    if (_subtitleStreams is EqualUnmodifiableListView) return _subtitleStreams;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_subtitleStreams);
  }

  @override
  @JsonKey(name: 'selectedAudioIndex')
  final int? selectedAudioIndex;
  @override
  @JsonKey(name: 'selectedSubtitleIndex')
  final int? selectedSubtitleIndex;

  @override
  String toString() {
    return 'PlaybackInfo(mediaSourceId: $mediaSourceId, audioStreams: $audioStreams, subtitleStreams: $subtitleStreams, selectedAudioIndex: $selectedAudioIndex, selectedSubtitleIndex: $selectedSubtitleIndex)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaybackInfoImpl &&
            (identical(other.mediaSourceId, mediaSourceId) ||
                other.mediaSourceId == mediaSourceId) &&
            const DeepCollectionEquality().equals(
              other._audioStreams,
              _audioStreams,
            ) &&
            const DeepCollectionEquality().equals(
              other._subtitleStreams,
              _subtitleStreams,
            ) &&
            (identical(other.selectedAudioIndex, selectedAudioIndex) ||
                other.selectedAudioIndex == selectedAudioIndex) &&
            (identical(other.selectedSubtitleIndex, selectedSubtitleIndex) ||
                other.selectedSubtitleIndex == selectedSubtitleIndex));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    mediaSourceId,
    const DeepCollectionEquality().hash(_audioStreams),
    const DeepCollectionEquality().hash(_subtitleStreams),
    selectedAudioIndex,
    selectedSubtitleIndex,
  );

  /// Create a copy of PlaybackInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlaybackInfoImplCopyWith<_$PlaybackInfoImpl> get copyWith =>
      __$$PlaybackInfoImplCopyWithImpl<_$PlaybackInfoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PlaybackInfoImplToJson(this);
  }
}

abstract class _PlaybackInfo implements PlaybackInfo {
  const factory _PlaybackInfo({
    @JsonKey(name: 'mediaSourceId') final String? mediaSourceId,
    @JsonKey(name: 'audioStreams') final List<PlaybackTrack> audioStreams,
    @JsonKey(name: 'subtitleStreams') final List<PlaybackTrack> subtitleStreams,
    @JsonKey(name: 'selectedAudioIndex') final int? selectedAudioIndex,
    @JsonKey(name: 'selectedSubtitleIndex') final int? selectedSubtitleIndex,
  }) = _$PlaybackInfoImpl;

  factory _PlaybackInfo.fromJson(Map<String, dynamic> json) =
      _$PlaybackInfoImpl.fromJson;

  @override
  @JsonKey(name: 'mediaSourceId')
  String? get mediaSourceId;
  @override
  @JsonKey(name: 'audioStreams')
  List<PlaybackTrack> get audioStreams;
  @override
  @JsonKey(name: 'subtitleStreams')
  List<PlaybackTrack> get subtitleStreams;
  @override
  @JsonKey(name: 'selectedAudioIndex')
  int? get selectedAudioIndex;
  @override
  @JsonKey(name: 'selectedSubtitleIndex')
  int? get selectedSubtitleIndex;

  /// Create a copy of PlaybackInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlaybackInfoImplCopyWith<_$PlaybackInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
