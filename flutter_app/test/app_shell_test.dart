import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/app_shell.dart';
import 'package:watchparty/ui/ui.dart';

void main() {
  testWidgets('AppShell shows full nav labels at desktop width', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AppShell(location: '/home', child: const SizedBox()),
    ));
    await tester.pump();

    // "Home" appears twice: the title-bar section name + the nav rail label.
    expect(find.text('Home'), findsNWidgets(2));
    expect(find.text('Browse'), findsOneWidget);
  });

  testWidgets('AppShell collapses to a compact icon rail below the breakpoint', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(600, 800));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AppShell(location: '/home', child: const SizedBox()),
    ));
    await tester.pump();

    // Only the title bar still spells "Home"; the nav rail label is gone
    // (tooltip-only) but its icon remains.
    expect(find.text('Home'), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });
}
