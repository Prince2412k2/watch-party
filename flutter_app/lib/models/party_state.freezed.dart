// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'party_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

SyncSchedule _$SyncScheduleFromJson(Map<String, dynamic> json) {
  return _SyncSchedule.fromJson(json);
}

/// @nodoc
mixin _$SyncSchedule {
  int get positionTicks => throw _privateConstructorUsedError;

  /// Server epoch-ms when the current play segment started (0 when paused).
  int get t0 => throw _privateConstructorUsedError;

  /// Playback rate: 1 while playing, 0 while paused/stalled.
  int get rate => throw _privateConstructorUsedError;
  bool get paused => throw _privateConstructorUsedError;

  /// 'playing' | 'paused' | 'stalled'
  String get phase => throw _privateConstructorUsedError;

  /// Monotonic version; a controller may gate a command on it (baseVersion).
  int get version => throw _privateConstructorUsedError;

  /// Bumped whenever the media selection changes (guards stale stalls).
  int get mediaGeneration => throw _privateConstructorUsedError;

  /// Serializes this SyncSchedule to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SyncSchedule
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SyncScheduleCopyWith<SyncSchedule> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyncScheduleCopyWith<$Res> {
  factory $SyncScheduleCopyWith(
    SyncSchedule value,
    $Res Function(SyncSchedule) then,
  ) = _$SyncScheduleCopyWithImpl<$Res, SyncSchedule>;
  @useResult
  $Res call({
    int positionTicks,
    int t0,
    int rate,
    bool paused,
    String phase,
    int version,
    int mediaGeneration,
  });
}

/// @nodoc
class _$SyncScheduleCopyWithImpl<$Res, $Val extends SyncSchedule>
    implements $SyncScheduleCopyWith<$Res> {
  _$SyncScheduleCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyncSchedule
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? positionTicks = null,
    Object? t0 = null,
    Object? rate = null,
    Object? paused = null,
    Object? phase = null,
    Object? version = null,
    Object? mediaGeneration = null,
  }) {
    return _then(
      _value.copyWith(
            positionTicks: null == positionTicks
                ? _value.positionTicks
                : positionTicks // ignore: cast_nullable_to_non_nullable
                      as int,
            t0: null == t0
                ? _value.t0
                : t0 // ignore: cast_nullable_to_non_nullable
                      as int,
            rate: null == rate
                ? _value.rate
                : rate // ignore: cast_nullable_to_non_nullable
                      as int,
            paused: null == paused
                ? _value.paused
                : paused // ignore: cast_nullable_to_non_nullable
                      as bool,
            phase: null == phase
                ? _value.phase
                : phase // ignore: cast_nullable_to_non_nullable
                      as String,
            version: null == version
                ? _value.version
                : version // ignore: cast_nullable_to_non_nullable
                      as int,
            mediaGeneration: null == mediaGeneration
                ? _value.mediaGeneration
                : mediaGeneration // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SyncScheduleImplCopyWith<$Res>
    implements $SyncScheduleCopyWith<$Res> {
  factory _$$SyncScheduleImplCopyWith(
    _$SyncScheduleImpl value,
    $Res Function(_$SyncScheduleImpl) then,
  ) = __$$SyncScheduleImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int positionTicks,
    int t0,
    int rate,
    bool paused,
    String phase,
    int version,
    int mediaGeneration,
  });
}

/// @nodoc
class __$$SyncScheduleImplCopyWithImpl<$Res>
    extends _$SyncScheduleCopyWithImpl<$Res, _$SyncScheduleImpl>
    implements _$$SyncScheduleImplCopyWith<$Res> {
  __$$SyncScheduleImplCopyWithImpl(
    _$SyncScheduleImpl _value,
    $Res Function(_$SyncScheduleImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SyncSchedule
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? positionTicks = null,
    Object? t0 = null,
    Object? rate = null,
    Object? paused = null,
    Object? phase = null,
    Object? version = null,
    Object? mediaGeneration = null,
  }) {
    return _then(
      _$SyncScheduleImpl(
        positionTicks: null == positionTicks
            ? _value.positionTicks
            : positionTicks // ignore: cast_nullable_to_non_nullable
                  as int,
        t0: null == t0
            ? _value.t0
            : t0 // ignore: cast_nullable_to_non_nullable
                  as int,
        rate: null == rate
            ? _value.rate
            : rate // ignore: cast_nullable_to_non_nullable
                  as int,
        paused: null == paused
            ? _value.paused
            : paused // ignore: cast_nullable_to_non_nullable
                  as bool,
        phase: null == phase
            ? _value.phase
            : phase // ignore: cast_nullable_to_non_nullable
                  as String,
        version: null == version
            ? _value.version
            : version // ignore: cast_nullable_to_non_nullable
                  as int,
        mediaGeneration: null == mediaGeneration
            ? _value.mediaGeneration
            : mediaGeneration // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SyncScheduleImpl implements _SyncSchedule {
  const _$SyncScheduleImpl({
    this.positionTicks = 0,
    this.t0 = 0,
    this.rate = 0,
    this.paused = true,
    this.phase = 'paused',
    this.version = 0,
    this.mediaGeneration = 0,
  });

  factory _$SyncScheduleImpl.fromJson(Map<String, dynamic> json) =>
      _$$SyncScheduleImplFromJson(json);

  @override
  @JsonKey()
  final int positionTicks;

  /// Server epoch-ms when the current play segment started (0 when paused).
  @override
  @JsonKey()
  final int t0;

  /// Playback rate: 1 while playing, 0 while paused/stalled.
  @override
  @JsonKey()
  final int rate;
  @override
  @JsonKey()
  final bool paused;

  /// 'playing' | 'paused' | 'stalled'
  @override
  @JsonKey()
  final String phase;

  /// Monotonic version; a controller may gate a command on it (baseVersion).
  @override
  @JsonKey()
  final int version;

  /// Bumped whenever the media selection changes (guards stale stalls).
  @override
  @JsonKey()
  final int mediaGeneration;

  @override
  String toString() {
    return 'SyncSchedule(positionTicks: $positionTicks, t0: $t0, rate: $rate, paused: $paused, phase: $phase, version: $version, mediaGeneration: $mediaGeneration)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyncScheduleImpl &&
            (identical(other.positionTicks, positionTicks) ||
                other.positionTicks == positionTicks) &&
            (identical(other.t0, t0) || other.t0 == t0) &&
            (identical(other.rate, rate) || other.rate == rate) &&
            (identical(other.paused, paused) || other.paused == paused) &&
            (identical(other.phase, phase) || other.phase == phase) &&
            (identical(other.version, version) || other.version == version) &&
            (identical(other.mediaGeneration, mediaGeneration) ||
                other.mediaGeneration == mediaGeneration));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    positionTicks,
    t0,
    rate,
    paused,
    phase,
    version,
    mediaGeneration,
  );

  /// Create a copy of SyncSchedule
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyncScheduleImplCopyWith<_$SyncScheduleImpl> get copyWith =>
      __$$SyncScheduleImplCopyWithImpl<_$SyncScheduleImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SyncScheduleImplToJson(this);
  }
}

abstract class _SyncSchedule implements SyncSchedule {
  const factory _SyncSchedule({
    final int positionTicks,
    final int t0,
    final int rate,
    final bool paused,
    final String phase,
    final int version,
    final int mediaGeneration,
  }) = _$SyncScheduleImpl;

  factory _SyncSchedule.fromJson(Map<String, dynamic> json) =
      _$SyncScheduleImpl.fromJson;

  @override
  int get positionTicks;

  /// Server epoch-ms when the current play segment started (0 when paused).
  @override
  int get t0;

  /// Playback rate: 1 while playing, 0 while paused/stalled.
  @override
  int get rate;
  @override
  bool get paused;

  /// 'playing' | 'paused' | 'stalled'
  @override
  String get phase;

  /// Monotonic version; a controller may gate a command on it (baseVersion).
  @override
  int get version;

  /// Bumped whenever the media selection changes (guards stale stalls).
  @override
  int get mediaGeneration;

  /// Create a copy of SyncSchedule
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyncScheduleImplCopyWith<_$SyncScheduleImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

BrowseState _$BrowseStateFromJson(Map<String, dynamic> json) {
  return _BrowseState.fromJson(json);
}

/// @nodoc
mixin _$BrowseState {
  List<Map<String, dynamic>> get stack => throw _privateConstructorUsedError;

  /// Serializes this BrowseState to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of BrowseState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BrowseStateCopyWith<BrowseState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BrowseStateCopyWith<$Res> {
  factory $BrowseStateCopyWith(
    BrowseState value,
    $Res Function(BrowseState) then,
  ) = _$BrowseStateCopyWithImpl<$Res, BrowseState>;
  @useResult
  $Res call({List<Map<String, dynamic>> stack});
}

/// @nodoc
class _$BrowseStateCopyWithImpl<$Res, $Val extends BrowseState>
    implements $BrowseStateCopyWith<$Res> {
  _$BrowseStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BrowseState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? stack = null}) {
    return _then(
      _value.copyWith(
            stack: null == stack
                ? _value.stack
                : stack // ignore: cast_nullable_to_non_nullable
                      as List<Map<String, dynamic>>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$BrowseStateImplCopyWith<$Res>
    implements $BrowseStateCopyWith<$Res> {
  factory _$$BrowseStateImplCopyWith(
    _$BrowseStateImpl value,
    $Res Function(_$BrowseStateImpl) then,
  ) = __$$BrowseStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<Map<String, dynamic>> stack});
}

/// @nodoc
class __$$BrowseStateImplCopyWithImpl<$Res>
    extends _$BrowseStateCopyWithImpl<$Res, _$BrowseStateImpl>
    implements _$$BrowseStateImplCopyWith<$Res> {
  __$$BrowseStateImplCopyWithImpl(
    _$BrowseStateImpl _value,
    $Res Function(_$BrowseStateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of BrowseState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? stack = null}) {
    return _then(
      _$BrowseStateImpl(
        stack: null == stack
            ? _value._stack
            : stack // ignore: cast_nullable_to_non_nullable
                  as List<Map<String, dynamic>>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$BrowseStateImpl implements _BrowseState {
  const _$BrowseStateImpl({final List<Map<String, dynamic>> stack = const []})
    : _stack = stack;

  factory _$BrowseStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$BrowseStateImplFromJson(json);

  final List<Map<String, dynamic>> _stack;
  @override
  @JsonKey()
  List<Map<String, dynamic>> get stack {
    if (_stack is EqualUnmodifiableListView) return _stack;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_stack);
  }

  @override
  String toString() {
    return 'BrowseState(stack: $stack)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BrowseStateImpl &&
            const DeepCollectionEquality().equals(other._stack, _stack));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_stack));

  /// Create a copy of BrowseState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BrowseStateImplCopyWith<_$BrowseStateImpl> get copyWith =>
      __$$BrowseStateImplCopyWithImpl<_$BrowseStateImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BrowseStateImplToJson(this);
  }
}

abstract class _BrowseState implements BrowseState {
  const factory _BrowseState({final List<Map<String, dynamic>> stack}) =
      _$BrowseStateImpl;

  factory _BrowseState.fromJson(Map<String, dynamic> json) =
      _$BrowseStateImpl.fromJson;

  @override
  List<Map<String, dynamic>> get stack;

  /// Create a copy of BrowseState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BrowseStateImplCopyWith<_$BrowseStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PartyState _$PartyStateFromJson(Map<String, dynamic> json) {
  return _PartyState.fromJson(json);
}

/// @nodoc
mixin _$PartyState {
  String get id => throw _privateConstructorUsedError;
  String get hostId => throw _privateConstructorUsedError;
  String? get hostName => throw _privateConstructorUsedError;

  /// 'lobby' | 'watching'
  String get stage => throw _privateConstructorUsedError;
  String? get mediaItemId => throw _privateConstructorUsedError;
  String? get mediaSourceId => throw _privateConstructorUsedError;
  bool get collaborativeControl => throw _privateConstructorUsedError;

  /// 'hopping' | 'dragging'
  String get syncMode => throw _privateConstructorUsedError;
  List<Participant> get participants => throw _privateConstructorUsedError;
  SyncSchedule get schedule => throw _privateConstructorUsedError;
  BrowseState get browse => throw _privateConstructorUsedError;

  /// Serializes this PartyState to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PartyState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PartyStateCopyWith<PartyState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PartyStateCopyWith<$Res> {
  factory $PartyStateCopyWith(
    PartyState value,
    $Res Function(PartyState) then,
  ) = _$PartyStateCopyWithImpl<$Res, PartyState>;
  @useResult
  $Res call({
    String id,
    String hostId,
    String? hostName,
    String stage,
    String? mediaItemId,
    String? mediaSourceId,
    bool collaborativeControl,
    String syncMode,
    List<Participant> participants,
    SyncSchedule schedule,
    BrowseState browse,
  });

  $SyncScheduleCopyWith<$Res> get schedule;
  $BrowseStateCopyWith<$Res> get browse;
}

/// @nodoc
class _$PartyStateCopyWithImpl<$Res, $Val extends PartyState>
    implements $PartyStateCopyWith<$Res> {
  _$PartyStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PartyState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? hostId = null,
    Object? hostName = freezed,
    Object? stage = null,
    Object? mediaItemId = freezed,
    Object? mediaSourceId = freezed,
    Object? collaborativeControl = null,
    Object? syncMode = null,
    Object? participants = null,
    Object? schedule = null,
    Object? browse = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            hostId: null == hostId
                ? _value.hostId
                : hostId // ignore: cast_nullable_to_non_nullable
                      as String,
            hostName: freezed == hostName
                ? _value.hostName
                : hostName // ignore: cast_nullable_to_non_nullable
                      as String?,
            stage: null == stage
                ? _value.stage
                : stage // ignore: cast_nullable_to_non_nullable
                      as String,
            mediaItemId: freezed == mediaItemId
                ? _value.mediaItemId
                : mediaItemId // ignore: cast_nullable_to_non_nullable
                      as String?,
            mediaSourceId: freezed == mediaSourceId
                ? _value.mediaSourceId
                : mediaSourceId // ignore: cast_nullable_to_non_nullable
                      as String?,
            collaborativeControl: null == collaborativeControl
                ? _value.collaborativeControl
                : collaborativeControl // ignore: cast_nullable_to_non_nullable
                      as bool,
            syncMode: null == syncMode
                ? _value.syncMode
                : syncMode // ignore: cast_nullable_to_non_nullable
                      as String,
            participants: null == participants
                ? _value.participants
                : participants // ignore: cast_nullable_to_non_nullable
                      as List<Participant>,
            schedule: null == schedule
                ? _value.schedule
                : schedule // ignore: cast_nullable_to_non_nullable
                      as SyncSchedule,
            browse: null == browse
                ? _value.browse
                : browse // ignore: cast_nullable_to_non_nullable
                      as BrowseState,
          )
          as $Val,
    );
  }

  /// Create a copy of PartyState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SyncScheduleCopyWith<$Res> get schedule {
    return $SyncScheduleCopyWith<$Res>(_value.schedule, (value) {
      return _then(_value.copyWith(schedule: value) as $Val);
    });
  }

  /// Create a copy of PartyState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $BrowseStateCopyWith<$Res> get browse {
    return $BrowseStateCopyWith<$Res>(_value.browse, (value) {
      return _then(_value.copyWith(browse: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$PartyStateImplCopyWith<$Res>
    implements $PartyStateCopyWith<$Res> {
  factory _$$PartyStateImplCopyWith(
    _$PartyStateImpl value,
    $Res Function(_$PartyStateImpl) then,
  ) = __$$PartyStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String hostId,
    String? hostName,
    String stage,
    String? mediaItemId,
    String? mediaSourceId,
    bool collaborativeControl,
    String syncMode,
    List<Participant> participants,
    SyncSchedule schedule,
    BrowseState browse,
  });

  @override
  $SyncScheduleCopyWith<$Res> get schedule;
  @override
  $BrowseStateCopyWith<$Res> get browse;
}

/// @nodoc
class __$$PartyStateImplCopyWithImpl<$Res>
    extends _$PartyStateCopyWithImpl<$Res, _$PartyStateImpl>
    implements _$$PartyStateImplCopyWith<$Res> {
  __$$PartyStateImplCopyWithImpl(
    _$PartyStateImpl _value,
    $Res Function(_$PartyStateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PartyState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? hostId = null,
    Object? hostName = freezed,
    Object? stage = null,
    Object? mediaItemId = freezed,
    Object? mediaSourceId = freezed,
    Object? collaborativeControl = null,
    Object? syncMode = null,
    Object? participants = null,
    Object? schedule = null,
    Object? browse = null,
  }) {
    return _then(
      _$PartyStateImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        hostId: null == hostId
            ? _value.hostId
            : hostId // ignore: cast_nullable_to_non_nullable
                  as String,
        hostName: freezed == hostName
            ? _value.hostName
            : hostName // ignore: cast_nullable_to_non_nullable
                  as String?,
        stage: null == stage
            ? _value.stage
            : stage // ignore: cast_nullable_to_non_nullable
                  as String,
        mediaItemId: freezed == mediaItemId
            ? _value.mediaItemId
            : mediaItemId // ignore: cast_nullable_to_non_nullable
                  as String?,
        mediaSourceId: freezed == mediaSourceId
            ? _value.mediaSourceId
            : mediaSourceId // ignore: cast_nullable_to_non_nullable
                  as String?,
        collaborativeControl: null == collaborativeControl
            ? _value.collaborativeControl
            : collaborativeControl // ignore: cast_nullable_to_non_nullable
                  as bool,
        syncMode: null == syncMode
            ? _value.syncMode
            : syncMode // ignore: cast_nullable_to_non_nullable
                  as String,
        participants: null == participants
            ? _value._participants
            : participants // ignore: cast_nullable_to_non_nullable
                  as List<Participant>,
        schedule: null == schedule
            ? _value.schedule
            : schedule // ignore: cast_nullable_to_non_nullable
                  as SyncSchedule,
        browse: null == browse
            ? _value.browse
            : browse // ignore: cast_nullable_to_non_nullable
                  as BrowseState,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$PartyStateImpl implements _PartyState {
  const _$PartyStateImpl({
    required this.id,
    required this.hostId,
    this.hostName,
    this.stage = 'lobby',
    this.mediaItemId,
    this.mediaSourceId,
    this.collaborativeControl = false,
    this.syncMode = 'hopping',
    final List<Participant> participants = const <Participant>[],
    this.schedule = const SyncSchedule(),
    this.browse = const BrowseState(),
  }) : _participants = participants;

  factory _$PartyStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$PartyStateImplFromJson(json);

  @override
  final String id;
  @override
  final String hostId;
  @override
  final String? hostName;

  /// 'lobby' | 'watching'
  @override
  @JsonKey()
  final String stage;
  @override
  final String? mediaItemId;
  @override
  final String? mediaSourceId;
  @override
  @JsonKey()
  final bool collaborativeControl;

  /// 'hopping' | 'dragging'
  @override
  @JsonKey()
  final String syncMode;
  final List<Participant> _participants;
  @override
  @JsonKey()
  List<Participant> get participants {
    if (_participants is EqualUnmodifiableListView) return _participants;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_participants);
  }

  @override
  @JsonKey()
  final SyncSchedule schedule;
  @override
  @JsonKey()
  final BrowseState browse;

  @override
  String toString() {
    return 'PartyState(id: $id, hostId: $hostId, hostName: $hostName, stage: $stage, mediaItemId: $mediaItemId, mediaSourceId: $mediaSourceId, collaborativeControl: $collaborativeControl, syncMode: $syncMode, participants: $participants, schedule: $schedule, browse: $browse)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PartyStateImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.hostId, hostId) || other.hostId == hostId) &&
            (identical(other.hostName, hostName) ||
                other.hostName == hostName) &&
            (identical(other.stage, stage) || other.stage == stage) &&
            (identical(other.mediaItemId, mediaItemId) ||
                other.mediaItemId == mediaItemId) &&
            (identical(other.mediaSourceId, mediaSourceId) ||
                other.mediaSourceId == mediaSourceId) &&
            (identical(other.collaborativeControl, collaborativeControl) ||
                other.collaborativeControl == collaborativeControl) &&
            (identical(other.syncMode, syncMode) ||
                other.syncMode == syncMode) &&
            const DeepCollectionEquality().equals(
              other._participants,
              _participants,
            ) &&
            (identical(other.schedule, schedule) ||
                other.schedule == schedule) &&
            (identical(other.browse, browse) || other.browse == browse));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    hostId,
    hostName,
    stage,
    mediaItemId,
    mediaSourceId,
    collaborativeControl,
    syncMode,
    const DeepCollectionEquality().hash(_participants),
    schedule,
    browse,
  );

  /// Create a copy of PartyState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PartyStateImplCopyWith<_$PartyStateImpl> get copyWith =>
      __$$PartyStateImplCopyWithImpl<_$PartyStateImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PartyStateImplToJson(this);
  }
}

abstract class _PartyState implements PartyState {
  const factory _PartyState({
    required final String id,
    required final String hostId,
    final String? hostName,
    final String stage,
    final String? mediaItemId,
    final String? mediaSourceId,
    final bool collaborativeControl,
    final String syncMode,
    final List<Participant> participants,
    final SyncSchedule schedule,
    final BrowseState browse,
  }) = _$PartyStateImpl;

  factory _PartyState.fromJson(Map<String, dynamic> json) =
      _$PartyStateImpl.fromJson;

  @override
  String get id;
  @override
  String get hostId;
  @override
  String? get hostName;

  /// 'lobby' | 'watching'
  @override
  String get stage;
  @override
  String? get mediaItemId;
  @override
  String? get mediaSourceId;
  @override
  bool get collaborativeControl;

  /// 'hopping' | 'dragging'
  @override
  String get syncMode;
  @override
  List<Participant> get participants;
  @override
  SyncSchedule get schedule;
  @override
  BrowseState get browse;

  /// Create a copy of PartyState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PartyStateImplCopyWith<_$PartyStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
