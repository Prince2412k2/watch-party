class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;
}

List<SubtitleCue> parseSubtitleCues(String source) {
  final normalized = source
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final cues = <SubtitleCue>[];

  for (final block in normalized.split(RegExp(r'\n[ \t]*\n'))) {
    final lines = block.split('\n');
    final timingIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timingIndex < 0) continue;

    final timing = RegExp(
      r'^\s*((?:\d+:)?\d{1,2}:\d{2}[,.]\d{1,3})\s*-->\s*'
      r'((?:\d+:)?\d{1,2}:\d{2}[,.]\d{1,3})(?:\s+.*)?$',
    ).firstMatch(lines[timingIndex]);
    if (timing == null) continue;

    final start = _parseTimestamp(timing.group(1)!);
    final end = _parseTimestamp(timing.group(2)!);
    final text = lines
        .skip(timingIndex + 1)
        .map(_plainSubtitleText)
        .join('\n')
        .trim();
    if (start == null || end == null || end <= start || text.isEmpty) continue;
    cues.add(SubtitleCue(start: start, end: end, text: text));
  }

  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

List<SubtitleCue> activeSubtitleCues(
  List<SubtitleCue> cues,
  Duration playbackPosition, {
  Duration delay = Duration.zero,
}) {
  final subtitlePosition = playbackPosition - delay;
  if (subtitlePosition.isNegative) return const [];

  final active = <SubtitleCue>[];
  for (final cue in cues) {
    if (cue.start > subtitlePosition) break;
    if (cue.end > subtitlePosition) active.add(cue);
  }
  return active;
}

Duration? _parseTimestamp(String value) {
  final parts = value.replaceAll(',', '.').split(':');
  if (parts.length != 2 && parts.length != 3) return null;

  final hours = parts.length == 3 ? int.tryParse(parts[0]) : 0;
  final minutes = int.tryParse(parts[parts.length - 2]);
  final secondParts = parts.last.split('.');
  if (secondParts.length != 2) return null;
  final seconds = int.tryParse(secondParts[0]);
  final fraction = secondParts[1];
  final milliseconds = int.tryParse(fraction.padRight(3, '0').substring(0, 3));
  if (hours == null ||
      minutes == null ||
      seconds == null ||
      milliseconds == null ||
      minutes > 59 ||
      seconds > 59) {
    return null;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: milliseconds,
  );
}

String _plainSubtitleText(String text) {
  final withoutTags = text.replaceAll(
    RegExp(
      r'</?(?:b|i|u|c|v|ruby|rt|font)(?:\.[^\s>]*)?(?:\s+[^>]*)?>',
      caseSensitive: false,
    ),
    '',
  );
  return withoutTags.replaceAllMapped(
    RegExp(
      r'&(?:amp|lt|gt|nbsp|quot|apos|#\d+|#x[0-9a-f]+);',
      caseSensitive: false,
    ),
    (match) {
      final entity = match.group(0)!.toLowerCase();
      const named = {
        '&amp;': '&',
        '&lt;': '<',
        '&gt;': '>',
        '&nbsp;': ' ',
        '&quot;': '"',
        '&apos;': "'",
      };
      if (named.containsKey(entity)) return named[entity]!;
      final radix = entity.startsWith('&#x') ? 16 : 10;
      final digits = entity.substring(radix == 16 ? 3 : 2, entity.length - 1);
      final codePoint = int.tryParse(digits, radix: radix);
      return codePoint == null || codePoint > 0x10ffff
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    },
  );
}
