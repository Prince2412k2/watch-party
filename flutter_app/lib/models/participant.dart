import 'package:freezed_annotation/freezed_annotation.dart';

part 'participant.freezed.dart';
part 'participant.g.dart';

/// A member of a watch party. Derived from the server's guest/host records
/// (`user:joined` payloads and `publicSession.guests`).
@freezed
class Participant with _$Participant {
  const factory Participant({
    required String userId,
    required String name,
    @Default(false) bool isHost,
  }) = _Participant;

  factory Participant.fromJson(Map<String, dynamic> json) =>
      _$ParticipantFromJson(json);
}
