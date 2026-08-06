import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/catalog_cache_store.dart';
import 'package:watchparty/data/catalog_prefetcher.dart';
import 'package:watchparty/data/catalog_repository.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';

/// Records what the catalog was asked for, and can be stalled so a test can
/// look at the queue while a warm is still outstanding.
class _RecordingApi extends MockApiClient {
  final List<String> calls = [];
  Completer<void>? gate;
  bool fail = false;

  Future<void> _hold(String call) async {
    calls.add(call);
    await gate?.future;
    if (fail) throw StateError('catalog unavailable');
  }

  @override
  Future<LibraryItem> item(String id) async {
    await _hold('item:$id');
    return LibraryItem(id: id, name: 'Title $id', type: 'Movie');
  }

  @override
  Future<List<LibraryItem>> items({String? parentId}) async {
    await _hold('items');
    return const [LibraryItem(id: 'a', name: 'A', type: 'Movie')];
  }
}

typedef _Fixture = ({
  _RecordingApi api,
  CatalogRepository repository,
  CatalogPrefetcher prefetcher,
});

void main() {
  const namespace = 'server|user';

  Future<_Fixture> fixture() async {
    final directory = await Directory.systemTemp.createTemp('catalog-warm-');
    addTearDown(() => directory.delete(recursive: true));
    final api = _RecordingApi();
    final repository = CatalogRepository(
      api: api,
      cache: CatalogCacheStore(directory),
    );
    final prefetcher = CatalogPrefetcher(repository);
    addTearDown(prefetcher.dispose);
    return (api: api, repository: repository, prefetcher: prefetcher);
  }

  test('a warmed title opens without waiting on the network', () async {
    final f = await fixture();
    f.prefetcher.warmItem(namespace, 'x');
    await f.prefetcher.settle();
    expect(f.api.calls, ['item:x'], reason: 'the warm cost one request');

    // Nothing is answered from here on. The detail surface must still have
    // something to paint, which is the whole point of having warmed it.
    f.api.gate = Completer<void>();
    expect(
      (await f.repository.item(namespace, 'x').first).name,
      'Title x',
      reason: 'the first emission came off disk, not the wire',
    );
  });

  test('a rail run leaves one warm in flight, not one per title', () async {
    final f = await fixture();
    f.api.gate = Completer<void>();

    for (var i = 0; i < 50; i++) {
      f.prefetcher.warmItem(namespace, 'title-$i');
    }

    expect(f.prefetcher.inFlight, 1, reason: 'the concurrency cap holds');
    expect(
      f.prefetcher.pending,
      lessThanOrEqualTo(1),
      reason: 'the focus slot is replaced, not appended to',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(f.api.calls, ['item:title-0']);

    f.api.gate!.complete();
    // Drain before teardown pulls the cache directory out from under a write.
    await f.prefetcher.settle();
  });

  test('the browse catalog is warmed once, however often it is asked', () async {
    final f = await fixture();
    f.prefetcher.warmBrowse(namespace);
    f.prefetcher.warmBrowse(namespace);
    await f.prefetcher.settle();
    f.prefetcher.warmBrowse(namespace);
    await f.prefetcher.settle();

    expect(f.api.calls, ['items']);
  });

  test('nothing is warmed for a signed-out user', () async {
    final f = await fixture();
    // A null namespace is what tells CatalogRepository not to persist, so a
    // warm would spend a request and keep nothing.
    f.prefetcher.warmBrowse(null);
    f.prefetcher.warmItem(null, 'x');
    f.prefetcher.warmItem(namespace, '');
    await f.prefetcher.settle();

    expect(f.api.calls, isEmpty);
  });

  test('a failing warm is a non-event', () async {
    final f = await fixture();
    f.api.fail = true;
    f.prefetcher.warmItem(namespace, 'x');
    // No unhandled error escapes, and the queue drains rather than wedging.
    await f.prefetcher.settle();
    expect(f.prefetcher.inFlight, 0);
    expect(f.prefetcher.pending, 0);
  });
}
