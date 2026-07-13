import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/player/subtitle_cues.dart';

void main() {
  test('parses SRT multiline text and strips basic tags', () {
    final cues = parseSubtitleCues('''
1
00:00:01,250 --> 00:00:03,500
<i>Hello &amp; welcome</i>
Second line
''');

    expect(cues, hasLength(1));
    expect(cues.single.start, const Duration(milliseconds: 1250));
    expect(cues.single.end, const Duration(milliseconds: 3500));
    expect(cues.single.text, 'Hello & welcome\nSecond line');
  });

  test('parses WebVTT identifiers, settings, and hourless timestamps', () {
    final cues = parseSubtitleCues('''WEBVTT

intro
01:02.003 --> 01:04.500 align:start position:10%
<v Speaker>Hi</v> &#33;
''');

    expect(cues, hasLength(1));
    expect(
      cues.single.start,
      const Duration(minutes: 1, seconds: 2, milliseconds: 3),
    );
    expect(cues.single.text, 'Hi !');
  });

  test('returns overlapping cues and treats cue end as exclusive', () {
    final cues = parseSubtitleCues('''
00:00:01.000 --> 00:00:04.000
First

00:00:02.000 --> 00:00:03.000
Second
''');

    expect(
      activeSubtitleCues(
        cues,
        const Duration(milliseconds: 2500),
      ).map((cue) => cue.text),
      ['First', 'Second'],
    );
    expect(
      activeSubtitleCues(
        cues,
        const Duration(seconds: 3),
      ).map((cue) => cue.text),
      ['First'],
    );
  });

  test('positive delay displays a cue later', () {
    final cues = parseSubtitleCues('''
00:00:01.000 --> 00:00:02.000
Delayed
''');

    expect(
      activeSubtitleCues(
        cues,
        const Duration(milliseconds: 1500),
        delay: const Duration(seconds: 1),
      ),
      isEmpty,
    );
    expect(
      activeSubtitleCues(
        cues,
        const Duration(milliseconds: 2500),
        delay: const Duration(seconds: 1),
      ).single.text,
      'Delayed',
    );
  });

  test('skips malformed and empty cues', () {
    expect(
      parseSubtitleCues('00:00:03,000 --> 00:00:01,000\nBackwards'),
      isEmpty,
    );
    expect(parseSubtitleCues('not subtitle content'), isEmpty);
  });
}
