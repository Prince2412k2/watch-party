import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:watchparty/ui/theme.dart';
import 'package:watchparty/ui/widgets/icon_tray.dart';
import 'package:watchparty/ui/widgets/profile_menu.dart';

Widget _harness() => MaterialApp(
  theme: AppTheme.dark,
  home: const ProviderScope(
    child: Align(alignment: Alignment.topRight, child: ProfileMenu()),
  ),
);

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Watchparty',
      packageName: 'watchparty',
      version: '1.2.3',
      buildNumber: '7',
      buildSignature: '',
    );
  });

  testWidgets('the tray carries the installed version and update action', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ProfileMenu));
    await tester.pumpAndSettle();

    // The version and the action moved off the surface and into the update
    // button's tooltip when the dropdown card became a tray. Nothing was
    // dropped — assert on where it went, rather than deleting the coverage.
    expect(
      find.byTooltip('Version 1.2.3+7\nCheck for updates'),
      findsOneWidget,
    );
  });

  testWidgets('the control occupies only the avatar until it is opened', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Closed, the tray must take no width at all: it sits over artwork, and a
    // zero-height-but-not-zero-width tray would absorb clicks aimed at the
    // stage behind it. The buttons are in the tree the whole time — the clip
    // is the only thing keeping them out of the way.
    final closed = tester.getSize(find.byType(ProfileMenu)).width;

    await tester.tap(find.byType(ProfileMenu));
    await tester.pumpAndSettle();
    final open = tester.getSize(find.byType(ProfileMenu)).width;

    // Derived, not a magic number: the control's size is a design knob that
    // gets turned, and a literal here just means the test fails every time
    // somebody adjusts it. What must stay true is the RELATIONSHIP — closed is
    // the handle and nothing else, open is the handle plus a row of buttons.
    expect(closed, lessThanOrEqualTo(IconTray.thickness));
    expect(open, greaterThan(closed + TrayButton.size * 3));
  });
}
