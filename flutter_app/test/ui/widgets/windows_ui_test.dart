import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/ui/ui.dart';

void main() {
  testWidgets('Windows caption controls are compact and preserve actions', (
    tester,
  ) async {
    var minimized = false;
    var maximized = false;
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Align(
          alignment: Alignment.topRight,
          child: WindowsCaptionControls(
            maximized: false,
            onMinimize: () => minimized = true,
            onToggleMaximize: () => maximized = true,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(WindowsCaptionControls)),
      const Size(windowsCaptionControlWidth * 3, integratedDesktopChromeHeight),
    );
    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Maximize'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('windows-minimize')));
    await tester.tap(find.byKey(const ValueKey('windows-maximize')));
    await tester.tap(find.byKey(const ValueKey('windows-close')));
    expect((minimized, maximized, closed), (true, true, true));
  });

  testWidgets('Windows caption surfaces remain transparent after hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: WindowsCaptionControls(
          maximized: false,
          onMinimize: () {},
          onToggleMaximize: () {},
          onClose: () {},
        ),
      ),
    );

    final surface = find.byKey(const ValueKey('windows-minimize-surface'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(surface));
    await tester.pump();

    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(of: surface, matching: find.byType(ColoredBox)),
          )
          .color,
      Colors.transparent,
    );

    await mouse.moveTo(const Offset(300, 300));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the open party tray stays inside a compact desktop viewport', (
    tester,
  ) async {
    // Was 300x240. The control is 3x the size it was, so that viewport is now
    // smaller than the chrome by construction and asserts nothing useful. This
    // is the app's actual minimum desktop window.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(640, 480));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
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

    // This replaced a 320px panel that had to be clamped against the viewport
    // to fit here at all. The tray is a COLUMN of buttons rising off the
    // handle, so the axis that can now overrun is the short one.
    await tester.tap(find.byType(PopcornControl));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(PopcornControl)).height, lessThan(480));
    expect(tester.takeException(), isNull);
  });
}
