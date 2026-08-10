import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/analog.dart';
import 'package:watchparty/ui/analog_tokens.dart';

Widget _host(Widget stage) => ProviderScope(child: MaterialApp(home: stage));

void main() {
  testWidgets('the stage is scenery: it never eats a gesture', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AnalogStage(
          backdropUrl: '/api/image/movie-1?type=Backdrop',
          child: Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const SizedBox(
                width: 200,
                height: 60,
                child: Text('Play'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Play'));
    expect(taps, 1);
    expect(find.byType(IgnorePointer), findsWidgets);
  });

  testWidgets('a backdrop change cross-fades rather than cutting', (
    tester,
  ) async {
    Widget stage(String? url) =>
        _host(AnalogStage(backdropUrl: url, child: const SizedBox.shrink()));

    await tester.pumpWidget(stage('/api/image/a?type=Backdrop'));
    await tester.pump();
    await tester.pumpWidget(stage('/api/image/b?type=Backdrop'));
    await tester.pump();
    // Mid-flight both frames are on the stage; a cut would leave only one.
    await tester.pump(AnalogMotion.backdropCrossMs ~/ 2);
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, AnalogMotion.backdropCrossMs);
    expect(switcher.switchInCurve, AnalogMotion.backdropCrossEase);
    expect(find.byType(FadeTransition), findsAtLeast(2));
  });

  testWidgets('rapidly revisiting a backdrop keeps switcher keys unique', (
    tester,
  ) async {
    Widget stage(String url) =>
        _host(AnalogStage(backdropUrl: url, child: const SizedBox.shrink()));

    await tester.pumpWidget(stage('/api/image/a?type=Backdrop'));
    await tester.pump();
    await tester.pumpWidget(stage('/api/image/b?type=Backdrop'));
    await tester.pump();
    await tester.pumpWidget(stage('/api/image/a?type=Backdrop'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(FadeTransition), findsAtLeast(2));
  });

  testWidgets('grain is fine and low-contrast, and lifts on focus', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AnalogStage(child: SizedBox.shrink())));
    await tester.pump();
    AnalogGrainPainter painterOf() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<AnalogGrainPainter>()
        .single;

    expect(painterOf().opacity, closeTo(AnalogGrain.opacityPct / 100, 1e-9));

    await tester.pumpWidget(
      _host(const AnalogStage(focused: true, child: SizedBox.shrink())),
    );
    await tester.pump();
    expect(
      painterOf().opacity,
      closeTo(
        (AnalogGrain.opacityPct + AnalogGrain.focusedBoostPct) / 100,
        1e-9,
      ),
    );
    // Low-contrast means low-contrast: a few percent, never a visible veil.
    expect(painterOf().opacity, lessThan(0.08));
  });

  testWidgets('the ground under a bare stage is warm, never pure black', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AnalogStage(child: SizedBox.shrink())));
    await tester.pump();
    final ground = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((box) => box.color)
        .firstWhere((color) => color == AnalogColor.stageGround);
    expect(ground.r, greaterThan(ground.g));
    expect(ground.g, greaterThan(ground.b));
    expect(ground, isNot(const Color(0xFF000000)));
  });
}
