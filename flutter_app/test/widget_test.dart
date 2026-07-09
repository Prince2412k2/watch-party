import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/app.dart';

void main() {
  testWidgets('app boots to the mock home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WatchpartyApp()));
    // Let the mock homeProvider future resolve and the rails render.
    await tester.pumpAndSettle();

    // The nav rail brand is present.
    expect(find.text('Watchparty'), findsWidgets);
    // A mock section from HomeData renders on the home screen.
    expect(find.text('Continue Watching'), findsOneWidget);
  });
}
