import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_stream.freezed.dart';
part 'media_stream.g.dart';

/// A single Jellyfin `MediaStream` (video / audio / subtitle track). Field
/// names mirror Jellyfin's PascalCase payload so the raw JSON maps 1:1.
@freezed
class MediaStream with _$MediaStream {
  const factory MediaStream({
    /// Stream index within the container (Jellyfin `Index`).
    @JsonKey(name: 'Index') int? index,
    /// 'Video' | 'Audio' | 'Subtitle' | 'EmbeddedImage' ...
    @JsonKey(name: 'Type') String? type,
    @JsonKey(name: 'Codec') String? codec,
    @JsonKey(name: 'Language') String? language,
    @JsonKey(name: 'DisplayTitle') String? displayTitle,
    @JsonKey(name: 'Title') String? title,
    @JsonKey(name: 'Channels') int? channels,
    @JsonKey(name: 'Height') int? height,
    @JsonKey(name: 'Width') int? width,
    @JsonKey(name: 'IsDefault') @Default(false) bool isDefault,
    @JsonKey(name: 'IsForced') @Default(false) bool isForced,
    @JsonKey(name: 'IsExternal') @Default(false) bool isExternal,
  }) = _MediaStream;

  factory MediaStream.fromJson(Map<String, dynamic> json) =>
      _$MediaStreamFromJson(json);
}
