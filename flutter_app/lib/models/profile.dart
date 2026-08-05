/// Profile models. Deliberately hand-written rather than freezed: they are
/// plain data with no codegen step, and every other model in here needs
/// `build_runner` re-run to change.

/// A saved avatar customisation — overrides only, in the vocabulary the asset
/// set defines. Anything absent falls back to the value derived from the
/// account, which the server resolves when it draws the picture.
class AvatarConfig {
  const AvatarConfig({
    this.selections = const <String, String>{},
    this.colors = const <String, String>{},
    this.background,
  });

  final Map<String, String> selections;
  final Map<String, String> colors;
  final String? background;

  /// Nothing overridden is the same as nothing saved — the derived default.
  bool get isEmpty =>
      selections.isEmpty && colors.isEmpty && background == null;

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    final result = <String, String>{};
    value.forEach((key, entry) {
      if (key is String && entry is String) result[key] = entry;
    });
    return result;
  }

  factory AvatarConfig.fromJson(Map<String, dynamic> json) => AvatarConfig(
    selections: _stringMap(json['selections']),
    colors: _stringMap(json['colors']),
    background: json['background'] is String
        ? json['background'] as String
        : null,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (selections.isNotEmpty) 'selections': selections,
    if (colors.isNotEmpty) 'colors': colors,
    if (background != null) 'background': background,
  };

  AvatarConfig withPart(String slotId, String partId) => AvatarConfig(
    selections: <String, String>{...selections, slotId: partId},
    colors: colors,
    background: background,
  );

  AvatarConfig withColor(String slotId, String hex) => AvatarConfig(
    selections: selections,
    colors: <String, String>{...colors, slotId: hex},
    background: background,
  );

  AvatarConfig withBackground(String value) => AvatarConfig(
    selections: selections,
    colors: colors,
    background: value,
  );
}

/// Someone's profile. Both fields are absent for anyone who has never saved
/// one, which is the ordinary case rather than a missing record: the account
/// name and a derived avatar stand in.
class UserProfile {
  const UserProfile({this.accountName = '', this.displayName, this.avatar});

  final String accountName;
  final String? displayName;
  final AvatarConfig? avatar;

  /// What to call them: their display name if they set one, else the account.
  String get shownName {
    final chosen = displayName?.trim() ?? '';
    return chosen.isNotEmpty ? chosen : accountName;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    accountName: json['accountName'] as String? ?? '',
    displayName: json['displayName'] as String?,
    avatar: json['avatar'] is Map<String, dynamic>
        ? AvatarConfig.fromJson(json['avatar'] as Map<String, dynamic>)
        : null,
  );
}

/// One choice within a slot — a hairstyle, a jacket, a hat.
class AvatarPart {
  const AvatarPart({required this.id, required this.name});

  final String id;
  final String name;

  factory AvatarPart.fromJson(Map<String, dynamic> json) => AvatarPart(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );

  /// `low-twin-buns` reads better as `Low twin buns`.
  String get label {
    if (name.isEmpty) return id;
    final spaced = name.replaceAll('-', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

class AvatarSlot {
  const AvatarSlot({required this.id, required this.label, required this.parts});

  final String id;
  final String label;
  final List<AvatarPart> parts;

  factory AvatarSlot.fromJson(Map<String, dynamic> json) => AvatarSlot(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    parts: (json['parts'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(AvatarPart.fromJson)
        .toList(growable: false),
  );
}

class AvatarGroup {
  const AvatarGroup({
    required this.id,
    required this.label,
    required this.slots,
  });

  final String id;
  final String label;
  final List<AvatarSlot> slots;

  factory AvatarGroup.fromJson(Map<String, dynamic> json) => AvatarGroup(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    slots: (json['slots'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(AvatarSlot.fromJson)
        .toList(growable: false),
  );
}

class AvatarColorSlot {
  const AvatarColorSlot({
    required this.id,
    required this.label,
    required this.defaultHex,
    required this.allowTransparent,
  });

  final String id;
  final String label;
  final String defaultHex;
  final bool allowTransparent;

  factory AvatarColorSlot.fromJson(Map<String, dynamic> json) =>
      AvatarColorSlot(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        defaultHex: json['default'] as String? ?? '000000',
        allowTransparent: json['allowTransparent'] == true,
      );
}

/// Everything an editor needs to offer, read from the asset set the server has
/// installed rather than hardcoded here — so an asset-set update adds options
/// instead of silently dropping them.
class AvatarOptions {
  const AvatarOptions({
    required this.groups,
    required this.colors,
    required this.palettes,
    required this.defaultBackground,
  });

  final List<AvatarGroup> groups;
  final List<AvatarColorSlot> colors;
  final Map<String, List<String>> palettes;
  final String defaultBackground;

  factory AvatarOptions.fromJson(Map<String, dynamic> json) {
    final palettes = <String, List<String>>{};
    final raw = json['palettes'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is List) {
          palettes[key] = value.whereType<String>().toList(growable: false);
        }
      });
    }
    final defaults = json['defaults'];
    return AvatarOptions(
      groups: (json['groups'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AvatarGroup.fromJson)
          .toList(growable: false),
      colors: (json['colors'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AvatarColorSlot.fromJson)
          .toList(growable: false),
      palettes: palettes,
      defaultBackground: defaults is Map<String, dynamic>
          ? defaults['background'] as String? ?? 'F6F5F4'
          : 'F6F5F4',
    );
  }
}
