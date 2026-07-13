// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PlaybackTrackImpl _$$PlaybackTrackImplFromJson(Map<String, dynamic> json) =>
    _$PlaybackTrackImpl(
      index: (json['index'] as num).toInt(),
      displayTitle: json['displayTitle'] as String?,
      title: json['title'] as String?,
      language: json['language'] as String?,
      codec: json['codec'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      isForced: json['isForced'] as bool? ?? false,
      isExternal: json['isExternal'] as bool? ?? false,
      deliveryUrl: json['deliveryUrl'] as String?,
    );

Map<String, dynamic> _$$PlaybackTrackImplToJson(_$PlaybackTrackImpl instance) =>
    <String, dynamic>{
      'index': instance.index,
      'displayTitle': instance.displayTitle,
      'title': instance.title,
      'language': instance.language,
      'codec': instance.codec,
      'isDefault': instance.isDefault,
      'isForced': instance.isForced,
      'isExternal': instance.isExternal,
      'deliveryUrl': instance.deliveryUrl,
    };

_$PlaybackInfoImpl _$$PlaybackInfoImplFromJson(Map<String, dynamic> json) =>
    _$PlaybackInfoImpl(
      mediaSourceId: json['mediaSourceId'] as String?,
      audioStreams:
          (json['audioStreams'] as List<dynamic>?)
              ?.map((e) => PlaybackTrack.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <PlaybackTrack>[],
      subtitleStreams:
          (json['subtitleStreams'] as List<dynamic>?)
              ?.map((e) => PlaybackTrack.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <PlaybackTrack>[],
      selectedAudioIndex: (json['selectedAudioIndex'] as num?)?.toInt(),
      selectedSubtitleIndex: (json['selectedSubtitleIndex'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$PlaybackInfoImplToJson(_$PlaybackInfoImpl instance) =>
    <String, dynamic>{
      'mediaSourceId': instance.mediaSourceId,
      'audioStreams': instance.audioStreams,
      'subtitleStreams': instance.subtitleStreams,
      'selectedAudioIndex': instance.selectedAudioIndex,
      'selectedSubtitleIndex': instance.selectedSubtitleIndex,
    };
