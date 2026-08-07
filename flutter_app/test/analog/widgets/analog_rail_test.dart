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

  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
    final cursorX = _posterAt(tester, 'Title 0').dx;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // After a settled step the item under the cursor is flush with where the
    // previous one sat. A rail that scrolled by pixels would land anywhere.
    expect(
      _posterAt(tester, 'Title 1').dx,
      moreOrLessEquals(cursorX, epsilon: 0.5),
    );

    // Its predecessor has moved a whole base slot to the left — base, not the
    // selected width, because the trail is drawn unscaled.
    //
    // The base sample is taken at distance >= 3 from the SELECTION, which is
    // now index 1: the falloff only reaches base on the third slot, so
    // sampling 'Title 3' here would measure a still-scaled poster.
    final passed = _posterAt(tester, 'Title 0');
    final base = tester.getSize(
      find.ancestor(
        of: find.text('Title 4'),
        matching: find.byType(AnalogPosterTile),
      ).first,
    ).width;
    expect(
      cursorX - passed.dx,
      greaterThan(base),
      reason: 'the passed title sits a full slot behind the cursor',
    );
  });

  testWidgets('scale falls away from the cursor and then holds flat', (
    tester,
  ) async {
    await _pumpRail(tester);

    double widthOf(String label) => tester.getSize(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AnalogPosterTile),
      ).first,
    ).width;

    final selected = widthOf('Title 0');
    final one = widthOf('Title 1');
    final two = widthOf('Title 2');
    final three = widthOf('Title 3');
    final four = widthOf('Title 4');

    expect(selected, greaterThan(one), reason: 'the selection is the biggest');
    expect(one, greaterThan(two));
    expect(two, greaterThan(three));
    // Reached base by the third slot and flat from there.
    expect(four, moreOrLessEquals(three, epsilon: 0.5));

    // Nothing overlaps: each poster starts after the previous one ends.
    for (final (a, b) in [('Title 0', 'Title 1'), ('Title 1', 'Title 2')]) {
      expect(
        _posterAt(tester, b).dx,
        greaterThan(_posterAt(tester, a).dx + widthOf(a) - 1),
        reason: '$b must start after $a ends',
      );
    }
  });

  testWidgets('even a short rail brings the selection to the first slot', (
    tester,
  ) async {
    // Few enough items that the row could have shown them all at once. It
    // still travels: "selected should always be first" has no exception for a
    // short list, and the slots to the right simply run out.
    final selection = await _pumpRail(tester, count: 3);
    final cursorX = _posterAt(tester, 'Title 0').dx;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(selection(), 1);
    expect(
      _posterAt(tester, 'Title 1').dx,
      moreOrLessEquals(cursorX, epsilon: 0.5),
      reason: 'the row must scroll to put the selection first',
    );
  });

  testWidgets('the selection is the first slot at every position, including the last', (
    tester,
  ) async {
    await _pumpRail(tester, count: 8);
    final cursorX = _posterAt(tester, 'Title 0').dx;

    for (var expected = 1; expected <= 7; expected++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        _posterAt(tester, 'Title $expected').dx,
        moreOrLessEquals(cursorX, epsilon: 0.5),
        reason: 'selection $expected must sit in the first slot',
      );
    }
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
