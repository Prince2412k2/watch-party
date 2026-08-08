import 'package:flutter/foundation.dart';

@immutable
class SubtitlePreferences {
  const SubtitlePreferences({
    required this.delayMs,
    required this.fontScalePercent,
    required this.verticalOffsetPercent,
    required this.fontFamily,
    required this.textColor,
    required this.backgroundOpacityPercent,
  });

  static const defaults = SubtitlePreferences(
    delayMs: 0,
    fontScalePercent: 100,
    verticalOffsetPercent: 0,
    fontFamily: 'sans',
    textColor: '#FFFFFF',
    backgroundOpacityPercent: 65,
  );

  /// Legacy three-value positions, and where each lands on the new scale.
  ///
  /// Sessions persisted before this field existed still carry
  /// `verticalPosition`, and a stored party must not fail validation because
  /// the schema moved under it.
  static const legacyPositions = {'bottom': 0, 'middle': 50, 'top': 100};

  final int delayMs;
  final int fontScalePercent;

  /// How far the subtitles sit ABOVE the bottom edge, 0–100.
  ///
  /// 0 is the bottom, where subtitles belong and where they stay unless
  /// somebody moves them. 100 is the top.
  ///
  /// This replaced a three-value `verticalPosition` (top / middle / bottom).
  /// The player already tracked a continuous position — mpv takes any value and
  /// the Flutter overlay aligns on any value — but the shared preference could
  /// only carry three, so in a party every adjustment was rounded to the
  /// nearest third and echoed back, dragging the slider to 0, 50 or 100 under
  /// the user's hand.
  ///
  /// Note the inversion against mpv's `sub-pos`, where 100 means the bottom.
  /// This axis is expressed the way the setting reads to a person — "lift them
  /// up off the bottom" — and converted at the player boundary.
  final int verticalOffsetPercent;
  final String fontFamily;
  final String textColor;
  final int backgroundOpacityPercent;

  factory SubtitlePreferences.fromJson(Map<String, dynamic> json) {
    // Either spelling of the position key is accepted; everything else is
    // required exactly. A peer or a stored session written before the change
    // sends verticalPosition, and refusing it would drop the whole preference
    // set over one field.
    const keys = {
      'delayMs',
      'fontScalePercent',
      'fontFamily',
      'textColor',
      'backgroundOpacityPercent',
    };
    final delay = json['delayMs'];
    final scale = json['fontScalePercent'];
    final family = json['fontFamily'];
    final color = json['textColor'];
    final background = json['backgroundOpacityPercent'];
    final offset = json['verticalOffsetPercent'] ??
        legacyPositions[json['verticalPosition']];
    final extra = json.keys.toSet()
      ..removeAll(keys)
      ..removeAll(const {'verticalOffsetPercent', 'verticalPosition'});
    if (extra.isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty ||
        delay is! int ||
        delay < -10000 ||
        delay > 10000 ||
        scale is! int ||
        scale < 60 ||
        scale > 200 ||
        offset is! int ||
        offset < 0 ||
        offset > 100 ||
        !const {'sans', 'serif', 'mono'}.contains(family) ||
        color is! String ||
        !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color) ||
        background is! int ||
        background < 0 ||
        background > 100) {
      throw const FormatException('Invalid subtitlePreferences');
    }
    return SubtitlePreferences(
      delayMs: delay,
      fontScalePercent: scale,
      verticalOffsetPercent: offset,
      fontFamily: family as String,
      textColor: color.toUpperCase(),
      backgroundOpacityPercent: background,
    );
  }

  Map<String, dynamic> toJson() => {
    'delayMs': delayMs,
    'fontScalePercent': fontScalePercent,
    'verticalOffsetPercent': verticalOffsetPercent,
    'fontFamily': fontFamily,
    'textColor': textColor,
    'backgroundOpacityPercent': backgroundOpacityPercent,
  };

  SubtitlePreferences copyWith({
    int? delayMs,
    int? fontScalePercent,
    int? verticalOffsetPercent,
    String? fontFamily,
    String? textColor,
    int? backgroundOpacityPercent,
  }) => SubtitlePreferences(
    delayMs: delayMs ?? this.delayMs,
    fontScalePercent: fontScalePercent ?? this.fontScalePercent,
    verticalOffsetPercent: verticalOffsetPercent ?? this.verticalOffsetPercent,
    fontFamily: fontFamily ?? this.fontFamily,
    textColor: (textColor ?? this.textColor).toUpperCase(),
    backgroundOpacityPercent:
        backgroundOpacityPercent ?? this.backgroundOpacityPercent,
  );

  @override
  bool operator ==(Object other) =>
      other is SubtitlePreferences &&
      delayMs == other.delayMs &&
      fontScalePercent == other.fontScalePercent &&
      verticalOffsetPercent == other.verticalOffsetPercent &&
      fontFamily == other.fontFamily &&
      textColor == other.textColor &&
      backgroundOpacityPercent == other.backgroundOpacityPercent;

  @override
  int get hashCode => Object.hash(
    delayMs,
    fontScalePercent,
    verticalOffsetPercent,
    fontFamily,
    textColor,
    backgroundOpacityPercent,
  );
}
