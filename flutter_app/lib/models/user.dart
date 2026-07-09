import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

/// Authenticated identity, mirrors the server's "safe" session payload
/// (`app/server/auth.js` — accessToken/deviceId stripped).
@freezed
class User with _$User {
  const factory User({
    required String userId,
    required String name,
    @Default(false) bool isAdmin,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
