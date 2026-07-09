import 'package:freezed_annotation/freezed_annotation.dart';

part 'stream_url.freezed.dart';
part 'stream_url.g.dart';

/// The signed native stream/download URL returned by
/// `GET /api/library/native/stream-url/:itemId` (`app/server/native.js`):
/// `{ url, expiresAt }` where `expiresAt` is epoch-ms.
@freezed
class StreamUrl with _$StreamUrl {
  const factory StreamUrl({
    required String url,
    required int expiresAt,
  }) = _StreamUrl;

  factory StreamUrl.fromJson(Map<String, dynamic> json) =>
      _$StreamUrlFromJson(json);
}

extension StreamUrlX on StreamUrl {
  DateTime get expiresAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(expiresAt);
  bool get isExpired => DateTime.now().millisecondsSinceEpoch >= expiresAt;
}
