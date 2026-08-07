import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/state/state.dart';

import 'backend.dart';

/// Live integration test against a running backend (E3) — opt-in, see
/// `integration_test/README.md`. Logs in exactly ONCE (the login endpoint is
/// rate-limited to 10/5min/IP) via a persistent cookie jar, then exercises the
/// E3 providers directly against real Jellyfin data. Not part of
/// `flutter test`; an unreachable backend fails rather than skips.
void main() {
  // logout() clears the persisted server config, which reads SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3005');

  test('library_provider loads real home/browse/search/detail data', () async {
    await requireBackend(base);

    final dir = await Directory.systemTemp.createTemp('wp_library_test_');
    addTearDown(() => dir.delete(recursive: true));
    final api = await DioApiClient.persistent('${dir.path}/cookies', baseUrl: base);

    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    // Single login for the whole test — every provider below reuses this
    // client's persisted session cookie.
    await container.read(authProvider.notifier).login('root', 'root');
    expect(container.read(authProvider).isAuthenticated, isTrue);

    // homeProvider → GET /api/library/home
    final home = await container.read(homeProvider.future);
    expect(home.views, isA<List>());

    // browseItemsProvider (default: no query/filter) → full library
    final browsed = await container.read(browseItemsProvider.future);
    expect(browsed, isNotEmpty);
    final first = browsed.first;
    expect(first.id, isNotEmpty);
    expect(first.name, isNotEmpty);

    // itemDetailProvider → GET /api/library/item/:id
    final detail = await container.read(itemDetailProvider(first.id).future);
    expect(detail.id, first.id);

    // browseItemsProvider with a search query → GET-backed search filter
    container.read(browseQueryProvider.notifier).state = first.name;
    final searched = await container.read(browseItemsProvider.future);
    expect(searched.any((i) => i.id == first.id), isTrue);

    // Type filter narrows the result set to the item's own type.
    container.read(browseQueryProvider.notifier).state = '';
    final filterValue = first.type == 'Series' ? BrowseTypeFilter.series : BrowseTypeFilter.movie;
    container.read(browseTypeFilterProvider.notifier).state = filterValue;
    final filtered = await container.read(browseItemsProvider.future);
    expect(filtered, isNotEmpty);
    expect(filtered.every((i) => i.type == first.type), isTrue);

    await container.read(authProvider.notifier).logout();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
