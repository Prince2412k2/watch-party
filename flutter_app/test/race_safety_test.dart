import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/cache_fill_controller.dart';
import 'package:watchparty/cache/catalog_cache_store.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/catalog_repository.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/download/offline_manifest_store.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/state/chat_provider.dart';
import 'package:watchparty/state/downloads_provider.dart';
import 'package:watchparty/state/offline_provider.dart';
import 'package:watchparty/state/servarr_provider.dart';

// Deterministic coverage for the data/offline/polling/download races (audit
// #64). Every test here drives the real production class and forces the
// interleaving explicitly — a gated manifest load, an ack that never arrives, a
// fetch held open by a Completer — rather than relying on timing luck.

/// Returns the fixed item list for `items()` — enough for [CatalogRepository]
/// to have something fresh to emit.
class _ItemsApi extends MockApiClient {
  _ItemsApi(this.result);

  final List<LibraryItem> result;

  @override
  Future<List<LibraryItem>> items({String? parentId}) async => result;
}

/// Reads like a normal cache, but every write fails (full disk, unwritable
/// support dir, …).
class _UnwritableCatalogCache extends CatalogCacheStore {
  _UnwritableCatalogCache(super.directory);

  @override
  Future<void> write(String namespace, String key, dynamic body) async {
    throw StateError('cache write failed');
  }
}

/// Holds [load] open until the test releases [gate], so a mutation can be made
/// to land in the middle of a rehydrate scan.
class _GatedManifestStore extends OfflineManifestStore {
  _GatedManifestStore({required this.gate, super.overrideDir});

  final Future<void> gate;

  @override
  Future<List<OfflineRecord>> load() async {
    await gate;
    return super.load();
  }
}

/// Every fill fails on the way in (before the fill loop, so no [FillProgress]
/// ever reports the failure).
class _FailingFillController extends CacheFillController {
  _FailingFillController({required super.proxy});

  @override
  Future<void> start(String itemId, {RangeFetcher? fetcher}) async {
    throw StateError('could not open the cache entry');
  }

  @override
  Future<void> resume(String itemId, {RangeFetcher? fetcher}) async {
    throw StateError('could not open the cache entry');
  }
}

/// Accepts the emit and then never acks.
class _SilentSocketClient extends MockSocketClient {
  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) {
    emitted.add((event, data));
    return Completer<dynamic>().future;
  }
}

/// The emit itself fails (socket dropped between composing and sending).
class _DeadSocketClient extends MockSocketClient {
  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) =>
      Future<dynamic>.error(StateError('socket not connected'));
}

/// Always reports the server-side rate limit.
class _RateLimitingSocketClient extends MockSocketClient {
  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) async {
    emitted.add((event, data));
    return {'error': 'rate limited'};
  }
}

OfflineRecord _record(String itemId) =>
    OfflineRecord(itemId: itemId, title: itemId, filePath: '', downloadedAt: 0);

