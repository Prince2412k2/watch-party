import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/app.dart';
import 'package:watchparty/state/state.dart';

void main() {
  testWidgets('app boots to the mock home screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // A server must be configured for the app to move past the setup
          // gate; the mock clients don't care about the actual URL.
          serverConfigProvider
              .overrideWith((ref) => ServerConfigNotifier(ref, 'http://mock.local')),
        ],
        child: const WatchpartyApp(enableWindowFrame: false),
      ),
    );
    // Let the mock homeProvider future resolve and the rails render.
    await tester.pumpAndSettle();

    // The nav rail brand is present.
    expect(find.text('Watchparty'), findsWidgets);
    // A mock section from HomeData renders on the home screen.
    expect(find.text('Continue Watching'), findsOneWidget);
  });
}
