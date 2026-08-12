import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/range_cache_store.dart';

void main() {
  late Directory tmp;
  late RangeCacheStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp-cache-clear');
    store = RangeCacheStore(overrideDir: tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> seed(String itemId) async {
    final entry = await store.open(itemId);
    entry.setTotalLength(64);
    await entry.write(0, List<int>.filled(64, 7));
    await entry.flushMetadata();
    await entry.close();
  }

  test('clear drops streamed titles and keeps the downloaded one', () async {
    await seed('streamed-a');
    await seed('streamed-b');
    await seed('downloaded');

    expect((await store.allItemIds())..sort(), hasLength(3));

    final removed = await store.clear(protected: {'downloaded'});

    expect(removed, 2);
    expect(await store.allItemIds(), ['downloaded']);
  });

  test('clear with nothing protected empties it', () async {
    await seed('one');
    await seed('two');
    expect(await store.clear(), 2);
    expect(await store.allItemIds(), isEmpty);
  });

  test('clearing an empty cache is not an error', () async {
    expect(await store.clear(protected: {'nothing-here'}), 0);
  });
}