void main() {
  group('catalog refresh vs. cache persistence', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('catalog_race_');
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('a failed cache write does not swallow the network result', () async {
      const fresh = LibraryItem(id: 'fresh', name: 'Fresh', type: 'Movie');
      final repository = CatalogRepository(
        api: _ItemsApi(const [fresh]),
        cache: _UnwritableCatalogCache(dir),
      );

      final emissions = await repository.items('server|user').toList();

      expect(emissions.map((items) => items.single.id), ['fresh']);
    });

    test(
      'a failed cache write still emits fresh data over cached data',
      () async {
        const namespace = 'server|user';
        const cached = LibraryItem(id: 'cached', name: 'Cached', type: 'Movie');
        const fresh = LibraryItem(id: 'fresh', name: 'Fresh', type: 'Movie');
        await CatalogCacheStore(
          dir,
        ).write(namespace, 'items:', [cached.toJson()]);

        final repository = CatalogRepository(
          api: _ItemsApi(const [fresh]),
          cache: _UnwritableCatalogCache(dir),
        );

        final emissions = await repository.items(namespace).toList();

        expect(emissions.map((items) => items.single.id), ['cached', 'fresh']);
      },
    );
  });

  group('offline rehydrate vs. concurrent mutations', () {
    late Directory cacheDir;
    late Directory manifestDir;
    late MediaCacheProxy proxy;

    setUp(() {
      cacheDir = Directory.systemTemp.createTempSync('offline_race_cache_');
      manifestDir = Directory.systemTemp.createTempSync('offline_race_meta_');
      proxy = MediaCacheProxy(
        apiClient: MockApiClient(),
        store: RangeCacheStore(overrideDir: cacheDir),
      );
    });

    tearDown(() async {
      // Let any fire-and-forget scan/persist settle before the dirs go away.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        cacheDir.deleteSync(recursive: true);
      } catch (_) {}
      try {
        manifestDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // Makes itemId's cache entry fully present, so the rehydrate scan finds it
    // as an offline title.
    Future<void> completeEntry(String itemId) async {
      final entry = await proxy.openEntry(itemId);
      entry.setTotalLength(8);
      await entry.write(0, List<int>.filled(8, 1));
      await entry.flushMetadata();
    }

    test('markComplete during a rehydrate scan survives the scan', () async {
      await completeEntry('scanned');
      final gate = Completer<void>();
      final notifier = OfflineNotifier(
        proxy,
        manifestStore: _GatedManifestStore(
          gate: gate.future,
          overrideDir: manifestDir,
        ),
      );
      addTearDown(notifier.dispose);

      // Queued while the scan is still blocked on its manifest load.
      final marked = notifier.markComplete(itemId: 'marked', title: 'Marked');
      gate.complete();
      await marked;

      expect(
        notifier.state.map((r) => r.itemId),
        containsAll(<String>['scanned', 'marked']),
      );
      // And the sidecar reflects both, not just whichever write landed last.
      final persisted = await OfflineManifestStore(
        overrideDir: manifestDir,
      ).load();
      expect(
        persisted.map((r) => r.itemId),
        containsAll(<String>['scanned', 'marked']),
      );
    });

    test(
      'a synchronous upsert during a rehydrate scan is merged, not lost',
      () async {
        await completeEntry('scanned');
        final gate = Completer<void>();
        final notifier = OfflineNotifier(
          proxy,
          manifestStore: _GatedManifestStore(
            gate: gate.future,
            overrideDir: manifestDir,
          ),
        );
        addTearDown(notifier.dispose);

        notifier.upsert(_record('live'));
        gate.complete();

        final ids = await _waitFor(
          () => notifier.state.map((r) => r.itemId).toList(),
          (current) => current.contains('scanned'),
        );
        expect(ids, containsAll(<String>['scanned', 'live']));
      },
    );

    test('remove during a rehydrate scan is not resurrected by it', () async {
      await completeEntry('gone');
      final gate = Completer<void>();
      final notifier = OfflineNotifier(
        proxy,
        manifestStore: _GatedManifestStore(
          gate: gate.future,
          overrideDir: manifestDir,
        ),
      );
      addTearDown(notifier.dispose);

      final removed = notifier.remove('gone');
      gate.complete();
      await removed;

      expect(notifier.state, isEmpty);
      expect(await proxy.isComplete('gone'), isFalse);
    });
  });

  group('offline manifest writes', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('manifest_race_');
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'overlapping saves are serialized and leave a parseable manifest',
      () async {
        final store = OfflineManifestStore(overrideDir: dir);

        // 20 saves fired without awaiting: interleaved `writeAsString` calls used
        // to produce a truncated/mixed file, which `load()` reports as empty.
        await Future.wait<void>([
          for (var n = 1; n <= 20; n++)
            store.save([for (var i = 0; i < n; i++) _record('item-$i')]),
        ]);

        final loaded = await OfflineManifestStore(overrideDir: dir).load();
        expect(
          loaded,
          hasLength(20),
          reason: 'the last queued save is on disk',
        );
        expect(
          File('${dir.path}/offline_manifest.json.tmp').existsSync(),
          isFalse,
          reason: 'the atomic write renames its temp file away',
        );
      },
    );
  });

  group('PollSequencer', () {
    test('drops a tick that would overlap an in-flight one', () async {
      final sequencer = PollSequencer();
      final gate = Completer<String>();
      var requests = 0;
      final applied = <String>[];

      final first = sequencer.poll<String>(
        request: () {
          requests++;
          return gate.future;
        },
        onData: applied.add,
        onError: () => applied.add('error'),
      );
      await sequencer.poll<String>(
        request: () async {
          requests++;
          return 'second';
        },
        onData: applied.add,
        onError: () => applied.add('error'),
      );

      expect(requests, 1, reason: 'the overlapping tick never left the ground');
      expect(applied, isEmpty);

      gate.complete('first');
      await first;

      expect(applied, ['first']);
      expect(sequencer.isInFlight, isFalse);
    });

    test('drops a response that resolves after stop()', () async {
      final sequencer = PollSequencer();
      final gate = Completer<String>();
      final applied = <String>[];

      final pending = sequencer.poll<String>(
        request: () => gate.future,
        onData: applied.add,
        onError: () => applied.add('error'),
      );

      sequencer.stop();
      gate.complete('too late');
      await pending;

      expect(applied, isEmpty);
      expect(sequencer.isStopped, isTrue);
    });

    test('drops a failure that resolves after stop()', () async {
      final sequencer = PollSequencer();
      final gate = Completer<String>();
      final applied = <String>[];

      final pending = sequencer.poll<String>(
        request: () => gate.future,
        onData: applied.add,
        onError: () => applied.add('error'),
      );

      sequencer.stop();
      gate.completeError(StateError('offline'));
      await pending;

      expect(applied, isEmpty);
    });

    test(
      'a failed tick reports onError and does not block the next tick',
      () async {
        final sequencer = PollSequencer();
        final applied = <String>[];

        await sequencer.poll<String>(
          request: () async => throw StateError('offline'),
          onData: applied.add,
          onError: () => applied.add('error'),
        );
        await sequencer.poll<String>(
          request: () async => 'recovered',
          onData: applied.add,
          onError: () => applied.add('error'),
        );

        expect(applied, ['error', 'recovered']);
      },
    );

    test(
      'a payload that fails to parse is reported as a failed tick',
      () async {
        final sequencer = PollSequencer();
        final applied = <String>[];

        await sequencer.poll<String>(
          request: () async => 'raw',
          onData: (_) => throw StateError('malformed'),
          onError: () => applied.add('error'),
        );

        expect(applied, ['error']);
      },
    );
  });

  group('chat acknowledgements', () {
    test('an ack that never arrives times out instead of hanging', () async {
      final notifier = ChatNotifier(
        _SilentSocketClient(),
        ackTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(notifier.dispose);

      final error = await notifier.send('hello');

      expect(error, isNotNull);
      expect(error, contains('No reply'));
    });

    test('a failed emit is reported, not thrown', () async {
      final notifier = ChatNotifier(_DeadSocketClient());
      addTearDown(notifier.dispose);

      final error = await notifier.send('hello');

      expect(error, contains('Could not send'));
    });

    test(
      'a server rate-limit ack blocks further sends until the window drains',
      () async {
        final socket = _RateLimitingSocketClient();
        final notifier = ChatNotifier(socket);
        addTearDown(notifier.dispose);

        final error = await notifier.send('hi');

        expect(error, contains('Rate limited'));
        expect(notifier.isRateLimited, isTrue);

        // The next send is refused locally — no further hammering of a server
        // that is already saying no.
        expect(await notifier.send('hi again'), contains('Rate limited'));
        expect(socket.emitted, hasLength(1));
      },
    );
  });

  group('cache fills', () {
    late Directory cacheDir;
    late Directory manifestDir;
    late MediaCacheProxy proxy;
    late OfflineNotifier offlineNotifier;

    setUp(() async {
      cacheDir = Directory.systemTemp.createTempSync('fill_race_cache_');
      manifestDir = Directory.systemTemp.createTempSync('fill_race_meta_');
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
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        cacheDir.deleteSync(recursive: true);
      } catch (_) {}
      try {
        manifestDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'a fill that fails on startup becomes a visible failed record',
      () async {
        final notifier = DownloadsNotifier(
          _FailingFillController(proxy: proxy),
          offlineNotifier,
        );
        addTearDown(notifier.dispose);

        await notifier.start(itemId: 'boom', title: 'Boom');

        final record = await _waitFor(
          () => notifier.state.firstWhere((r) => r.itemId == 'boom'),
          (current) => current.status == DownloadStatus.failed,
        );
        expect(record.title, 'Boom');
      },
    );

    test('a resume that fails on startup is reported, not thrown', () async {
      final notifier = DownloadsNotifier(
        _FailingFillController(proxy: proxy),
        offlineNotifier,
      );
      addTearDown(notifier.dispose);

      await notifier.resume('boom');

      final record = await _waitFor(
        () => notifier.state.firstWhere((r) => r.itemId == 'boom'),
        (current) => current.status == DownloadStatus.failed,
      );
      expect(record.itemId, 'boom');
    });

    test('pauseAll pauses the fills that are actually running', () async {
      const itemId = 'title-pause-all';
      final entry = await proxy.openEntry(itemId);
      entry.setTotalLength(50);

      final released = Completer<void>();
      final controller = CacheFillController(proxy: proxy, chunkSize: 10);
      unawaited(
        controller.start(
          itemId,
          fetcher: (entry, start, end) async {
            await released.future;
            await entry.write(start, List<int>.filled(end - start, 1));
          },
        ),
      );

      await _waitFor(
        () => controller.progressFor(itemId).value.state,
        (state) => state == FillState.running,
      );

      expect(controller.pauseAll(), 1);

      released.complete();
      await _waitFor(
        () => controller.progressFor(itemId).value.state,
        (state) => state == FillState.paused,
      );
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
