import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';

class _GatedRestoreApi extends MockApiClient {
  final restoredUser = Completer<User>();

  @override
  Future<User> me() => restoredUser.future;

  @override
  Future<void> logout() async {}
}

void main() {
  test('a pending restore cannot authenticate after logout', () async {
    final api = _GatedRestoreApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final restoring = container.read(authProvider.notifier).restore();
    await Future<void>.delayed(Duration.zero);
    await container.read(authProvider.notifier).logout();
    api.restoredUser.complete(const User(userId: 'old-user', name: 'Old User'));
    await restoring;

    expect(container.read(authProvider).isAuthenticated, isFalse);
  });
}
