import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/analog.dart';
import 'package:watchparty/ui/analog_tokens.dart';

const _modes = [
  AnalogNavMode(id: '/home', label: 'Home', icon: Icons.home_outlined),
  AnalogNavMode(id: '/movies', label: 'Movies', icon: Icons.movie_outlined),
  AnalogNavMode(id: '/series', label: 'Shows', icon: Icons.tv_outlined),
  AnalogNavMode(id: '/discover', label: 'Discover'),
  AnalogNavMode(id: '/downloads', label: 'Downloads'),
];

Widget _host({required String current, required ValueChanged<String> onSelect}) =>
    MaterialApp(
      home: Scaffold(
        backgroundColor: AnalogColor.stageGround,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AnalogNav(
            modes: _modes,
            currentId: current,
            onSelect: onSelect,
          ),
        ),
      ),
    );

void main() {
  testWidgets('every mode stays visible along the bottom edge', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(current: '/movies', onSelect: (_) {}));
    await tester.pumpAndSettle();

    for (final mode in _modes) {
      expect(find.text(mode.label), findsOneWidget);
    }
    final nav = tester.getRect(find.byType(AnalogNav));
    expect(nav.bottom, 800);
  });

  testWidgets('tapping and Enter both select a mode', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      _host(current: '/movies', onSelect: selected.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Downloads'));
    expect(selected, ['/downloads']);

    await tester.tap(find.text('Discover'));
    expect(selected, ['/downloads', '/discover']);
  });

  testWidgets('selection does not rely on colour alone', (tester) async {
    await tester.pumpWidget(_host(current: '/series', onSelect: (_) {}));
    await tester.pumpAndSettle();

    TextStyle styleOf(String id) => tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(ValueKey('analog-nav-$id')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;

    expect(styleOf('/series').fontWeight, FontWeight.w700);
    expect(styleOf('/movies').fontWeight, FontWeight.w500);
    expect(styleOf('/series').color, AnalogColor.ink);
    expect(styleOf('/movies').color, AnalogColor.inkDim);
  });

  testWidgets('a mode carries its selected state to assistive tech', (
    tester,
  ) async {
    await tester.pumpWidget(_host(current: '/series', onSelect: (_) {}));
    await tester.pumpAndSettle();

    final selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.selected ?? false)
        .map((s) => s.properties.label)
        .toList();
    expect(selected, ['Shows']);
  });

  testWidgets('keyboard focus can reach and fire a mode', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_host(current: '/home', onSelect: selected.add));
    await tester.pumpAndSettle();

    // Nothing autofocuses the nav, so the first Tab lands on the first mode.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, ['/home']);
  });

  testWidgets('the hit target clears the touch floor', (tester) async {
    await tester.pumpWidget(_host(current: '/movies', onSelect: (_) {}));
    await tester.pumpAndSettle();
    final tab = tester.getSize(find.byKey(const ValueKey('analog-nav-/movies')));
    expect(tab.height, greaterThanOrEqualTo(AnalogHairline.hitPx));
    expect(tab.width, greaterThanOrEqualTo(AnalogHairline.hitPx));
  });
}
