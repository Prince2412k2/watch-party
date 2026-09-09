import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/cache_fill_controller.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/stream_url.dart';

class _LocalApiClient extends MockApiClient {
  _LocalApiClient(this.url);
  final String url;
  int mints = 0;

  @override
  Future<StreamUrl> nativeStreamUrl(
    String itemId, {
    String purpose = 'stream',
    String? mediaSourceId,
  }) async {
    mints++;
    return StreamUrl(url: url, expiresAt: 9999999999999);
  }
}

void main() {
  const mib = 1024 * 1024;
  late Directory dir;
  late HttpServer server;
  late _LocalApiClient api;
  late MediaCacheProxy proxy;
  late CacheEntry entry;
  late CacheFillController controller;
  late List<(int, int)> requests;
  late Future<void> Function(HttpRequest, int, int) respond;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cache_fill_http_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = _LocalApiClient('http://127.0.0.1:${server.port}/media');
    proxy = MediaCacheProxy(
      apiClient: api,
      store: RangeCacheStore(overrideDir: dir),
    );
    entry = await proxy.openEntry('title');
    controller = CacheFillController(proxy: proxy);
    requests = [];
    respond = (request, start, end) async {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${end - 1}/${entry.totalLength}',
      );
      request.response.contentLength = end - start;
      request.response.add(Uint8List.fromList(
        List<int>.generate(end - start, (i) => (start + i) % 251),
      ));
      await request.response.close();
    };
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader)!;
      final parts = range.substring('bytes='.length).split('-');
      final start = int.parse(parts[0]);
      final end = int.parse(parts[1]) + 1;
      requests.add((start, end));
      await respond(request, start, end);
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await proxy.dispose();
    await entry.close();
    await dir.delete(recursive: true);
  });

  test('download uses 8 MiB requests, preserves islands and persists bytes',
      () async {
    const total = 10 * mib + 37;
    entry.setTotalLength(total);
    await entry.write(0, [99]);
    await entry.write(9 * mib, [98]);

    await controller.start('title');

    expect(requests, [
      (1, 8 * mib + 1),
      (8 * mib + 1, 9 * mib),
      (9 * mib + 1, total),
    ]);
    expect(api.mints, 3);
    expect(controller.progressFor('title').value.state, FillState.complete);
    final reopened = await RangeCacheStore(overrideDir: dir).open('title');
    try {
      expect(reopened.hasRange(0, total), isTrue);
      final bytes = await reopened.read(0, total);
      for (var i = 0; i < total; i++) {
        final expected = i == 0
            ? 99
            : i == 9 * mib
            ? 98
            : i % 251;
        if (bytes[i] != expected) fail('Incorrect byte at $i');
      }
    } finally {
      await reopened.close();
    }
  });

  test('pause waits for one in-flight chunk; resume fetches only the remainder',
      () async {
    const total = 8 * mib + 17;
    entry.setTotalLength(total);
    final arrived = Completer<void>();
    final release = Completer<void>();
    final normalResponse = respond;
    respond = (request, start, end) async {
      if (start == 0) {
        arrived.complete();
        await release.future;
      }
      await normalResponse(request, start, end);
    };
    final running = controller.start('title');
    try {
      await arrived.future.timeout(const Duration(seconds: 5));
      controller.pause('title');
      expect(requests, [(0, 8 * mib)]);
      expect(entry.rangeSet.isEmpty, isTrue);
    } finally {
      release.complete();
      await running;
    }
    expect(requests, [(0, 8 * mib)]);
    expect(controller.progressFor('title').value.state, FillState.paused);
    expect(controller.progressFor('title').value.cachedBytes, 8 * mib);
    await controller.resume('title');
    expect(requests, [(0, 8 * mib), (8 * mib, total)]);
    expect(controller.progressFor('title').value.state, FillState.complete);
  });

  test('default proxy cache fill retains 1 MiB upstream cadence', () async {
    entry.setTotalLength(2 * mib + 7);
    await proxy.fetchAndStore('title', entry, 0, 2 * mib + 7);
    expect(requests, [(0, mib), (mib, 2 * mib), (2 * mib, 2 * mib + 7)]);
  });

  test('custom download chunks reach upstream without 1 MiB subdivision',
      () async {
    entry.setTotalLength(3 * mib);
    controller = CacheFillController(proxy: proxy, chunkSize: 2 * mib);
    await controller.start('title');
    expect(requests, [(0, 2 * mib), (2 * mib, 3 * mib)]);
  });

  test('invalid chunk sizes fail before requesting upstream', () async {
    for (final size in [0, -1, 8 * mib + 1]) {
      expect(
        () => CacheFillController(proxy: proxy, chunkSize: size),
        throwsArgumentError,
      );
      await expectLater(
        proxy.fetchAndStore('title', entry, 0, 10, chunkSize: size),
        throwsArgumentError,
      );
    }
    expect(requests, isEmpty);
  });

  for (final mode in ['status', 'missing', 'offset', 'total', 'short', 'long']) {
    test('rejects $mode response without storing bytes; resume recovers',
        () async {
      entry.setTotalLength(100);
      await entry.write(0, [99]);
      final normalResponse = respond;
      respond = (request, start, end) async {
        request.response.statusCode = mode == 'status'
            ? HttpStatus.ok
            : HttpStatus.partialContent;
        if (mode != 'missing') {
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes ${mode == 'offset' ? 0 : start}-${end - 1}/'
            '${mode == 'total' ? 101 : 100}',
          );
        }
        final adjustment = mode == 'short' ? -1 : mode == 'long' ? 1 : 0;
        final length = end - start + adjustment;
        request.response.add(List<int>.filled(length, 7));
        await request.response.close();
      };
      await controller.start('title');
      expect(controller.progressFor('title').value.state, FillState.error);
      expect(entry.rangeSet.intervals, [
        [0, 1],
      ]);
      expect(await proxy.isComplete('title'), isFalse);
      respond = normalResponse;
      await controller.resume('title');
      expect(requests, [(1, 100), (1, 100)]);
      expect(await entry.read(0, 100), [
        99,
        for (var i = 1; i < 100; i++) i,
      ]);
      expect(controller.progressFor('title').value.state, FillState.complete);
    });
  }
}
