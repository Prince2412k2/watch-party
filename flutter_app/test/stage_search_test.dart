import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/stage_search.dart';
import 'package:watchparty/ui/ui.dart';

/// The stage's search, plus something else to click on so "look away" is
/// something the test can actually do.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: Column(
        children: [
          StageSearchField(
            hint: 'Search movies',
            query: _query,
            controller: _controller,
            onChanged: (q) => setState(() => _query = q),
          ),
          const SizedBox(height: 40),
          const Text('ELSEWHERE'),
        ],
      ),
    ),
  );
}

void main() {
  double widthOf(WidgetTester tester) =>
      tester.getSize(find.byType(StageSearchField)).width;

  testWidgets('starts as a button, not a field', (tester) async {
    await tester.pumpWidget(const _Harness());
    expect(find.byType(TextField), findsNothing);
    expect(widthOf(tester), lessThan(StageSearchField.width));
  });

  testWidgets('tapping it opens the tray and takes focus', (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(widthOf(tester), StageSearchField.width);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('looking away closes an empty tray', (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ELSEWHERE'));
    await tester.pumpAndSettle();

    expect(widthOf(tester), lessThan(StageSearchField.width));
  });

  testWidgets('but a typed query holds it open', (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'darjeeling');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ELSEWHERE'));
    await tester.pumpAndSettle();

    // The field is the only thing saying why the rail is short. Hiding it
    // would hide the reason the library looks half empty.
    expect(widthOf(tester), StageSearchField.width);
    expect(find.text('darjeeling'), findsOneWidget);
  });

  testWidgets('clearing empties the query and closes it', (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'darjeeling');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(widthOf(tester), lessThan(StageSearchField.width));
    expect(find.text('darjeeling'), findsNothing);
  });
}
