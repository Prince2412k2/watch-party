import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/theme.dart';
import 'package:watchparty/ui/widgets/ambient_wash.dart';

void main() {
  testWidgets('rapidly revisiting artwork does not duplicate switcher keys', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: AmbientWash()),
        ),
      ),
    );

    container.read(ambientArtworkIdProvider.notifier).state = 'a';
    await tester.pump();
    container.read(ambientArtworkIdProvider.notifier).state = 'b';
    await tester.pump(const Duration(milliseconds: 50));
    container.read(ambientArtworkIdProvider.notifier).state = 'a';
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });
}
