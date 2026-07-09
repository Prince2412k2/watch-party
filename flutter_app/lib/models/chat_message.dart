import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// A chat line, exactly the `chat:message` payload the server broadcasts
/// (`app/server/index.js`): `{ userId, name, text, timestamp }`.
@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String userId,
    required String name,
    required String text,
    /// Server epoch-ms.
    required int timestamp,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}
