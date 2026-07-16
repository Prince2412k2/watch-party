import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/cache_fill_controller.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/download/offline_manifest_store.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/downloads_provider.dart';
import 'package:watchparty/state/offline_provider.dart';

/// A [CacheFillController] that defaults `start`/`resume` to a synthetic,
/// network-free [RangeFetcher] whenever the caller doesn't supply one — real
/// UI call sites (via `DownloadsNotifier.start`/`resume`) never pass a
/// fetcher, so this lets a test drive the exact same call shape end-to-end
/// without touching the network.
class _FakeFillController extends CacheFillController {
  _FakeFillController({required super.proxy, super.chunkSize, this.fetcher});
  final RangeFetcher? fetcher;

  @override
  Future<void> start(String itemId, {RangeFetcher? fetcher}) =>
      super.start(itemId, fetcher: fetcher ?? this.fetcher);

  @override
  Future<void> resume(String itemId, {RangeFetcher? fetcher}) =>
      super.resume(itemId, fetcher: fetcher ?? this.fetcher);
}

RangeFetcher _fakeFetcher() => (entry, start, end) async {
      await entry.write(start, List<int>.filled(end - start, 1));
    };

void main() {
  test('statusForFillState maps every FillState to its DownloadStatus', () {
    expect(statusForFillState(FillState.idle), DownloadStatus.enqueued);
    expect(statusForFillState(FillState.running), DownloadStatus.running);
    expect(statusForFillState(FillState.paused), DownloadStatus.paused);
    expect(statusForFillState(FillState.complete), DownloadStatus.complete);
    expect(statusForFillState(FillState.error), DownloadStatus.failed);
    expect(statusForFillState(FillState.cancelled), DownloadStatus.canceled);
  });

  group('DownloadsNotifier driving a real cache fill', () {
    late Directory cacheDir;
    late Directory manifestDir;
    late MediaCacheProxy proxy;
    late OfflineNotifier offlineNotifier;

    setUp(() async {
      cacheDir = Directory.systemTemp.createTempSync('downloads_provider_cache_');
      manifestDir =
          Directory.systemTemp.createTempSync('downloads_provider_manifest_');
      proxy = MediaCacheProxy(
        apiClient: MockApiClient(),
        store: RangeCacheStore(overrideDir: cacheDir),
      );
      offlineNotifier = OfflineNotifier(
        proxy,
        manifestStore: OfflineManifestStore(overrideDir: manifestDir),
      );
      // Let the (empty) initial rehydrate settle before a test drives a fill.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    tearDown(() async {
      // Let fire-and-forget completion work (markComplete persist, evict scan)
      // settle before deleting the temp dirs out from under it.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        cacheDir.deleteSync(recursive: true);
      } catch (_) {}
      try {
        manifestDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('a completed fill drops the in-flight record and adds an OfflineRecord',
        () async {
      const itemId = 'title-1';
      final entry = await proxy.openEntry(itemId);
      entry.setTotalLength(30); // known total ⇒ no network probe needed

      final downloadsNotifier = DownloadsNotifier(
        _FakeFillController(proxy: proxy, chunkSize: 10, fetcher: _fakeFetcher()),
        offlineNotifier,
      );
      addTearDown(downloadsNotifier.dispose);

      await downloadsNotifier.start(
        itemId: itemId,
        title: 'Arrival',
        posterTag: 'poster-1',
        runTimeTicks: 12345,
      );

      await _waitFor(
        () => downloadsNotifier.state.any((r) => r.itemId == itemId),
        (stillTracked) => !stillTracked,
      );

      final offline = offlineNotifier.state.firstWhere((r) => r.itemId == itemId);
      expect(offline.title, 'Arrival');
      expect(offline.posterTag, 'poster-1');
      expect(offline.runTimeTicks, 12345);
      expect(await proxy.isComplete(itemId), isTrue);
    });

    test('cancel() stops the fill and removes it from state immediately',
        () async {
      const itemId = 'title-2';
      final entry = await proxy.openEntry(itemId);
      entry.setTotalLength(50);

      // Blocks the fetch until the test releases it, so `cancel()` is
      // guaranteed to land while the fill is still in flight. It does NOT
      // write on release, so nothing touches the cache after cancel/teardown.
      final released = Completer<void>();
      final fillController = _FakeFillController(
        proxy: proxy,
        chunkSize: 10,
        fetcher: (entry, start, end) async {
          await released.future;
        },
      );

      final downloadsNotifier = DownloadsNotifier(fillController, offlineNotifier);
      addTearDown(downloadsNotifier.dispose);

      // start() returns after the in-flight record is upserted.
      await downloadsNotifier.start(itemId: itemId, title: 'Heat');
      expect(downloadsNotifier.state.any((r) => r.itemId == itemId), isTrue);

      await downloadsNotifier.cancel(itemId);
      expect(downloadsNotifier.state.any((r) => r.itemId == itemId), isFalse);

      released.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });
}

Future<T> _waitFor<T>(
  T Function() read,
  bool Function(T value) done, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final value = read();
    if (done(value)) return value;
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout (last value: $value)');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
