import 'package:freezed_annotation/freezed_annotation.dart';

import 'media_stream.dart';

part 'media_source.freezed.dart';
part 'media_source.g.dart';

/// A Jellyfin `MediaSource` — one physical file/variant for a title, carrying
/// the container, size, and its embedded [MediaStream]s.
@freezed
class MediaSource with _$MediaSource {
  const factory MediaSource({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Protocol') String? protocol,
    @JsonKey(name: 'Container') String? container,
    @JsonKey(name: 'Path') String? path,
    @JsonKey(name: 'Name') String? name,
    @JsonKey(name: 'Size') int? size,
    @JsonKey(name: 'RunTimeTicks') int? runTimeTicks,
    @JsonKey(name: 'SupportsDirectPlay') @Default(false) bool supportsDirectPlay,
    @JsonKey(name: 'SupportsDirectStream')
    @Default(false)
    bool supportsDirectStream,
    @JsonKey(name: 'SupportsTranscoding') @Default(false) bool supportsTranscoding,
    @JsonKey(name: 'MediaStreams')
    @Default(<MediaStream>[])
    List<MediaStream> mediaStreams,
  }) = _MediaSource;

  factory MediaSource.fromJson(Map<String, dynamic> json) =>
      _$MediaSourceFromJson(json);
}
