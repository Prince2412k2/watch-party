import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/app/app.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('app boots to the movie library', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // A server must be configured for the app to move past the setup
          // gate; the mock clients don't care about the actual URL.
          serverConfigProvider.overrideWith(
            (ref) => ServerConfigNotifier(ref, 'http://mock.local'),
          ),
          // This test bypasses `main()`'s boot sequence (which normally calls
          // `restore()`/`markUnauthenticated()`), so without an override
          // `authProvider` stays at its default logged-out state and Home
          // would render the login page instead of the mock catalog (guest
          // offline-browse, PLAN). Sign in directly to exercise that content.
          authProvider.overrideWith((ref) {
            final notifier = AuthNotifier(ref);
            notifier.state = const AuthState(
              user: User(userId: 'u1', name: 'Test User'),
              initialized: true,
            );
            return notifier;
          }),
        ],
        child: const WatchpartyApp(enableWindowFrame: false),
      ),
    );
    // Let the mock catalog resolve and the movie shelves render.
    await tester.pumpAndSettle();

    // The bottom nav renders the primary tabs.
    expect(find.text('Movies'), findsWidgets);
    expect(find.text('Continue watching'), findsNothing);
    expect(find.text('Library'), findsNothing);
    expect(find.text('12 Angry Men'), findsOneWidget);
    expect(find.text('Blade Runner'), findsNothing);

    await tester.tap(find.text('Shows'));
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsNothing);
    expect(find.text('12 Angry Men'), findsNothing);
    expect(find.text('Blade Runner'), findsOneWidget);

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(find.text('This row is unavailable right now.'), findsNothing);
    expect(find.text('Discover'), findsWidgets);
    expect(find.text('12 Angry Men'), findsOneWidget);
  });
}
