import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/download/offline_manifest_store.dart';
import 'package:watchparty/state/offline_provider.dart';
import 'package:watchparty/state/providers.dart';

/// Phase 3b-wiring verification: a title is "offline" purely because its
/// on-device cache entry is fully present — no separate downloaded file, no
/// `background_downloader`. Wired through real [ProviderContainer] overrides
/// so this exercises the actual `offlineProvider`/`resolveOfflinePlayback`
/// wiring, against a real (temp-dir) [RangeCacheStore] and a [MockApiClient]
/// that's never actually hit (every entry below has its total length/bytes
/// set directly, so nothing here needs the network).
void main() {
  late Directory cacheDir;
  late Directory manifestDir;
  late MediaCacheProxy proxy;
  late ProviderContainer container;

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('offline_test_cache_');
    manifestDir = Directory.systemTemp.createTempSync('offline_test_manifest_');
    proxy = MediaCacheProxy(
      apiClient: MockApiClient(),
      store: RangeCacheStore(overrideDir: cacheDir),
    );
    container = ProviderContainer(overrides: [
      mediaCacheProxyProvider.overrideWithValue(proxy),
      offlineProvider.overrideWith(
        (ref) => OfflineNotifier(
          ref.watch(mediaCacheProxyProvider),
          manifestStore: OfflineManifestStore(overrideDir: manifestDir),
        ),
      ),
    ]);
    addTearDown(container.dispose);
  });

  tearDown(() async {
    // Let fire-and-forget rehydrate/scan work settle before deleting the temp
    // dirs out from under it.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      cacheDir.deleteSync(recursive: true);
    } catch (_) {}
    try {
      manifestDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a fully-cached title surfaces in offlineProvider on rehydrate', () async {
    const itemId = 'title-42';
    final entry = await proxy.openEntry(itemId);
    entry.setTotalLength(1024);
    await entry.write(0, List<int>.filled(1024, 1));
    await entry.flushMetadata();
    await proxy.touch(itemId); // OfflineNotifier itself never opens the entry.

    final state = await _waitFor(
      () => container.read(offlineProvider),
      (records) => records.any((r) => r.itemId == itemId),
    );

    final record = state.firstWhere((r) => r.itemId == itemId);
    expect(record.itemId, itemId);
  });

  test('markComplete flips offlineProvider live, with the metadata the guest '
      'detail path reads', () async {
    const itemId = 'title-99';
    final entry = await proxy.openEntry(itemId);
    entry.setTotalLength(10);
    await entry.write(0, List<int>.filled(10, 1));
    await entry.flushMetadata();

    // Let the initial rehydrate settle. title-99 is fully cached, so it may
    // already surface from rehydrate (a complete cache entry IS offline-
    // available by design) — the point of this test is that markComplete
    // attaches the guest-detail metadata regardless.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(offlineProvider.notifier).markComplete(
          itemId: itemId,
          title: 'Klute',
          posterTag: 'poster-99',
          runTimeTicks: 90 * 60 * 10000000,
        );

    final state = container.read(offlineProvider);
    final record = state.firstWhere((r) => r.itemId == itemId);
    expect(record.title, 'Klute');
    expect(record.posterTag, 'poster-99');
    expect(record.runTimeTicks, 90 * 60 * 10000000);
  });

  test(
      'resolveOfflinePlayback resolves the cache-proxy URL once offline, '
      'falls back to the network URL otherwise', () async {
    const itemId = 'title-7';
    final entry = await proxy.openEntry(itemId);
    entry.setTotalLength(10);
    await entry.write(0, List<int>.filled(10, 1));
    await entry.flushMetadata();
    await _waitFor(
      () => container.read(offlineProvider),
      (records) => records.any((r) => r.itemId == itemId),
    );

    await proxy.start();
    addTearDown(proxy.dispose);

    final ref = container.read(_refProvider);
    const streamUrl = 'https://example.com/native/file?token=abc';

    final resolved = resolveOfflinePlayback(ref, itemId, streamUrl);
    expect(resolved.offline, isTrue);
    expect(resolved.url, proxy.urlFor(itemId));

    final untouched = resolveOfflinePlayback(ref, 'never-downloaded', streamUrl);
    expect(untouched.offline, isFalse);
    expect(untouched.url, streamUrl);
  });

  test('remove() deletes the cache entry and drops the record', () async {
    const itemId = 'title-remove';
    final entry = await proxy.openEntry(itemId);
    entry.setTotalLength(10);
    await entry.write(0, List<int>.filled(10, 1));
    await entry.flushMetadata();
    await _waitFor(
      () => container.read(offlineProvider),
      (records) => records.any((r) => r.itemId == itemId),
    );

    await container.read(offlineProvider.notifier).remove(itemId);

    expect(container.read(offlineProvider).any((r) => r.itemId == itemId), isFalse);
    expect(await proxy.isComplete(itemId), isFalse);
  });
}

/// Fetches a real [Ref] out of the container — `resolveOfflinePlayback` wants
/// one (it only ever calls `ref.read`), and `ProviderContainer` itself isn't a `Ref`.
final _refProvider = Provider<Ref>((ref) => ref);

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
