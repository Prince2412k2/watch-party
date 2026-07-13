import 'package:freezed_annotation/freezed_annotation.dart';

part 'person.freezed.dart';
part 'person.g.dart';

/// A Jellyfin `Person` (cast/crew) entry attached to an item's `People` list.
@freezed
class Person with _$Person {
  const factory Person({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Name') @Default('') String name,
    @JsonKey(name: 'Role') String? role,
    @JsonKey(name: 'Type') String? type,
  }) = _Person;

  factory Person.fromJson(Map<String, dynamic> json) => _$PersonFromJson(json);
}
