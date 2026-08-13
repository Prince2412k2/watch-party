import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/app/config.dart';
import 'package:watchparty/app/screens/login_screen.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/state/state.dart';

/// A build that names its own backend should never ask anyone for one.
///
/// These run in BOTH shapes, because the answer is a compile-time constant and
/// a plain `flutter test` gets the un-baked one. Run the baked half with:
///
///   flutter test --dart-define=API_BASE=https://example.test
///
/// Each test asserts whichever behaviour the current build should have, so both
/// invocations are green and neither silently skips.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the baked origin is present exactly when one was defined', () {
    expect(bakedServerUrl, AppConfig.hasBakedServer ? AppConfig.apiBase : null);
    if (AppConfig.hasBakedServer) {
      expect(bakedServerUrl, isNot('http://localhost:3005'));
    }
  });

  testWidgets('the login page offers a server field only when it needs one', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(MockApiClient())],
        child: const MaterialApp(
          home: AnalogToastHost(child: LoginScreen()),
        ),
      ),
    );
    await tester.pump();

    // The chip carries the host name, and is the only way to open the dialog.
    final chip = find.byIcon(Icons.dns_outlined);
    expect(
      chip,
      AppConfig.hasBakedServer ? findsNothing : findsOneWidget,
      reason: 'hasBakedServer=${AppConfig.hasBakedServer}',
    );
  });

  test('signing out of a baked build falls back to the baked origin', () async {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(MockApiClient()),
        serverConfigProvider.overrideWith(
          (ref) => ServerConfigNotifier(ref, 'https://runtime.example'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(serverConfigProvider.notifier).clear();

    // Dropping to null here is what would strand a baked build on a server
    // picker it does not show — the app would have no origin and no way to be
    // given one.
    expect(container.read(serverConfigProvider), bakedServerUrl);
    if (AppConfig.hasBakedServer) {
      expect(container.read(serverConfigProvider), isNotNull);
    }
  });
}
