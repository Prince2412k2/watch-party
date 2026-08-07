// The rail's *rendered* behaviour, as distinct from its arithmetic.
//
// movie_rail_parity_test.dart pins the numbers against the web. This pins that
// the widget actually draws them: that the cursor holds its position on screen
// while the track slides, which is the whole of "our selection cursor will
// always be the first position".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/stage_layout.dart';
import 'package:watchparty/analog/widgets/analog_poster.dart';
import 'package:watchparty/analog/widgets/analog_rail.dart';

List<AnalogRailItem> _items(int n) => [
  for (var i = 0; i < n; i++) AnalogRailItem(id: 'id-$i', label: 'Title $i'),
];

/// Pumps a rail whose selection is owned by the test, the way a stage owns it.
Future<int Function()> _pumpRail(
  WidgetTester tester, {
  int count = 40,
  int initial = 0,
  double width = 1200,
  ValueChanged<int>? onActivate,
}) async {
  var selection = initial;
  late StateSetter setLocal;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: StatefulBuilder(
            builder: (context, setState) {
              setLocal = setState;
              return AnalogRail(
                items: _items(count),
                selection: selection,
                size: StageSize.desktop,
                autofocus: true,
                onSelect: (i) => setLocal(() => selection = i),
                onActivate: onActivate ?? (_) {},
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => selection;
}

Offset _posterAt(WidgetTester tester, String label) => tester.getTopLeft(
  find.ancestor(
    of: find.text(label),
    matching: find.byType(AnalogPosterTile),
  ).first,
);

void main() {
  testWidgets('the cursor holds its screen position while the row slides', (
    tester,
  ) async {
    final selection = await _pumpRail(tester);

    final cursorX = _posterAt(tester, 'Title 0').dx;

    // Walk several steps. Each time, the newly selected title must be sitting
    // exactly where the previous one was: the cursor is fixed, the row moved.
    for (var expected = 1; expected <= 5; expected++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(selection(), expected);
      expect(
        _posterAt(tester, 'Title $expected').dx,
        moreOrLessEquals(cursorX, epsilon: 0.5),
        reason: 'title $expected should have slid into the cursor slot, '
            'not the cursor moved to it',
      );
    }
  });

  testWidgets('the track snaps to whole slots — never a half-shown poster', (
    tester,
  ) async {
    await _pumpRail(tester);
    final first = _posterAt(tester, 'Title 0').dx;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // After a settled step the item under the cursor is flush with where the
    // previous one sat. A rail that scrolled by pixels would land anywhere.
    expect(_posterAt(tester, 'Title 1').dx, moreOrLessEquals(first, epsilon: 0.5));

    // And its predecessor has moved a whole slot to the left, not a fraction.
    final step = _posterAt(tester, 'Title 2').dx - _posterAt(tester, 'Title 1').dx;
    expect(first - _posterAt(tester, 'Title 0').dx, moreOrLessEquals(step, epsilon: 0.5));
  });

  testWidgets('the cursor walks the last page once travel runs out', (
    tester,
  ) async {
    // Few enough items that the row cannot scroll at all.
    final selection = await _pumpRail(tester, count: 3);
    final firstX = _posterAt(tester, 'Title 0').dx;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(selection(), 1);
    // Nothing moved — instead the cursor advanced, which is the only way to
    // reach a title the row can't bring to slot 0.
    expect(_posterAt(tester, 'Title 0').dx, moreOrLessEquals(firstX, epsilon: 0.5));
    expect(_posterAt(tester, 'Title 1').dx, greaterThan(firstX));
  });

  testWidgets('stepping clamps at both ends rather than wrapping', (
    tester,
  ) async {
    final selection = await _pumpRail(tester, count: 6, initial: 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(selection(), 0, reason: 'left at the head must not wrap to the tail');

    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(selection(), 5, reason: 'right at the tail must not wrap to the head');
  });

  testWidgets('a long library mounts only a bounded window', (tester) async {
    await _pumpRail(tester, count: 400);
    // 400 titles must not be 400 poster tiles. railRendered bounds this to the
    // visible slots plus the warmed neighbours.
    expect(tester.widgetList(find.byType(AnalogPosterTile)).length, lessThan(30));
  });

  testWidgets('Enter activates the selected title, not the one under a pointer', (
    tester,
  ) async {
    final activated = <int>[];
    await _pumpRail(tester, onActivate: activated.add);

    // Pumped between steps: the rail is a controlled component reading
    // widget.selection, so two keys inside one frame both compute from the
    // stale value. A real keypress always has a frame behind it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(activated, [2]);
  });

  testWidgets('an empty rail says so instead of collapsing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalogRail(
            items: const [],
            selection: 0,
            size: StageSize.desktop,
            onSelect: (_) {},
            onActivate: (_) {},
            emptyLabel: 'No movies yet',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A silently empty row is indistinguishable from one that failed to load.
    expect(find.text('No movies yet'), findsOneWidget);
  });
}
