import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/analog.dart';
import 'package:watchparty/ui/analog_tokens.dart';

/// Drives a controlled [AnalogShelf] the way a real surface does, so these
/// tests exercise the same wiring the browse screen uses.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    this.itemCount = 8,
    this.onActivate,
    this.onEdge,
    required this.clock,
  });

  final int itemCount;
  final ValueChanged<int>? onActivate;
  final ValueChanged<int>? onEdge;
  final double Function() clock;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int index = 0;
  int changes = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: AnalogColor.stageGround,
      body: AnalogShelf(
        title: 'Movies',
        itemCount: widget.itemCount,
        itemWidth: 120,
        itemHeight: 180,
        autofocus: true,
        focusedIndex: index,
        nowMs: widget.clock,
        onFocusChanged: (next) => setState(() {
          index = next;
          changes++;
        }),
        onActivate: widget.onActivate,
        onEdge: widget.onEdge,
        semanticLabelBuilder: (i) => 'Item $i',
        itemBuilder: (_, i, _) => Text('Item $i'),
      ),
    ),
  );
}

/// Park the cursor over the first slot rather than the shelf centre: hovering
/// mid-shelf would land on some other slot and hand it focus, which is the
/// pointer path, not the wheel path under test.
Future<TestPointer> _parkOnFirstSlot(WidgetTester tester) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(
      tester.getCenter(find.byKey(const ValueKey('analog-shelf-item-0'))),
    ),
  );
  await tester.pump();
  return pointer;
}

Future<void> _wheel(WidgetTester tester, TestPointer pointer, double dy) async {
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pump();
}

void main() {
  testWidgets('the wheel steps focus through the shared stepped-scroll core', (
    tester,
  ) async {
    var clock = 0.0;
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key, clock: () => clock));
    await tester.pump();
    final pointer = await _parkOnFirstSlot(tester);

    // Below the 48px step threshold: nothing moves, however keen the gesture.
    await _wheel(tester, pointer, 30);
    expect(key.currentState!.index, 0);

    // Crossing the threshold moves exactly one item, never two.
    clock = 20;
    await _wheel(tester, pointer, 30);
    expect(key.currentState!.index, 1);

    // The decaying tail of a flick is momentum, not intent.
    clock = 40;
    await _wheel(tester, pointer, 5);
    expect(key.currentState!.index, 1);

    // Past the threshold again but inside the 110ms cooldown: a burst must not
    // discharge as a run of steps.
    clock = 60;
    await _wheel(tester, pointer, 60);
    expect(key.currentState!.index, 1);

    // A fresh gesture, well clear of the cooldown.
    clock = 200;
    await _wheel(tester, pointer, 60);
    expect(key.currentState!.index, 2);

    // 185px of raw wheel delta over five events produced two focus steps.
    expect(key.currentState!.changes, 2);
  });

  testWidgets('a reverse gesture restarts accumulation rather than cancelling', (
    tester,
  ) async {
    var clock = 0.0;
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key, clock: () => clock));
    await tester.pump();
    final pointer = await _parkOnFirstSlot(tester);

    await _wheel(tester, pointer, 40);
    clock = 20;
    await _wheel(tester, pointer, -40);
    expect(key.currentState!.index, 0, reason: 'neither direction banked 48px');
  });

  testWidgets('arrow keys step, Enter activates, and the ends detent', (
    tester,
  ) async {
    var activated = -1;
    final edges = <int>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(
        key: key,
        itemCount: 3,
        clock: () => 0,
        onActivate: (i) => activated = i,
        onEdge: edges.add,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(key.currentState!.index, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(key.currentState!.index, 0);
    expect(edges, [-1], reason: 'a step off the start is reported, not clamped');

    // "Scroll moves focus through items and then into the next collection."
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(key.currentState!.index, 2);
    expect(edges, [-1, 1]);
  });

  testWidgets('Select activates too, so a TV remote works', (tester) async {
    var activated = -1;
    await tester.pumpWidget(
      _Host(clock: () => 0, onActivate: (i) => activated = i),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(activated, 0);
  });

  testWidgets('arrow up/down are left to directional traversal', (tester) async {
    // Two shelves in one traversal group: down from the first has to reach the
    // second. Nothing in the old browse tree handled ArrowUp/ArrowDown at all,
    // which is also why no remote's D-pad worked.
    var upper = 0;
    var lower = 0;
    var lowerHasFocus = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  AnalogShelf(
                    itemCount: 3,
                    itemWidth: 80,
                    itemHeight: 100,
                    autofocus: true,
                    focusedIndex: upper,
                    onFocusChanged: (i) => setState(() => upper = i),
                    itemBuilder: (_, i, _) => Text('Upper $i'),
                  ),
                  AnalogShelf(
                    itemCount: 3,
                    itemWidth: 80,
                    itemHeight: 100,
                    focusedIndex: lower,
                    onFocusChanged: (i) => setState(() => lower = i),
                    onShelfFocusChanged: (has) =>
                        setState(() => lowerHasFocus = has),
                    itemBuilder: (_, i, _) => Text('Lower $i'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(lowerHasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(lower, 1, reason: 'the newly focused shelf owns the horizontal axis');
    expect(upper, 0, reason: 'and the one that lost focus does not move');
  });

  testWidgets('the focused slot is the one marked selected', (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key, itemCount: 3, clock: () => 0));
    await tester.pump();
    expect(_selectedLabel(tester), 'Item 0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_selectedLabel(tester), 'Item 1');
  });

  testWidgets('the inner list never scrolls on raw pointer delta', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(clock: () => 0));
    await tester.pump();
    final list = tester.widget<ListView>(find.byType(ListView));
    // Raw wheel delta must reach steppedScroll, not the scrollable: an
    // ordinary ListView would register with the pointer signal resolver first
    // and coast the shelf past the intended item.
    expect(list.physics, isA<NeverScrollableScrollPhysics>());
    expect(list.clipBehavior, Clip.hardEdge);
  });
}

String? _selectedLabel(WidgetTester tester) {
  for (final semantics in tester.widgetList<Semantics>(
    find.descendant(
      of: find.byType(AnalogShelf),
      matching: find.byType(Semantics),
    ),
  )) {
    final properties = semantics.properties;
    if (properties.selected ?? false) return properties.label;
  }
  return null;
}
