import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/api_client.dart';

import 'backend.dart';

/// Live integration test against a running backend — opt-in, see
/// `integration_test/README.md`. Not part of `flutter test`; an unreachable backend
/// fails rather than skips, because running this suite at all is a deliberate
/// choice and a silent pass would say nothing.
void main() {
  const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3005');

  test('DioApiClient logs in with root/root and lists the library (200)', () async {
    await requireBackend(base);

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
