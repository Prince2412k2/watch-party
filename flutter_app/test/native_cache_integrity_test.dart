import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/cache_fill_controller.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/stream_url.dart';

class _Api extends MockApiClient {
  _Api(this.url);
  final String url;
  Completer<void>? mintGate;
  int mints = 0;

  @override
  Future<StreamUrl> nativeStreamUrl(
    String itemId, {
    String purpose = 'stream',
    String? mediaSourceId,
  }) async {
    mints++;
    await mintGate?.future;
    return StreamUrl(url: url, expiresAt: 9999999999999);
  }
}

void main() {
  late Directory dir;
  late HttpServer server;
  late _Api api;
  late MediaCacheProxy proxy;
  late CacheFillController fills;
  late Future<void> Function(HttpRequest) respond;
  late int requests;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('native-integrity-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = _Api('http://127.0.0.1:${server.port}/media');
    requests = 0;
    respond = (request) async {
      final parts = request.headers.value('range')!.substring(6).split('-');
      final start = int.parse(parts[0]);
      final end = int.parse(parts[1]);
      request.response.statusCode = 206;
      request.response.headers.set('content-range', 'bytes $start-$end/12');
      request.response.add(List.generate(end - start + 1, (i) => start + i));
      await request.response.close();
    };
    server.listen((request) async {
      requests++;
      try {
        await respond(request);
      } catch (_) {}
    });
    proxy = MediaCacheProxy(
      apiClient: api,
      store: RangeCacheStore(overrideDir: dir),
      requestTimeout: const Duration(milliseconds: 250),
    );
    fills = CacheFillController(proxy: proxy);
  });

  tearDown(() async {
    fills.dispose();
    await proxy.dispose();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  for (final path in ['probe', 'foreground']) {
    for (final mode in [
      'ignored',
      'error',
      'offset',
      'missing',
      'short',
      'long',
      'encoded',
    ]) {
      test('$path rejects $mode without caching any body', () async {
        final entry = await proxy.openEntry('title');
        if (path == 'foreground') entry.setTotalLength(12);
        respond = (request) async {
          final size = path == 'probe' ? 1 : 12;
          request.response.statusCode = mode == 'ignored'
              ? 200
              : mode == 'error'
              ? 500
              : 206;
          if (mode != 'missing') {
            request.response.headers.set(
              'content-range',
              'bytes ${mode == 'offset' ? 1 : 0}-${size - 1}/12',
            );
          }
          if (mode == 'encoded') {
            request.response.headers.set('content-encoding', 'gzip');
          }
          request.response.add(
            List.filled(
              size +
                  (mode == 'long'
                      ? 1
                      : mode == 'short'
                      ? -1
                      : 0),
              99,
            ),
          );
          await request.response.close();
        };
        if (path == 'probe') {
          await expectLater(
            proxy.ensureTotalLength('title', entry),
            throwsA(isA<HttpException>()),
          );
          expect(entry.totalLength, isNull);
        } else {
          await proxy.start();
          final client = HttpClient();
          try {
            final response = await (await client.getUrl(
              Uri.parse(proxy.urlFor('title')),
            )).close();
            await response.drain<void>();
          } on HttpException {
            // Invalid upstream data can abort before local headers are sent.
          } finally {
            client.close(force: true);
          }
        }
        expect(entry.rangeSet.isEmpty, isTrue);
        expect(await proxy.isComplete('title'), isFalse);
      });
    }
  }

  test('stalled probe body is bounded by a deadline', () async {
    final release = Completer<void>();
    respond = (request) async {
      request.response.statusCode = 206;
      request.response.headers.set('content-range', 'bytes 0-0/12');
      await request.response.flush();
      await release.future;
      await request.response.close();
    };
    final entry = await proxy.openEntry('title');
    try {
      await expectLater(
        proxy.ensureTotalLength('title', entry),
        throwsA(isA<TimeoutException>()),
      );
      expect(entry.rangeSet.isEmpty, isTrue);
      expect(entry.totalLength, isNull);
    } finally {
      release.complete();
    }
  });

  test('concurrent start and resume share one startup probe', () async {
    api.mintGate = Completer<void>();
    final first = fills.start('title');
    final second = fills.resume('title');
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.mints, 1);
    api.mintGate!.complete();
    await Future.wait([first, second]);
    expect(requests, 2); // probe, then the remaining eleven bytes
    expect(await proxy.isComplete('title'), isTrue);
  });

  test(
    'cancel aborts a real stalled body without caching its partial bytes',
    () async {
      fills.dispose();
      await proxy.dispose();
      proxy = MediaCacheProxy(
        apiClient: api,
        store: RangeCacheStore(overrideDir: dir),
        requestTimeout: const Duration(seconds: 10),
      );
      fills = CacheFillController(proxy: proxy);
      final entry = await proxy.openEntry('title');
      entry.setTotalLength(12);
      final arrived = Completer<void>();
      final release = Completer<void>();
      respond = (request) async {
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 0-11/12');
        request.response.add([0, 1, 2]);
        await request.response.flush();
        arrived.complete();
        await release.future;
        await request.response.close();
      };
      final job = fills.start('title');
      try {
        await arrived.future.timeout(const Duration(seconds: 2));
        fills.cancel('title');
        await job.timeout(const Duration(seconds: 1));
        expect(entry.rangeSet.isEmpty, isTrue);
        expect(fills.progressFor('title').value.state, FillState.cancelled);
      } finally {
        release.complete();
      }
    },
  );

  test(
    'cancel before open completes does not mint or resurrect progress',
    () async {
      final job = fills.start('title');
      fills.cancel('title');
      await job;
      expect(api.mints, 0);
      expect(fills.progressFor('title').value.state, FillState.cancelled);
    },
  );

  test(
    'cancel while minting prevents the late URL from starting HTTP',
    () async {
      api.mintGate = Completer<void>();
      final job = fills.start('title');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fills.cancel('title');
      api.mintGate!.complete();
      await job;
      expect(requests, 0);
      expect(fills.progressFor('title').value.state, FillState.cancelled);
    },
  );

  test(
    'delete then redownload uses a fresh entry rather than stale Fill',
    () async {
      await fills.start('title');
      final old = await proxy.openEntry('title');
      fills.cancel('title');
      final deleting = proxy.deleteEntry('title');
      final restart = fills.start('title');
      await Future.wait([deleting, restart]);
      final fresh = await proxy.openEntry('title');
      expect(identical(old, fresh), isFalse);
      expect(await fresh.read(0, 12), List.generate(12, (i) => i));
      expect(fills.progressFor('title').value.state, FillState.complete);
      expect(requests, 4);
    },
  );

  test(
    'explicit media sources never reuse default or other source bytes',
    () async {
      await fills.start('title');
      final other = await proxy.openEntry('title', mediaSourceId: 'other');
      expect(other.rangeSet.isEmpty, isTrue);
      await proxy.ensureTotalLength('title', other, mediaSourceId: 'other');
      expect(other.hasRange(0, 1), isTrue);
      await expectLater(
        proxy.fetchAndStore('title', other, 1, 12),
        throwsStateError,
      );
      expect(await proxy.completedItemIds(), ['title']);
    },
  );

  test(
    'session switch rejects old URLs and late mint; old bytes remain scoped',
    () async {
      await proxy.start();
      final oldUrl = proxy.urlFor('title');
      api.mintGate = Completer<void>();
      final job = fills.start('title');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fills.cancelAll();
      await proxy.changeOrigin('https://second.example');
      api.baseUrl = 'https://second.example';
      api.mintGate!.complete();
      await job;
      expect(requests, 0);
      expect((await proxy.openEntry('title')).rangeSet.isEmpty, isTrue);
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(Uri.parse(oldUrl))).close();
        expect(response.statusCode, HttpStatus.gone);
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
    },
  );

  for (final mode in ['missing', 'truncated', 'version']) {
    test('isComplete and open reject $mode backing data', () async {
      await fills.start('title');
      final data = File('${dir.path}/media-cache/title.data');
      final meta = File('${dir.path}/media-cache/title.meta.json');
      if (mode == 'missing') await data.delete();
      if (mode == 'truncated') await data.writeAsBytes([0]);
      if (mode == 'version') {
        final raw =
            jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        raw['version'] = 2;
        await meta.writeAsString(jsonEncode(raw));
      }
      final store = RangeCacheStore(overrideDir: dir);
      try {
        expect(await store.isComplete('title'), isFalse);
        final entry = await store.open('title');
        expect(entry.rangeSet.isEmpty, isTrue);
        expect(await store.isComplete('title'), isFalse);
      } finally {
        await store.dispose();
      }
      if (mode != 'version') {
        expect(await proxy.isComplete('title'), isFalse);
        expect((await proxy.openEntry('title')).rangeSet.isEmpty, isTrue);
      }
    });
  }

  test(
    'origin namespaces isolate IDs and preserve offline data on return',
    () async {
      final a = RangeCacheStore(
        overrideDir: dir,
        namespace: 'https://a.example',
      );
      final b = RangeCacheStore(
        overrideDir: dir,
        namespace: 'https://b.example',
      );
      final entry = await a.open('title');
      entry.setTotalLength(1);
      await entry.write(0, [42]);
      await entry.flushMetadata();
      await a.dispose();
      expect(await b.isComplete('title'), isFalse);
      await b.dispose();
      final again = RangeCacheStore(
        overrideDir: dir,
        namespace: 'https://a.example',
      );
      expect(await again.isComplete('title'), isTrue);
      await again.evict();
      expect(await again.isComplete('title'), isTrue);
      await again.dispose();
    },
  );
}
