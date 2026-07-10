import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/state/state.dart';

/// Live integration test against the running backend (E2). Requires the dev
/// server on http://localhost:3005 (root/root). Skips rather than fails if
/// unreachable, so `flutter test` stays green offline.
void main() {
  // logout() clears the persisted server config, which reads SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3005');

  Future<bool> backendUp() async {
    try {
      final res = await HttpClient()
          .getUrl(Uri.parse('$base/api/health'))
          .then((r) => r.close())
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  test('authProvider logs in root/root and reaches authenticated state', () async {
    if (!await backendUp()) {
      markTestSkipped('backend not reachable at $base');
      return;
    }

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
    if (!await backendUp()) {
      markTestSkipped('backend not reachable at $base');
      return;
    }

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
