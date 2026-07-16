// Phase 3b-wiring retired `background_downloader` from the download/offline
// path entirely — downloads now fill the same on-device [RangeCacheStore]
// playback already streams through (see `CacheFillController`,
// `DownloadsNotifier`, `OfflineNotifier`). There is no more native
// platform-channel task DB to resume from, so this no longer needs to run
// outside the headless `flutter_tester` VM (the reason it lived under
// `integration_test/` in the first place) — it stays here only so the
// restart-survives-and-resumes property it used to check for
// `background_downloader` keeps being checked for its replacement.
//
// "Restart" here means: throw away every in-memory object (the
// [RangeCacheStore], its [CacheEntry]s, the [CacheFillController]) and
// rebuild them fresh pointed at the same on-disk directory — exactly what
// happens across a real app relaunch, since the cache's on-disk sidecar
// (`.meta.json`) is the only thing that survives a process death.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/cache_fill_controller.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/mock_api_client.dart';

void main() {
  test(
      'a fill paused mid-flight resumes from a fresh (simulated-restart) '
      'controller and lands on a fully cached, re-openable entry', () async {
    final cacheDir = Directory.systemTemp.createTempSync('downloader_restart_');
    addTearDown(() => cacheDir.deleteSync(recursive: true));
    const itemId = 'restart-title';
    const total = 100;
    const chunkSize = 10;

    var fetchCount = 0;
    final pausingFetcher = (entry, start, end) async {
      fetchCount++;
      await entry.write(start, List<int>.filled(end - start, 7));
      // Mirrors `MediaCacheProxy.fetchAndStore`, which the real fill loop
      // uses by default — it persists the sidecar after every chunk, which
      // is exactly what makes bytes already on disk recoverable across a
      // real process restart.
      await entry.flushMetadata();
      if (fetchCount == 3) throw StateError('simulated crash mid-fill');
    };

    // "Before restart": start filling, hit a simulated crash partway through.
    var store = RangeCacheStore(overrideDir: cacheDir);
    var proxy = MediaCacheProxy(apiClient: MockApiClient(), store: store);
    var controller = CacheFillController(proxy: proxy, chunkSize: chunkSize);

    final entry = await proxy.openEntry(itemId);
    entry.setTotalLength(total);
    await controller.start(itemId, fetcher: pausingFetcher);

    expect(controller.progressFor(itemId).value.state, FillState.error);
    final cachedBeforeRestart = controller.progressFor(itemId).value.cachedBytes;
    expect(cachedBeforeRestart, greaterThan(0));
    expect(cachedBeforeRestart, lessThan(total));
    await entry.close();

    // "Restart": brand new store/proxy/controller instances, same directory —
    // nothing in memory survives, only the on-disk `.meta.json` + data file.
    store = RangeCacheStore(overrideDir: cacheDir);
    proxy = MediaCacheProxy(apiClient: MockApiClient(), store: store);
    controller = CacheFillController(proxy: proxy, chunkSize: chunkSize);

    // The fresh entry rehydrates the previously-cached bytes from disk...
    expect(await proxy.isComplete(itemId), isFalse);
    final reopened = await proxy.openEntry(itemId);
    expect(reopened.hasRange(0, cachedBeforeRestart), isTrue);

    // ...and resuming (a fresh controller has never seen this itemId, so this
    // is a `start`, exactly like `DownloadsNotifier.resume` calling
    // `CacheFillController.resume` on an unknown id falls back to `start`)
    // only re-fetches what's still missing, and finishes the fill.
    await controller.resume(
      itemId,
      fetcher: (entry, start, end) async {
        await entry.write(start, List<int>.filled(end - start, 7));
        await entry.flushMetadata();
      },
    );

    expect(controller.progressFor(itemId).value.state, FillState.complete);
    expect(await proxy.isComplete(itemId), isTrue);
    expect(reopened.missingRanges(0, total), isEmpty);
  });
}
