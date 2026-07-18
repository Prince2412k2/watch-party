import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/ui.dart';

void main() {
  testWidgets('watch-party DotLottie asset decodes and renders', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: WatchPartyAnimation())),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(WatchPartyAnimation), findsOneWidget);
  });
}
