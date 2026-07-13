import 'package:freezed_annotation/freezed_annotation.dart';

part 'playback_info.freezed.dart';
part 'playback_info.g.dart';

/// One selectable audio or subtitle track, as normalized by the server's
/// `normalizePlaybackInfo` (`app/server/library.js`) from Jellyfin's
/// `PlaybackInfoResponse`.
@freezed
class PlaybackTrack with _$PlaybackTrack {
  const factory PlaybackTrack({
    @JsonKey(name: 'index') required int index,
    @JsonKey(name: 'displayTitle') String? displayTitle,
    @JsonKey(name: 'title') String? title,
    @JsonKey(name: 'language') String? language,
    @JsonKey(name: 'codec') String? codec,
    @JsonKey(name: 'isDefault') @Default(false) bool isDefault,
    @JsonKey(name: 'isForced') @Default(false) bool isForced,
    @JsonKey(name: 'isExternal') @Default(false) bool isExternal,
    @JsonKey(name: 'deliveryUrl') String? deliveryUrl,
  }) = _PlaybackTrack;

  factory PlaybackTrack.fromJson(Map<String, dynamic> json) =>
      _$PlaybackTrackFromJson(json);
}

/// `POST /api/library/playback-info/:id` response: the audio/subtitle tracks
/// available for a title, plus which ones are currently selected.
@freezed
class PlaybackInfo with _$PlaybackInfo {
  const factory PlaybackInfo({
    @JsonKey(name: 'mediaSourceId') String? mediaSourceId,
    @JsonKey(name: 'audioStreams')
    @Default(<PlaybackTrack>[])
    List<PlaybackTrack> audioStreams,
    @JsonKey(name: 'subtitleStreams')
    @Default(<PlaybackTrack>[])
    List<PlaybackTrack> subtitleStreams,
    @JsonKey(name: 'selectedAudioIndex') int? selectedAudioIndex,
    @JsonKey(name: 'selectedSubtitleIndex') int? selectedSubtitleIndex,
  }) = _PlaybackInfo;

  factory PlaybackInfo.fromJson(Map<String, dynamic> json) =>
      _$PlaybackInfoFromJson(json);
}
