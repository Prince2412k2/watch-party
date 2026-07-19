import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:watchparty/ui/ui.dart';
import 'package:watchparty/ui/widgets/party_widget.dart';

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

  testWidgets('PartyWidget stays inside a compact desktop viewport', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(300, 240));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => sc.ShadcnLayer(
            theme: AppShadcnTheme.light,
            themeMode: sc.ThemeMode.light,
            child: child!,
          ),
          home: const MediaQuery(
            data: MediaQueryData(size: Size(300, 240)),
            child: Scaffold(body: Align(child: PartyWidget())),
          ),
        ),
      ),
    );
    await tester.pump();

    final size = tester.getSize(
      find.byKey(const ValueKey('party-widget-panel')),
    );
    expect(size.width, lessThanOrEqualTo(262));
    expect(size.height, lessThanOrEqualTo(158));
    expect(tester.takeException(), isNull);
  });
}
