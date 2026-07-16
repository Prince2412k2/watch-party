import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/cache_fill_controller.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/mock_api_client.dart';

/// A fake [RangeFetcher] that never touches the network — it just writes
/// synthetic bytes into the entry for the requested range, so the fill
/// loop's control flow (chunking, pause/resume/cancel, progress) is fully
/// exercised without any I/O beyond the temp-dir cache file itself.
RangeFetcher fakeFetcher({List<(int, int)>? calls}) {
  return (entry, start, end) async {
    calls?.add((start, end));
    await entry.write(start, List<int>.filled(end - start, 1));
  };
}

void main() {
  late Directory tmpDir;
  late RangeCacheStore store;
  late MediaCacheProxy proxy;
  late CacheFillController controller;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('cache_fill_test_');
    store = RangeCacheStore(overrideDir: tmpDir);
    proxy = MediaCacheProxy(apiClient: MockApiClient(), store: store);
    controller = CacheFillController(proxy: proxy, chunkSize: 10);
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('filling an empty entry of known total reaches 100%', () async {
    final entry = await store.open('item-empty');
    entry.setTotalLength(35);

    await controller.start('item-empty', fetcher: fakeFetcher());

    final progress = controller.progressFor('item-empty').value;
    expect(progress.state, FillState.complete);
    expect(progress.cachedBytes, 35);
    expect(progress.totalBytes, 35);
    expect(entry.missingRanges(0, 35), isEmpty);
  });

  test('a middle gap only fetches the gap', () async {
    final entry = await store.open('item-gap');
    entry.setTotalLength(100);
    await entry.write(0, List<int>.filled(20, 9));
    await entry.write(50, List<int>.filled(50, 9));
    // Present: [0,20) and [50,100). Missing: [20,50).

    final calls = <(int, int)>[];
    await controller.start('item-gap', fetcher: fakeFetcher(calls: calls));

    expect(entry.missingRanges(0, 100), isEmpty);
    // Every fetched range must lie within the original gap.
    for (final call in calls) {
      expect(call.$1, greaterThanOrEqualTo(20));
      expect(call.$2, lessThanOrEqualTo(50));
    }
    expect(calls, isNotEmpty);
    expect(controller.progressFor('item-gap').value.state, FillState.complete);
  });

  test('pause mid-fill stops progress and resume completes it', () async {
    final entry = await store.open('item-pause');
    entry.setTotalLength(50);

    var fetchCount = 0;
    final pausingFetcher = (entry, start, end) async {
      fetchCount++;
      await entry.write(start, List<int>.filled(end - start, 1));
      if (fetchCount == 2) controller.pause('item-pause');
    };

    await controller.start('item-pause', fetcher: pausingFetcher);

    final pausedProgress = controller.progressFor('item-pause').value;
    expect(pausedProgress.state, FillState.paused);
    final pausedBytes = pausedProgress.cachedBytes;
    expect(pausedBytes, lessThan(50));
    expect(pausedBytes, greaterThan(0));

    await controller.resume('item-pause', fetcher: fakeFetcher());

    final finalProgress = controller.progressFor('item-pause').value;
    expect(finalProgress.state, FillState.complete);
    expect(finalProgress.cachedBytes, 50);
    expect(entry.missingRanges(0, 50), isEmpty);
  });

  test('cancel leaves partial bytes and marks cancelled', () async {
    final entry = await store.open('item-cancel');
    entry.setTotalLength(50);

    var fetchCount = 0;
    final cancellingFetcher = (entry, start, end) async {
      fetchCount++;
      await entry.write(start, List<int>.filled(end - start, 1));
      if (fetchCount == 2) controller.cancel('item-cancel');
    };

    await controller.start('item-cancel', fetcher: cancellingFetcher);

    final progress = controller.progressFor('item-cancel').value;
    expect(progress.state, FillState.cancelled);
    expect(progress.cachedBytes, greaterThan(0));
    expect(progress.cachedBytes, lessThan(50));
    // Already-cached bytes stay in place.
    expect(entry.hasRange(0, progress.cachedBytes), isTrue);
  });

  test('progress ValueListenable emits increasing cachedBytes', () async {
    final entry = await store.open('item-progress');
    entry.setTotalLength(30);

    final seen = <int>[];
    controller.progressFor('item-progress').addListener(() {
      seen.add(controller.progressFor('item-progress').value.cachedBytes);
    });

    await controller.start('item-progress', fetcher: fakeFetcher());

    expect(seen, isNotEmpty);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    expect(seen.last, 30);
  });
}
