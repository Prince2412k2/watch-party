import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/ui/ui.dart';

void main() {
  testWidgets('the open party tray stays inside a compact desktop viewport', (
    tester,
  ) async {
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

    await tester.tap(find.byType(PopcornControl));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(PopcornControl)).height, lessThan(480));
    expect(tester.takeException(), isNull);
  });
}
