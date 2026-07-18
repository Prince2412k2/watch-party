import 'package:flutter/foundation.dart';

@immutable
class SubtitlePreferences {
  const SubtitlePreferences({
    required this.delayMs,
    required this.fontScalePercent,
    required this.verticalPosition,
    required this.fontFamily,
    required this.textColor,
    required this.backgroundOpacityPercent,
  });

  static const defaults = SubtitlePreferences(
    delayMs: 0,
    fontScalePercent: 100,
    verticalPosition: 'bottom',
    fontFamily: 'sans',
    textColor: '#FFFFFF',
    backgroundOpacityPercent: 65,
  );

  final int delayMs;
  final int fontScalePercent;
  final String verticalPosition;
  final String fontFamily;
  final String textColor;
  final int backgroundOpacityPercent;

  factory SubtitlePreferences.fromJson(Map<String, dynamic> json) {
    const keys = {
      'delayMs',
      'fontScalePercent',
      'verticalPosition',
      'fontFamily',
      'textColor',
      'backgroundOpacityPercent',
    };
    final delay = json['delayMs'];
    final scale = json['fontScalePercent'];
    final position = json['verticalPosition'];
    final family = json['fontFamily'];
    final color = json['textColor'];
    final background = json['backgroundOpacityPercent'];
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty ||
        delay is! int ||
        delay < -10000 ||
        delay > 10000 ||
        scale is! int ||
        scale < 60 ||
        scale > 200 ||
        !const {'top', 'middle', 'bottom'}.contains(position) ||
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
      verticalPosition: position as String,
      fontFamily: family as String,
      textColor: color.toUpperCase(),
      backgroundOpacityPercent: background,
    );
  }

  Map<String, dynamic> toJson() => {
    'delayMs': delayMs,
    'fontScalePercent': fontScalePercent,
    'verticalPosition': verticalPosition,
    'fontFamily': fontFamily,
    'textColor': textColor,
    'backgroundOpacityPercent': backgroundOpacityPercent,
  };

  SubtitlePreferences copyWith({
    int? delayMs,
    int? fontScalePercent,
    String? verticalPosition,
    String? fontFamily,
    String? textColor,
    int? backgroundOpacityPercent,
  }) => SubtitlePreferences(
    delayMs: delayMs ?? this.delayMs,
    fontScalePercent: fontScalePercent ?? this.fontScalePercent,
    verticalPosition: verticalPosition ?? this.verticalPosition,
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
      verticalPosition == other.verticalPosition &&
      fontFamily == other.fontFamily &&
      textColor == other.textColor &&
      backgroundOpacityPercent == other.backgroundOpacityPercent;

  @override
  int get hashCode => Object.hash(
    delayMs,
    fontScalePercent,
    verticalPosition,
    fontFamily,
    textColor,
    backgroundOpacityPercent,
  );
}
