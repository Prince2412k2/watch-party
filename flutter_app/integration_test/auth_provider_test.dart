import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/state/state.dart';

import 'backend.dart';

/// Live integration test against a running backend (E2) — opt-in, see
/// `integration_test/README.md`. Not part of `flutter test`; an unreachable backend
/// fails rather than skips.
void main() {
  // logout() clears the persisted server config, which reads SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3005');

  test('authProvider logs in root/root and reaches authenticated state', () async {
    await requireBackend(base);

    final api = DioApiClient(baseUrl: base);
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    expect(container.read(authProvider).isAuthenticated, isFalse);

    await container.read(authProvider.notifier).login('root', 'root');

    final state = container.read(authProvider);
    expect(state.isAuthenticated, isTrue);
    expect(state.error, isNull);
    expect(state.user!.name, 'root');

    await container.read(authProvider.notifier).logout();
    expect(container.read(authProvider).isAuthenticated, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('authProvider.restore() re-authenticates from a persisted cookie jar', () async {
    await requireBackend(base);

    final dir = await Directory.systemTemp.createTemp('wp_auth_test_');
    addTearDown(() => dir.delete(recursive: true));
    final cookieDir = '${dir.path}/cookies';

    // First "run": log in, cookie jar persists to disk.
    final api1 = await DioApiClient.persistent(cookieDir, baseUrl: base);
    final container1 = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api1)],
    );
    addTearDown(container1.dispose);
    await container1.read(authProvider.notifier).login('root', 'root');
    expect(container1.read(authProvider).isAuthenticated, isTrue);

    // Second "run": a fresh client/container over the same cookie directory —
    // simulates an app restart. restore() should re-authenticate via /me
    // without calling login() again.
    final api2 = await DioApiClient.persistent(cookieDir, baseUrl: base);
    final container2 = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api2)],
    );
    addTearDown(container2.dispose);

    expect(container2.read(authProvider).initialized, isFalse);
    await container2.read(authProvider.notifier).restore();

    final restored = container2.read(authProvider);
    expect(restored.initialized, isTrue);
    expect(restored.isAuthenticated, isTrue);
    expect(restored.user!.name, 'root');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
