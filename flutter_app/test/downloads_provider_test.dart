import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/cache_fill_controller.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/api_client.dart';
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
  _reconcileTests();
  _retryTests();

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

/// An ApiClient whose `item()` answers however the test needs it to: a 404 for
/// titles that are gone, a network failure for titles it cannot reach, and a
/// normal answer otherwise.
class _LibraryApi extends MockApiClient {
  _LibraryApi({this.gone = const {}, this.unreachable = const {}});

  final Set<String> gone;
  final Set<String> unreachable;

  @override
  Future<LibraryItem> item(String id) async {
    if (gone.contains(id)) throw ApiException('item', 404, 'Not Found');
    if (unreachable.contains(id)) throw const SocketException('offline');
    return super.item(id);
  }
}

void _reconcileTests() {
  group('reconcileWithLibrary', () {
    late Directory cacheDir;
    late Directory manifestDir;
    late MediaCacheProxy proxy;
    late OfflineNotifier offline;

    setUp(() async {
      cacheDir = Directory.systemTemp.createTempSync('reconcile_cache_');
      manifestDir = Directory.systemTemp.createTempSync('reconcile_manifest_');
      proxy = MediaCacheProxy(
        apiClient: MockApiClient(),
        store: RangeCacheStore(overrideDir: cacheDir),
      );
      offline = OfflineNotifier(
        proxy,
        manifestStore: OfflineManifestStore(overrideDir: manifestDir),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final id in ['kept', 'deleted', 'unreachable']) {
        await offline.markComplete(itemId: id, title: id);
      }
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      try {
        cacheDir.deleteSync(recursive: true);
      } catch (_) {}
      try {
        manifestDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('a title deleted from the library is dropped from the device',
        () async {
      await offline.reconcileWithLibrary(_LibraryApi(gone: {'deleted'}));
      expect(offline.state.map((r) => r.itemId), isNot(contains('deleted')));
    });

    test('a title that is still there is left alone', () async {
      await offline.reconcileWithLibrary(_LibraryApi(gone: {'deleted'}));
      expect(offline.state.map((r) => r.itemId), contains('kept'));
    });

    test('a server we cannot reach never costs anyone a download', () async {
      // THE failure mode worth guarding. Reconciling against a listing would
      // delete everything the first time a request came back empty or failed;
      // an unreachable server must change nothing at all.
      await offline.reconcileWithLibrary(
        _LibraryApi(unreachable: {'kept', 'deleted', 'unreachable'}),
      );
      expect(offline.state.length, 3);
    });

    test('a 500 is not an answer either', () async {
      await offline.reconcileWithLibrary(_ServerErrorApi());
      expect(offline.state.length, 3);
    });
  });
}

/// Everything 500s — a broken server, not a deleted library.
class _ServerErrorApi extends MockApiClient {
  @override
  Future<LibraryItem> item(String id) async =>
      throw ApiException('item', 500, 'Internal Server Error');
}

/// A fill controller whose fetches fail a set number of times before working,
/// counting attempts so a test can see the retries happen.
class _FlakyFillController extends CacheFillController {
  _FlakyFillController({
    required super.proxy,
    super.chunkSize,
    required this.failuresBeforeSuccess,
  });

  final int failuresBeforeSuccess;
  int attempts = 0;

  RangeFetcher get _fetcher => (entry, start, end) async {
        attempts++;
        if (attempts <= failuresBeforeSuccess) {
          throw const SocketException('the link dropped');
        }
        await entry.write(start, List<int>.filled(end - start, 1));
      };

  @override
  Future<void> start(String itemId, {RangeFetcher? fetcher}) =>
      super.start(itemId, fetcher: fetcher ?? _fetcher);

  @override
  Future<void> resume(String itemId, {RangeFetcher? fetcher}) =>
      super.resume(itemId, fetcher: fetcher ?? _fetcher);
}

void _retryTests() {
  group('automatic retry', () {
    test('the backoff grows and then stops growing', () {
      // 2s, 4s, 8s, 16s, 32s — and never more, so a long-dead server is
      // retried on a fixed slow beat rather than at ever-widening intervals.
      expect(DownloadsNotifier.retryDelay(0), const Duration(seconds: 2));
      expect(DownloadsNotifier.retryDelay(1), const Duration(seconds: 4));
      expect(DownloadsNotifier.retryDelay(4), const Duration(seconds: 32));
      expect(DownloadsNotifier.retryDelay(9), const Duration(seconds: 32));
    });

    test('it gives up rather than retrying forever', () {
      // A bound matters: past it the failure is not a blip, and retrying
      // silently forever would hide a real problem behind a spinner.
      expect(DownloadsNotifier.maxAutoRetries, 5);
    });

    test('a dropped link recovers with nobody pressing anything', () async {
      // The whole point: nobody presses anything. The backoff is injected so
      // this does not spend two wall-clock seconds — with the real one it
      // passed alone and failed under load, which is worse than no test.
      final cacheDir = Directory.systemTemp.createTempSync('retry_cache_');
      final manifestDir = Directory.systemTemp.createTempSync('retry_man_');
      addTearDown(() async {
        // Let the fire-and-forget completion work (markComplete's manifest
        // persist) land before the temp dirs go, exactly as the other groups
        // here do. Without it the save races the delete and throws
        // PathNotFoundException out of a future nobody is awaiting — which
        // fails whichever test happens to be running when it surfaces.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          cacheDir.deleteSync(recursive: true);
        } catch (_) {}
        try {
          manifestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final proxy = MediaCacheProxy(
        apiClient: MockApiClient(),
        store: RangeCacheStore(overrideDir: cacheDir),
      );
      final offline = OfflineNotifier(
        proxy,
        manifestStore: OfflineManifestStore(overrideDir: manifestDir),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const itemId = 'flaky-1';
      final entry = await proxy.openEntry(itemId);
      entry.setTotalLength(20);

      final controller = _FlakyFillController(
        proxy: proxy,
        chunkSize: 10,
        failuresBeforeSuccess: 1,
      );
      final downloads = DownloadsNotifier(
        controller,
        offline,
        backoff: (_) => const Duration(milliseconds: 20),
      );
      addTearDown(downloads.dispose);

      await downloads.start(itemId: itemId, title: 'Flaky');

      // First attempt fails; the retry lands after the 2s backoff and finishes.
      await _waitFor(
        () => offline.state.any((r) => r.itemId == itemId),
        (done) => done,
        timeout: const Duration(seconds: 5),
      );

      // More fetches than chunks: the first one threw and something tried
      // again. `attemptsFor` is deliberately NOT asserted here — a finished
      // download is removed from tracking, which clears its retry budget with
      // it, so by the time this line runs the counter is legitimately zero.
      expect(controller.attempts, greaterThan(2));
      expect(await proxy.isComplete(itemId), isTrue);
    });
  });
}
