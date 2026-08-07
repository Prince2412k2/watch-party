// The two kit-wide invariants, enforced across every control in
// lib/analog/chrome/.
//
// chrome.dart claims these rules "each have a test". This is that test. It is
// written as a loop over the kit rather than as a per-widget suite on purpose:
// the failure mode being defended against is someone ADDING a control that
// quietly does not honour them, and a per-widget suite cannot fail for a widget
// nobody wrote a case for.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/ui/analog_tokens.dart';

/// One control under test, with a hook to observe that it fired.
class _Case {
  const _Case(this.name, this.build);

  final String name;
  final Widget Function(VoidCallback onFired) build;
}

final _cases = <_Case>[
  _Case('AnalogButton', (fired) => AnalogButton(label: 'Play', onPressed: fired)),
  _Case(
    'AnalogIconButton',
    (fired) =>
        AnalogIconButton(icon: Icons.close, tooltip: 'Close', onPressed: fired),
  ),
  _Case('AnalogChip', (fired) => AnalogChip(label: 'Action', onPressed: fired)),
  _Case(
    'AnalogSwitch',
    (fired) => AnalogSwitch(
      value: false,
      onChanged: (_) => fired(),
      semanticLabel: 'Collaborative control',
    ),
  ),
];

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('nothing is hover-only', () {
    for (final testCase in _cases) {
      testWidgets('${testCase.name} takes focus and activates by keyboard', (
        tester,
      ) async {
        var fired = 0;
        await tester.pumpWidget(_host(testCase.build(() => fired++)));

        // Reachable by traversal, which is the actual claim: a remote and a
        // keyboard have no hover, and they arrive via Tab/d-pad, not by being
        // handed a FocusNode.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          primaryFocus?.context,
          isNotNull,
          reason: '${testCase.name} must be reachable by keyboard traversal',
        );

        // Enter and Space both activate. AnalogPressable fires on key UP so a
        // held key reads like a held pointer rather than repeating.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();

        expect(
          fired,
          2,
          reason: '${testCase.name} must activate on both Enter and Space',
        );
      });

      testWidgets('${testCase.name} carries an accessible name', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_host(testCase.build(() {})));

        // Something in the subtree must be nameable; an unnamed control is
        // invisible to a screen reader however it looks.
        final names = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .map((s) => s.properties.label)
            .where((label) => label != null && label.isNotEmpty)
            .toList();

        expect(
          names,
          isNotEmpty,
          reason: '${testCase.name} must expose an accessible name',
        );
        handle.dispose();
      });
    }

    testWidgets('a disabled control refuses focus', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        _host(AnalogButton(label: 'Play', onPressed: null, focusNode: node)),
      );

      node.requestFocus();
      await tester.pump();
      expect(
        node.hasFocus,
        isFalse,
        reason: 'there must be no way to reach a control that cannot act',
      );
    });
  });

  group('no state is signalled by colour alone', () {
    testWidgets('the switch reports position, not just fill', (tester) async {
      // The claim in analog_switch.dart is that with every colour collapsed the
      // knob is still on the left when off and on the right when on. Position
      // is what this asserts; it is independent of every Color in the widget.
      Future<Offset> knobCentre({required bool value}) async {
        await tester.pumpWidget(
          _host(
            AnalogSwitch(
              value: value,
              onChanged: (_) {},
              semanticLabel: 'Toggle',
            ),
          ),
        );
        await tester.pumpAndSettle();
        // The knob is the smallest Container in the track.
        final boxes = tester
            .widgetList<Container>(find.byType(Container))
            .toList();
        expect(boxes, isNotEmpty);
        final knob = find.byWidget(boxes.last);
        return tester.getCenter(knob);
      }

      final off = await knobCentre(value: false);
      final on = await knobCentre(value: true);

      expect(
        on.dx,
        greaterThan(off.dx),
        reason: 'the knob must travel; fill alone is not a state signal',
      );
    });

    testWidgets('danger is the only framed tone, rather than relying on red', (
      tester,
    ) async {
      // The frame is the non-colour signal; statusDanger reinforces it.
      //
      // This used to assert that danger's frame was DOUBLE the secondary's,
      // which was the right assertion when every tone carried a hairline and
      // danger had to out-weigh them. Buttons are tonal fills now and carry no
      // frame at all, so danger having one is the entire signal — a stronger
      // one than 2px-versus-1px ever was. The property under test is unchanged
      // and is what this asserts: with the red taken away, danger is still the
      // only button on the surface with an outline.
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnalogButton(
                label: 'Leave',
                tone: AnalogButtonTone.danger,
                onPressed: () {},
              ),
              AnalogButton(
                label: 'Stay',
                tone: AnalogButtonTone.secondary,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      double frameWidthOf(String label) {
        final container = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        // A tone with no frame has no `border` at all, not a zero-width one.
        final border = (container.decoration! as BoxDecoration).border;
        return border?.top.width ?? 0;
      }

      expect(
        frameWidthOf('Leave'),
        greaterThan(0),
        reason: 'danger must be legible without perceiving the red',
      );
      expect(
        frameWidthOf('Stay'),
        0,
        reason: 'a frame on the quiet default would cost danger its signal',
      );
    });

    testWidgets('the focus ring is a ring, not a tint', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        _host(AnalogButton(label: 'Play', onPressed: () {}, focusNode: node)),
      );
      expect(find.byType(AnalogFocusRing), findsOneWidget);

      AnalogFocusRing ring() =>
          tester.widget<AnalogFocusRing>(find.byType(AnalogFocusRing));
      expect(ring().visible, isFalse);

      node.requestFocus();
      await tester.pumpAndSettle();
      expect(
        ring().visible,
        isTrue,
        reason: 'focus must draw geometry a monochrome display can show',
      );
    });
  });

  group('the state layer', () {
    test('states do not sum — the strongest wins', () {
      // A pressed control is nearly always also hovered. Adding the layers
      // would wash the plate out and make the press invisible.
      const hoveredAndPressed = AnalogControlState(
        enabled: true,
        hovered: true,
        focused: true,
        pressed: true,
      );
      expect(
        hoveredAndPressed.stateLayerOpacity,
        AnalogStateLayer.pressedPct / 100,
      );

      const hoveredOnly = AnalogControlState(
        enabled: true,
        hovered: true,
        focused: false,
        pressed: false,
      );
      expect(hoveredOnly.stateLayerOpacity, AnalogStateLayer.hoverPct / 100);

      const disabled = AnalogControlState(
        enabled: false,
        hovered: true,
        focused: true,
        pressed: true,
      );
      expect(
        disabled.stateLayerOpacity,
        0,
        reason: 'a disabled control never lights up',
      );
    });

    test('the layer washes our ink, never a Material colour', () {
      const state = AnalogControlState(
        enabled: true,
        hovered: true,
        focused: false,
        pressed: false,
      );
      final washed = analogStateLayerOver(AnalogColor.stageSurface, state);

      expect(washed, isNot(AnalogColor.stageSurface));
      // Blending ink (warm, R > G > B) over the ramp must keep it warm; a
      // Material tint would push it blue.
      expect(washed.r, greaterThanOrEqualTo(washed.b));
    });

    test('a rest state is left exactly alone', () {
      const rest = AnalogControlState(
        enabled: true,
        hovered: false,
        focused: false,
        pressed: false,
      );
      expect(
        analogStateLayerOver(AnalogColor.stageSurface, rest),
        AnalogColor.stageSurface,
      );
    });
  });
}
