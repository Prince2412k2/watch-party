import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:watchparty/ui/theme.dart';
import 'package:watchparty/ui/widgets/profile_menu.dart';

void main() {
  testWidgets('profile menu shows installed version and update action', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Watchparty',
      packageName: 'watchparty',
      version: '1.2.3',
      buildNumber: '7',
      buildSignature: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const ProviderScope(
          child: Align(alignment: Alignment.topRight, child: ProfileMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ProfileMenu));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.2.3+7'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });
}
