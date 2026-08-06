import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/app/screens/gallery_screen.dart';
import 'package:watchparty/ui/ui.dart';

/// The rebuilt primitives need the theme and an [AnalogToastHost] ancestor —
/// the real app supplies both from app.dart's builder; standalone pumps mirror
/// that here (assertions are unchanged).
Widget _analog(BuildContext context, Widget? child) =>
    Theme(data: AppTheme.dark, child: AnalogToastHost(child: child!));

void main() {
  testWidgets('gallery renders every core widget without error', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(1400, 6000);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MaterialApp(theme: null, builder: _analog, home: const GalleryScreen()),
    );
    await tester.pump();

    expect(find.text('Design system gallery'), findsOneWidget);
    expect(find.byType(AppButton), findsWidgets);
    expect(find.byType(AppTextField), findsWidgets);
    expect(find.byType(PosterCard), findsWidgets);
    expect(find.byType(LoadingSkeleton), findsWidgets);
    expect(find.byType(NavRail), findsNWidgets(2));
    expect(find.byType(AppChip), findsWidgets);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('AppDialog.show presents title and actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: _analog,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: AppButton(
                label: 'Open',
                onPressed: () => AppDialog.show(
                  context,
                  title: 'Confirm',
                  body: 'Are you sure?',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Are you sure?'), findsOneWidget);
  });
}
