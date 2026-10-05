import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/cache_fill_controller.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/download/offline_manifest_store.dart';
import 'package:watchparty/state/offline_provider.dart';
import 'package:watchparty/state/downloads_provider.dart';
import 'package:watchparty/models/models.dart';

void main() {
  late Directory dir;
  late RangeCacheStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cache-lifecycle');
    store = RangeCacheStore(overrideDir: dir);
  });
  tearDown(() async {
    await store.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> seed(String id, {bool complete = true}) async {
    final entry = await store.open(id);
    entry.setTotalLength(10);
    await entry.write(0, List.filled(complete ? 10 : 4, 42));
    await entry.flushMetadata();
  }

  test(
    'repeat clear preserves complete and partial explicit downloads',
    () async {
      await seed('watched');
      await seed('download');
      await seed('partial', complete: false);
      await store.markDownload('download', {'title': 'Arrival'});
      await store.markDownload('partial', {
        'title': 'Pilot',
        'seriesName': 'Example Show',
        'seasonNumber': 1,
        'episodeNumber': 1,
      });
      await store.dispose();
      store = RangeCacheStore(overrideDir: dir);
      expect(await store.clear(), 1);
      expect(await store.clear(), 0);
      expect(await store.isComplete('download'), isTrue);
      expect(
        await store.allItemIds(),
        unorderedEquals(['download', 'partial']),
      );
      final meta = await store.metadataFor('partial');
      expect(meta['seriesName'], 'Example Show');
      expect(meta['episodeNumber'], 1);
    },
  );

  test(
    'fully watched cache does not become an explicit offline download',
    () async {
      await seed('watched');
      final proxy = MediaCacheProxy(apiClient: MockApiClient(), store: store);
      final offline = OfflineNotifier(
        proxy,
        manifestStore: OfflineManifestStore(overrideDir: dir),
      );
      // Queue a mutation behind constructor rehydration without making an
      // incomplete title offline.
      await offline.markComplete(itemId: 'absent', title: 'Absent');
      expect(offline.state, isEmpty);
      expect(await proxy.downloadedItemIds(), isEmpty);
      offline.dispose();
    },
  );

  test(
    'download reuses watched ranges and fetches only missing bytes',
    () async {
      await seed('title', complete: false);
      final proxy = MediaCacheProxy(apiClient: MockApiClient(), store: store);
      final fill = CacheFillController(proxy: proxy, chunkSize: 3);
      await fill.markDownload('title', {'title': 'Arrival'});
      expect(
        await proxy.openEntry('title', mediaSourceId: 'title'),
        same(await proxy.openEntry('title')),
      );
      final requests = <(int, int)>[];
      await fill.start(
        'title',
        fetcher: (entry, start, end) async {
          requests.add((start, end));
          await entry.write(start, List.filled(end - start, 42));
          await entry.flushMetadata();
        },
      );
      expect(requests, [(4, 7), (7, 10)]);
      expect(await store.clear(), 0);
      expect(await proxy.downloadedItemIds(), ['title']);
      fill.dispose();
    },
  );

  test(
    'partial download is restored paused and cancel releases retention',
    () async {
      await seed('partial', complete: false);
      await store.markDownload('partial', {'title': 'Arrival'});
      await store.dispose();
      store = RangeCacheStore(overrideDir: dir);
      final proxy = MediaCacheProxy(apiClient: MockApiClient(), store: store);
      final offline = OfflineNotifier(
        proxy,
        manifestStore: OfflineManifestStore(overrideDir: dir),
      );
      final fills = CacheFillController(proxy: proxy);
      final downloads = DownloadsNotifier(fills, offline);
      for (var i = 0; i < 100 && downloads.state.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(downloads.state.single.title, 'Arrival');
      expect(downloads.state.single.status, DownloadStatus.paused);
      expect(downloads.state.single.bytesDownloaded, 4);
      expect(await proxy.clear(), 0);
      await downloads.cancel('partial');
      expect(downloads.state, isEmpty);
      expect(await proxy.clear(), 1);
      downloads.dispose();
      offline.dispose();
      fills.dispose();
    },
  );

  test(
    'seven day expiry removes complete playback caches, keeps downloads',
    () async {
      await seed('watched');
      await seed('download');
      await store.markDownload('download', {'title': 'Arrival'});
      for (final id in ['watched', 'download']) {
        final entry = await store.open(id);
        entry.lastAccess = DateTime.now().subtract(const Duration(days: 8));
        await entry.flushMetadata();
      }
      // Previously opened is not the same as actively playing.
      await store.evict();
      expect(await store.allItemIds(), ['download']);
    },
  );

  test(
    'clear discovers orphan data and interrupted metadata temp files',
    () async {
      final cache = Directory('${dir.path}/media-cache');
      await cache.create();
      await File('${cache.path}/orphan.data').writeAsBytes([1, 2]);
      await File('${cache.path}/orphan.meta.json.tmp').writeAsString('{}');
      expect(await store.clear(), 1);
      expect(await cache.list().toList(), isEmpty);
    },
  );

  test('failed media deletion preserves ownership and is reported', () async {
    await seed('broken', complete: false);
    final data = File('${dir.path}/media-cache/broken.data');
    await data.delete();
    final blocked = Directory(data.path);
    await blocked.create();
    await File('${blocked.path}/child').writeAsString('blocks delete');
    await expectLater(store.clear(), throwsA(isA<FileSystemException>()));
    expect(
      await File('${dir.path}/media-cache/broken.meta.json').exists(),
      isTrue,
    );
    await blocked.delete(recursive: true);
    expect(await store.clear(), 1);
  });

  test('clear drains a concurrent open before discovering files', () async {
    final opening = store.open('racing');
    final clearing = store.clear();
    final entry = await opening;
    expect(await clearing, 1);
    expect(entry.closed, isTrue);
    expect(await store.allItemIds(), isEmpty);
  });

  test(
    'a download intent queued with clear survives either ordering',
    () async {
      await seed('before', complete: false);
      await Future.wait([
        store.markDownload('before', {'title': 'Before'}),
        store.clear(),
      ]);
      expect(await store.downloadItemIds(), ['before']);
      await Future.wait([
        store.clear(),
        store.markDownload('after', {'title': 'After'}),
      ]);
      expect(
        await store.downloadItemIds(),
        unorderedEquals(['before', 'after']),
      );
    },
  );

  test(
    'explicit delete removes download data, sidecar and temp metadata',
    () async {
      await seed('download');
      await store.markDownload('download', {'title': 'Arrival'});
      await File(
        '${dir.path}/media-cache/download.meta.json.tmp',
      ).writeAsString('{}');
      await store.delete('download');
      await store.delete('download');
      expect(await store.allItemIds(), isEmpty);
    },
  );

  test('legacy completed files are preserved when intent is unknown', () async {
    await seed('legacy');
    await store.dispose();
    final file = File('${dir.path}/media-cache/legacy.meta.json');
    final meta = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    meta.remove('retention');
    await file.writeAsString(jsonEncode(meta));
    store = RangeCacheStore(overrideDir: dir);
    expect(await store.clear(), 0);
    expect(await store.isComplete('legacy'), isTrue);
  });
}
