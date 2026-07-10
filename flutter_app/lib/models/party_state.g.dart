// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'party_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SyncScheduleImpl _$$SyncScheduleImplFromJson(Map<String, dynamic> json) =>
    _$SyncScheduleImpl(
      positionTicks: (json['positionTicks'] as num?)?.toInt() ?? 0,
      t0: (json['t0'] as num?)?.toInt() ?? 0,
      rate: (json['rate'] as num?)?.toInt() ?? 0,
      paused: json['paused'] as bool? ?? true,
      phase: json['phase'] as String? ?? 'paused',
      version: (json['version'] as num?)?.toInt() ?? 0,
      mediaGeneration: (json['mediaGeneration'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$SyncScheduleImplToJson(_$SyncScheduleImpl instance) =>
    <String, dynamic>{
      'positionTicks': instance.positionTicks,
      't0': instance.t0,
      'rate': instance.rate,
      'paused': instance.paused,
      'phase': instance.phase,
      'version': instance.version,
      'mediaGeneration': instance.mediaGeneration,
    };

_$BrowseStateImpl _$$BrowseStateImplFromJson(Map<String, dynamic> json) =>
    _$BrowseStateImpl(
      stack:
          (json['stack'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$BrowseStateImplToJson(_$BrowseStateImpl instance) =>
    <String, dynamic>{'stack': instance.stack};

_$PartyStateImpl _$$PartyStateImplFromJson(Map<String, dynamic> json) =>
    _$PartyStateImpl(
      id: json['id'] as String,
      hostId: json['hostId'] as String,
      hostName: json['hostName'] as String?,
      stage: json['stage'] as String? ?? 'lobby',
      mediaItemId: json['mediaItemId'] as String?,
      mediaSourceId: json['mediaSourceId'] as String?,
      collaborativeControl: json['collaborativeControl'] as bool? ?? false,
      syncMode: json['syncMode'] as String? ?? 'hopping',
      participants:
          (json['participants'] as List<dynamic>?)
              ?.map((e) => Participant.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Participant>[],
      schedule: json['schedule'] == null
          ? const SyncSchedule()
          : SyncSchedule.fromJson(json['schedule'] as Map<String, dynamic>),
      browse: json['browse'] == null
          ? const BrowseState()
          : BrowseState.fromJson(json['browse'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$PartyStateImplToJson(_$PartyStateImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'hostId': instance.hostId,
      'hostName': instance.hostName,
      'stage': instance.stage,
      'mediaItemId': instance.mediaItemId,
      'mediaSourceId': instance.mediaSourceId,
      'collaborativeControl': instance.collaborativeControl,
      'syncMode': instance.syncMode,
      'participants': instance.participants,
      'schedule': instance.schedule,
      'browse': instance.browse,
    };
