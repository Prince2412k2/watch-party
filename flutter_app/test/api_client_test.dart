import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/api_client.dart';

/// Live integration test against the running backend. Requires the dev server
/// on http://localhost:3005 (root/root). If the backend is unreachable the test
/// is skipped rather than failed, so `flutter test` stays green offline.
void main() {
  const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3005');

  test('DioApiClient logs in with root/root and lists the library (200)', () async {
    // Probe reachability first.
    try {
      final probe = await HttpClient()
          .getUrl(Uri.parse('$base/api/health'))
          .then((r) => r.close())
          .timeout(const Duration(seconds: 2));
      expect(probe.statusCode, 200);
    } catch (_) {
      markTestSkipped('backend not reachable at $base');
      return;
    }

    final api = DioApiClient(baseUrl: base);

    final user = await api.login('root', 'root');
    expect(user.name, 'root');
    expect(user.userId, isNotEmpty);

    // The persisted connect.sid cookie must carry the session to /me.
    final me = await api.me();
    expect(me.userId, user.userId);

    // Session cookie authorizes the library route → 200 with items.
    final items = await api.items();
    expect(items, isNotEmpty);
    expect(items.first.id, isNotEmpty);
    expect(items.first.name, isNotEmpty);

    await api.logout();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
