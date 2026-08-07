// Overlapping action on the rail.
//
// The visible property is that the row's parts do not all stop on the same
// frame: the slot under the cursor settles first and the tail catches up. That
// is what gives the row weight rather than reading as a rigid sheet being
// dragged. It is invisible in a static screenshot and easy to delete by
// accident while tuning durations, so it is pinned here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/stage_layout.dart';
import 'package:watchparty/analog/widgets/analog_poster.dart';
import 'package:watchparty/analog/widgets/analog_rail.dart';
import 'package:watchparty/ui/analog_tokens.dart';

void main() {
  testWidgets('slots nearer the cursor settle before the tail does', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var selection = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AnalogRail(
              items: [
                for (var i = 0; i < 30; i++)
                  AnalogRailItem(id: 'id-$i', label: 'Title $i'),
              ],
              selection: selection,
              size: StageSize.desktop,
              autofocus: true,
              onSelect: (i) => setState(() => selection = i),
              onActivate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double xOf(String label) => tester
        .getTopLeft(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnalogPosterTile),
              )
              .first,
        )
        .dx;

    final restNear = xOf('Title 1');
    final restFar = xOf('Title 6');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    // Part-way through the move: the near slot has travelled further towards
    // its destination than the far one, because the far one started later.
    await tester.pump();
    await tester.pump(AnalogMotion.focusStepMs * 0.6);

    final movedNear = (xOf('Title 1') - restNear).abs();
    final movedFar = (xOf('Title 6') - restFar).abs();

    expect(
      movedNear,
      greaterThan(movedFar),
      reason: 'the tail must lag the cursor, not move in lockstep with it',
    );

    // And everything still lands: the lag delays arrival, it does not change
    // where the row ends up.
    await tester.pumpAndSettle();
    expect(xOf('Title 1'), lessThan(restNear));
    expect(xOf('Title 6'), lessThan(restFar));
  });

  test('the lag is capped so a long rail does not ripple', () {
    // Growing the delay without bound turns follow-through into a travelling
    // wave, which reads as lag rather than as weight.
    expect(
      AnalogMotion.slotLagMaxMs.inMilliseconds,
      lessThan(AnalogMotion.focusStepMs.inMilliseconds * 2),
      reason: 'the tail must never take twice the cursor lead to arrive',
    );
    expect(
      AnalogMotion.slotLagMs.inMilliseconds,
      greaterThan(0),
      reason: 'zero per-slot lag is no follow-through at all',
    );
  });

  testWidgets('reduced motion removes the lag with the travel', (tester) async {
    // Follow-through is a spatial effect, so it goes when motion does — the
    // selection still changes, it just arrives instantly.
    final reduced = motionProfile(true);
    expect(reduced.animate, isFalse);
    expect(reduced.focusStep, Duration.zero);
  });
}
