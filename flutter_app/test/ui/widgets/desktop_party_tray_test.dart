import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/ui/ui.dart';

void main() {
  testWidgets('the open party tray stays inside a compact desktop viewport', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(640, 480));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => AnalogToastHost(child: child!),
          home: const MediaQuery(
            data: MediaQueryData(size: Size(640, 480)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomRight,
                child: PopcornControl(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopcornControl));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(PopcornControl)).height, lessThan(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tray casts its shadow from outside its own reveal clip', (
    tester,
  ) async {
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 1),
      value: 1,
    );
    addTearDown(animation.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: IconTray(
                animation: animation,
                axis: Axis.vertical,
                children: [
                  TrayButton(icon: Icons.add, tooltip: 'Add', onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A blur painted INSIDE the clip that reveals the pill is not a shadow, it
    // is a grey rectangle with hard edges — which is what the tray had. So the
    // box carrying the shadow has to sit above the ClipRect, and nothing below
    // it may carry one.
    final shadowed = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          (w.decoration as BoxDecoration).boxShadow?.isNotEmpty == true,
    );
    expect(shadowed, findsOneWidget);
    expect(
      find.descendant(of: shadowed, matching: find.byType(ClipRect)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(ClipRect).first, matching: shadowed),
      findsNothing,
    );
  });
}
