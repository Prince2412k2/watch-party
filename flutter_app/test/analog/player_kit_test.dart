// The analog player control kit (#67): timeline, volume, toasts, settings
// stack and the one auto-hide clock.
//
// The behaviour these widgets share with React lives in
// app/shared/design/interaction.json and is covered by
// interaction_parity_test.dart. This file covers the Flutter-side geometry and
// wiring: the layer stack, the invisible hit target, and the fact that both
// auto-hide owners now run the same state machine.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/player/analog_settings_stack.dart';
import 'package:watchparty/analog/player/analog_timeline.dart';
import 'package:watchparty/analog/player/analog_toast_stack.dart';
import 'package:watchparty/analog/player/analog_volume.dart';
import 'package:watchparty/analog/player/auto_hide_controller.dart';
import 'package:watchparty/analog/player_core.dart';
import 'package:watchparty/ui/analog_tokens.dart';

const _track = Rect.fromLTWH(0, 0, 100, 2);

void main() {
  group('timeline layer geometry', () {
    test('disjoint ranges keep a visible gap between them', () {
      // Two 40px runs abutting at x=40 in *time* but genuinely separate.
      final rects = timelineSegments(
        const [TimelineRange(0, 0.3), TimelineRange(0.5, 0.8)],
        _track,
        gapPx: AnalogHairline.rangeGapPx,
      );
      expect(rects, hasLength(2));
      expect(rects[0].left, 0);
      expect(rects[0].right, 30);
      expect(rects[1].left, 50);
      expect(rects[1].right, 80);
      // The engine can report ranges that touch to the pixel; the gap is only
      // opened where one is needed.
      expect(rects[1].left - rects[0].right, greaterThanOrEqualTo(
        AnalogHairline.rangeGapPx,
      ));
    });

    test('a boundary tighter than the gap is opened up by shortening the left '
        'span, never by moving the right one', () {
      final rects = timelineSegments(
        const [TimelineRange(0, 0.5), TimelineRange(0.505, 1)],
        _track,
      );
      expect(rects, hasLength(2));
      // The later range still starts exactly where it starts.
      expect(rects[1].left, closeTo(50.5, 1e-9));
      expect(rects[1].left - rects[0].right, AnalogHairline.rangeGapPx);
    });

    test('contiguous and overlapping ranges merge instead of showing a seam', () {
      expect(
        timelineSegments(
          const [TimelineRange(0, 0.4), TimelineRange(0.4, 0.9)],
          _track,
        ),
        [const Rect.fromLTWH(0, 0, 90, 2)],
      );
      expect(
        timelineSegments(
          const [TimelineRange(0.2, 0.6), TimelineRange(0.1, 0.3)],
          _track,
        ),
        [const Rect.fromLTWH(10, 0, 50, 2)],
      );
    });

    test('empty, inverted and out-of-bounds ranges are dropped or clamped', () {
      expect(timelineSegments(const [], _track), isEmpty);
      expect(timelineSegments(const [TimelineRange(0.5, 0.5)], _track), isEmpty);
      expect(timelineSegments(const [TimelineRange(0.8, 0.2)], _track), isEmpty);
      expect(
        timelineSegments(const [TimelineRange(-1, 2)], _track),
        [const Rect.fromLTWH(0, 0, 100, 2)],
      );
      expect(timelineSegments(const [TimelineRange(0, 1)], Rect.zero), isEmpty);
    });

    test('a sliver too narrow to survive the gap is dropped rather than drawn', () {
      final rects = timelineSegments(
        const [TimelineRange(0.5, 0.505), TimelineRange(0.51, 1)],
        _track,
      );
      expect(rects, hasLength(1));
      expect(rects.single.left, closeTo(51, 1e-9));
    });

    test('the visible line thickens on activity without changing the row', () {
      const size = Size(200, AnalogHairline.hitPx);
      final idle = AnalogTimelinePainter.trackRect(size, active: false);
      final active = AnalogTimelinePainter.trackRect(size, active: true);
      expect(idle.height, AnalogHairline.idlePx);
      expect(active.height, AnalogHairline.activePx);
      // Both are centred in the same box: nothing around the bar moves.
      expect(idle.center.dy, active.center.dy);
      expect(idle.center.dy, size.height / 2);
    });
  });

  group('AnalogTimeline', () {
    Future<AnalogTimelinePainter> pumpTimeline(
      WidgetTester tester, {
      List<TimelineRange> buffered = const [],
      List<TimelineRange> cached = const [],
      bool enabled = true,
      List<Duration>? commits,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: AnalogTimeline(
                  key: const Key('timeline'),
                  position: const Duration(minutes: 10),
                  duration: const Duration(minutes: 100),
                  enabled: enabled,
                  buffered: buffered,
                  cached: cached,
                  onPreview: (_) {},
                  onCommit: (p) => commits?.add(p),
                  onHoverPreview: (_, _) {},
                  onHoverEnd: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('timeline')),
          matching: find.byType(CustomPaint),
        ),
      );
      return paint.painter! as AnalogTimelinePainter;
    }

    testWidgets('cached spans stay a separate layer from the network buffer', (
      tester,
    ) async {
      final painter = await pumpTimeline(
        tester,
        buffered: const [TimelineRange(0.1, 0.2)],
        cached: const [TimelineRange(0.6, 0.9), TimelineRange(0.95, 1)],
      );
      expect(painter.buffered, const [TimelineRange(0.1, 0.2)]);
      expect(painter.cached, hasLength(2));
      // Weakest to strongest: unloaded < buffer < cached < played.
      expect(AnalogColor.line.a, lessThan(AnalogColor.inkFaint.a));
      expect(AnalogColor.inkFaint.a, lessThan(AnalogColor.inkDim.a));
      expect(AnalogColor.inkDim.a, lessThan(AnalogColor.accent.a));
    });

    testWidgets('the hit target is hitPx tall, well clear of the visible line', (
      tester,
    ) async {
      final commits = <Duration>[];
      await pumpTimeline(tester, commits: commits);
      final box = tester.getRect(find.byKey(const Key('timeline')));
      expect(box.height, AnalogHairline.hitPx);

      // A press 10px above the hairline — nowhere near the 2px line — still
      // seeks, which is the whole point of the invisible target.
      await tester.tapAt(Offset(box.left + box.width / 2, box.center.dy - 10));
      await tester.pump();
      expect(commits, hasLength(1));
      expect(commits.single, const Duration(minutes: 50));
    });

    testWidgets('a read-only guest still gets a handle and a position', (
      tester,
    ) async {
      final commits = <Duration>[];
      final painter = await pumpTimeline(
        tester,
        enabled: false,
        commits: commits,
      );
      expect(painter.fraction, closeTo(0.1, 1e-9));
      final box = tester.getRect(find.byKey(const Key('timeline')));
      await tester.tapAt(box.center);
      await tester.pump();
      expect(commits, isEmpty);
    });
  });

  group('AnalogVolume', () {
    testWidgets('dragging down lowers the level and up raises it', (
      tester,
    ) async {
      final levels = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnalogVolume(
                volume: 50,
                trackKey: const Key('volume'),
                onChanged: levels.add,
                onToggleMute: () {},
              ),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byKey(const Key('volume')));
      // Top of the track is loudest.
      await tester.tapAt(Offset(box.center.dx, box.top + 1));
      await tester.pump();
      expect(levels.last, greaterThan(90));

      await tester.tapAt(Offset(box.center.dx, box.bottom - 1));
      await tester.pump();
      expect(levels.last, lessThan(10));
    });

    testWidgets('arrow keys adjust the level and mute keeps its tooltip', (
      tester,
    ) async {
      final levels = <double>[];
      var muted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnalogVolume(
                volume: 40,
                trackKey: const Key('volume'),
                onChanged: levels.add,
                onToggleMute: () => muted++,
              ),
            ),
          ),
        ),
      );
      // Clicking the track focuses it, so the arrows land here.
      await tester.tap(find.byKey(const Key('volume')));
      await tester.pump();
      levels.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(levels, [40 + kAnalogVolumeKeyStep]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(levels.last, 40 - kAnalogVolumeKeyStep);

      await tester.tap(find.byTooltip('Mute'));
      await tester.pump();
      expect(muted, 1);
    });
  });

  group('AnalogToastStack', () {
    ToastMessage message(int index) => ToastMessage(
      id: 'm$index',
      sender: 'Sender $index',
      preview: 'Message $index',
      receivedAtMs: index,
    );

    testWidgets('draws the visible stack and collapses the rest into a count', (
      tester,
    ) async {
      var queue = const ToastQueueState();
      for (var i = 0; i < 5; i++) {
        queue = pushToast(queue, message(i));
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AnalogToastStack(view: toastView(queue))),
        ),
      );
      await tester.pumpAndSettle();

      // Three newest are drawn; the two older ones become a count.
      expect(find.text('Message 4'), findsOneWidget);
      expect(find.text('Message 2'), findsOneWidget);
      expect(find.text('Message 1'), findsNothing);
      expect(find.text('+2 earlier messages'), findsOneWidget);
      expect(find.text('Sender 4'), findsOneWidget);
    });

    testWidgets('an open drawer draws nothing at all', (tester) async {
      final queue = setChatOpen(
        pushToast(const ToastQueueState(), message(0)),
        true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AnalogToastStack(view: toastView(queue))),
        ),
      );
      expect(find.text('Message 0'), findsNothing);
    });
  });

  group('AnalogSettingsStack', () {
    testWidgets('the gear expands its rows UPWARD, not as a modal', (
      tester,
    ) async {
      var opened = 0;
      final opens = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: AnalogSettingsStack(
                onOpenChanged: opens.add,
                entries: [
                  AnalogSettingsEntry(
                    icon: Icons.tune,
                    label: 'Subtitle settings',
                    onTap: () => opened++,
                  ),
                  const AnalogSettingsEntry(
                    icon: Icons.memory,
                    label: 'Video decoder',
                    detail: 'Hardware',
                    onTap: _noop,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Subtitle settings'), findsNothing);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(opens, [true]);
      expect(find.text('Video decoder'), findsOneWidget);
      expect(find.text('Hardware'), findsOneWidget);
      // Every row sits above the gear it grew out of.
      expect(
        tester.getBottomLeft(find.text('Video decoder')).dy,
        lessThan(tester.getTopLeft(find.byIcon(Icons.settings)).dy),
      );

      await tester.tap(find.text('Subtitle settings'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(opens, [true, false]);
      expect(find.text('Video decoder'), findsNothing);
    });

    testWidgets('a row the viewer may not act on is shown greyed, not dropped', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: AnalogSettingsStack(
                entries: [
                  AnalogSettingsEntry(
                    icon: Icons.memory,
                    label: 'Video decoder',
                    detail: 'Hardware',
                    enabled: false,
                    onTap: () => taps++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Still readable: the guest can see WHICH decoder is running.
      expect(find.text('Video decoder'), findsOneWidget);
      expect(find.text('Hardware'), findsOneWidget);
      await tester.tap(find.text('Video decoder'));
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(find.text('Video decoder'), findsOneWidget);
    });
  });

  group('AnalogAutoHideController', () {
    /// One controller class is the whole point: the player chrome and the party
    /// screen used to run separate hand-written timers, with the hide rule, the
    /// chat exception and the paused exception spelled out twice.
    AnalogAutoHideController build({bool playing = true}) {
      final controller = AnalogAutoHideController(playing: playing);
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets('hides after three quiet seconds of playback', (tester) async {
      final controller = build();
      expect(controller.visible, isTrue);

      await tester.pump(const Duration(milliseconds: 2500));
      expect(controller.visible, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.visible, isFalse);
    });

    testWidgets('input brings it back and restarts the clock', (tester) async {
      final controller = build();
      await tester.pump(AnalogTiming.chromeAutoHideMs);
      expect(controller.visible, isFalse);

      controller.noteInput(PlayerInputKind.pointer);
      expect(controller.visible, isTrue);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(controller.visible, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.visible, isFalse);
    });

    testWidgets('a hold pins it open, and releasing grants the FULL three '
        'seconds rather than hiding instantly', (tester) async {
      final controller = build();
      controller.hold('chat');
      await tester.pump(const Duration(seconds: 30));
      expect(controller.visible, isTrue);
      expect(controller.holds, ['chat']);

      controller.release('chat');
      expect(controller.visible, isTrue);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(controller.visible, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.visible, isFalse);
    });

    testWidgets('holds nest, and the last one out starts the clock', (
      tester,
    ) async {
      final controller = build();
      controller
        ..hold('chat')
        ..hold('scrub')
        ..release('chat');
      await tester.pump(const Duration(seconds: 30));
      expect(controller.visible, isTrue);
      controller.release('scrub');
      await tester.pump(AnalogTiming.chromeAutoHideMs);
      expect(controller.visible, isFalse);
    });

    testWidgets('paused playback never hides', (tester) async {
      final controller = build(playing: false);
      await tester.pump(const Duration(seconds: 30));
      expect(controller.visible, isTrue);

      controller.setPlaying(true);
      await tester.pump(AnalogTiming.chromeAutoHideMs);
      expect(controller.visible, isFalse);

      // Pausing reveals the chrome and keeps it up.
      controller.setPlaying(false);
      expect(controller.visible, isTrue);
      await tester.pump(const Duration(seconds: 30));
      expect(controller.visible, isTrue);
    });
  });
}

void _noop() {}
