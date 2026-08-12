import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/ui.dart';

/// The shape that broke: a page inside a NESTED navigator, the way every
/// screen under the router's shell sits. The dialog goes up on the root
/// navigator, so the two are not the same stack — and popping the wrong one
/// takes the page instead of the dialog.
Widget _app({required void Function(bool) onResult}) => MaterialApp(
  home: Navigator(
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('THE PAGE'),
              Builder(
                builder: (inner) => TextButton(
                  onPressed: () async {
                    onResult(
                      await showConfirm(
                        inner,
                        title: 'Delete this download?',
                        confirmLabel: 'Delete',
                        danger: true,
                      ),
                    );
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('confirming closes the dialog and leaves the page standing', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(_app(onResult: (r) => result = r));

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this download?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('Delete this download?'), findsNothing);
    expect(
      find.text('THE PAGE'),
      findsOneWidget,
      reason: 'answering the dialog must not pop the page underneath it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling does the same, and answers false', (tester) async {
    bool? result;
    await tester.pumpWidget(_app(onResult: (r) => result = r));

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('THE PAGE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
