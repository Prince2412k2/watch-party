import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/analog.dart';
import 'package:watchparty/ui/analog_tokens.dart';

Widget _host({
  required AnalogToolboxCorner corner,
  required String label,
  Widget? child,
  int badgeCount = 0,
  bool live = false,
}) => MaterialApp(
  home: Scaffold(
    backgroundColor: AnalogColor.stageGround,
    body: Align(
      alignment: corner == AnalogToolboxCorner.upperRight
          ? Alignment.topRight
          : Alignment.bottomRight,
      child: AnalogToolbox(
        // Keyed by corner so a test that walks both corners gets a fresh
        // toolbox each time rather than reusing the previous open state.
        key: ValueKey(corner),
        corner: corner,
        label: label,
        icon: Icons.person_outline,
        badgeCount: badgeCount,
        live: live,
        child: child ?? const Text('Create a party'),
      ),
    ),
  ),
);

void main() {
  testWidgets('a toolbox is compact until activated, then expands inline', (
    tester,
  ) async {
    await tester.pumpWidget(_host(
      corner: AnalogToolboxCorner.lowerRight,
      label: 'Watch Party',
    ));
    await tester.pumpAndSettle();

    // Closed costs nothing: the panel is not built, not merely hidden.
    expect(find.text('Create a party'), findsNothing);
    final closed = tester.getSize(find.byType(AnalogToolbox));

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Create a party'), findsOneWidget);
    expect(
      tester.getSize(find.byType(AnalogToolbox)).height,
      greaterThan(closed.height),
    );
  });

  testWidgets('the expanded panel stays in its corner and stays capped', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(
      corner: AnalogToolboxCorner.upperRight,
      label: 'Profile',
      child: const SizedBox(width: 900, height: 900),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    // "must not cover primary content or compete with the bottom navigation"
    final toolbox = tester.getRect(find.byType(AnalogToolbox));
    expect(toolbox.width, lessThanOrEqualTo(320));
    expect(toolbox.height, lessThanOrEqualTo(420 + 60));
    expect(toolbox.right, 1280);
    expect(toolbox.top, 0);
  });

  testWidgets('the panel opens away from the edge the trigger is pinned to', (
    tester,
  ) async {
    for (final corner in AnalogToolboxCorner.values) {
      await tester.pumpWidget(_host(corner: corner, label: 'Toolbox'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      final trigger = tester.getRect(find.byIcon(Icons.person_outline));
      final panel = tester.getRect(find.text('Create a party'));
      if (corner.panelBelowTrigger) {
        expect(panel.top, greaterThan(trigger.bottom));
      } else {
        expect(panel.bottom, lessThan(trigger.top));
      }
    }
  });

  testWidgets('Escape and an outside tap both close it', (tester) async {
    await tester.pumpWidget(_host(
      corner: AnalogToolboxCorner.lowerRight,
      label: 'Watch Party',
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Create a party'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Create a party'), findsNothing);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Create a party'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Create a party'), findsNothing);
  });

  testWidgets('live and waiting states are marked on the compact control', (
    tester,
  ) async {
    await tester.pumpWidget(_host(
      corner: AnalogToolboxCorner.lowerRight,
      label: 'Watch Party',
      badgeCount: 3,
      live: true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    final expanded = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.label == 'Watch Party')
        .single;
    expect(expanded.properties.expanded, isFalse);
    expect(expanded.properties.button, isTrue);
  });

  testWidgets('open state can be driven from outside', (tester) async {
    var open = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AnalogToolbox(
              corner: AnalogToolboxCorner.upperRight,
              label: 'Profile',
              icon: Icons.person_outline,
              open: open,
              onOpenChanged: (next) => setState(() => open = next),
              child: const Text('Sign out'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsNothing);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(open, isTrue);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
