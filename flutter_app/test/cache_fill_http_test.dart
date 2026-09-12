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
  bool versionUrls = false;
  Future<void> Function(int mint)? beforeMint;

  @override
  Future<StreamUrl> nativeStreamUrl(
    String itemId, {
    String purpose = 'stream',
    String? mediaSourceId,
  }) async {
    final mint = ++mints;
    await beforeMint?.call(mint);
    return StreamUrl(
      url: versionUrls ? '$url?mint=$mint' : url,
      expiresAt: 9999999999999,
    );
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
  late List<int?> remotePorts;
  late Future<void> Function(HttpRequest, int, int) respond;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cache_fill_http_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = _LocalApiClient('http://127.0.0.1:${server.port}/media');
    proxy = MediaCacheProxy(
      apiClient: api,
      store: RangeCacheStore(overrideDir: dir),
      requestTimeout: const Duration(seconds: 1),
    );
    entry = await proxy.openEntry('title');
    controller = CacheFillController(proxy: proxy);
    requests = [];
    remotePorts = [];
    respond = (request, start, end) async {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${end - 1}/${entry.totalLength}',
      );
      request.response.contentLength = end - start;
      request.response.add(
        Uint8List.fromList(
          List<int>.generate(end - start, (i) => (start + i) % 251),
        ),
      );
      await request.response.close();
    };
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader)!;
      final parts = range.substring('bytes='.length).split('-');
      final start = int.parse(parts[0]);
      final end = int.parse(parts[1]) + 1;
      requests.add((start, end));
      remotePorts.add(request.connectionInfo?.remotePort);
      await respond(request, start, end);
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await proxy.dispose();
    await entry.close();
    await dir.delete(recursive: true);
  });

  test(
    'download uses 8 MiB requests, preserves islands and persists bytes',
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
      expect(api.mints, 1);
      expect(remotePorts.toSet(), hasLength(1));
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
    },
  );

  test(
    'pause waits for one in-flight chunk; resume fetches only the remainder',
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
    },
  );

  test('default proxy cache fill retains 1 MiB upstream cadence', () async {
    entry.setTotalLength(2 * mib + 7);
    await proxy.fetchAndStore('title', entry, 0, 2 * mib + 7);
    expect(requests, [(0, mib), (mib, 2 * mib), (2 * mib, 2 * mib + 7)]);
  });

  test(
    'custom download chunks reach upstream without 1 MiB subdivision',
    () async {
      entry.setTotalLength(3 * mib);
      controller = CacheFillController(proxy: proxy, chunkSize: 2 * mib);
      await controller.start('title');
      expect(requests, [(0, 2 * mib), (2 * mib, 3 * mib)]);
    },
  );

  test('slow but progressing body outlives the body-idle timeout', () async {
    const block = 64 * 1024;
    const total = 3 * block;
    entry.setTotalLength(total);
    respond = (request, start, end) async {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${end - 1}/$total',
      );
      request.response.contentLength = end - start;
      for (var i = start; i < end; i += block) {
        final length = (i + block).clamp(0, end) - i;
        request.response.add(
          Uint8List(length)..fillRange(0, length, i ~/ block),
        );
        await request.response.flush();
        if (i + block < end) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
      await request.response.close();
    };

    await proxy.fetchAndStore('title', entry, 0, total);

    final bytes = await entry.read(0, total);
    expect(bytes[0], 0);
    expect(bytes[block], 1);
    expect(bytes[2 * block], 2);
  });

  test('transient server failure retries the same range once', () async {
    entry.setTotalLength(100);
    var attempts = 0;
    final normalResponse = respond;
    respond = (request, start, end) async {
      attempts++;
      if (attempts == 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      await normalResponse(request, start, end);
    };

    await controller.start('title');

    expect(requests, [(0, 100), (0, 100)]);
    expect(controller.progressFor('title').value.state, FillState.complete);
  });

  test('authorization failure refreshes the signed URL once', () async {
    entry.setTotalLength(100);
    var attempts = 0;
    final normalResponse = respond;
    respond = (request, start, end) async {
      attempts++;
      if (attempts == 1) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      await normalResponse(request, start, end);
    };

    await proxy.fetchAndStore('title', entry, 0, 100);

    expect(requests, [(0, 100), (0, 100)]);
    expect(api.mints, 2);
    expect(await entry.read(0, 100), [for (var i = 0; i < 100; i++) i]);
  });

  test('concurrent authorization failures share one URL refresh', () async {
    entry.setTotalLength(100);
    api.versionUrls = true;
    final refreshGate = Completer<void>();
    api.beforeMint = (mint) => mint == 2 ? refreshGate.future : Future.value();
    final normalResponse = respond;
    respond = (request, start, end) async {
      if (request.uri.queryParameters['mint'] == '1') {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      await normalResponse(request, start, end);
    };

    final first = proxy.fetchAndStore('title', entry, 0, 50);
    final second = proxy.fetchAndStore('title', entry, 50, 100);
    for (var i = 0; i < 50 && requests.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.mints, 2);
    refreshGate.complete();
    await Future.wait([first, second]);

    expect(api.mints, 2);
    expect(await entry.read(0, 100), [for (var i = 0; i < 100; i++) i]);
  });

  test('cancelled URL mint cannot repopulate the capability cache', () async {
    entry.setTotalLength(100);
    final mintGate = Completer<void>();
    api.beforeMint = (mint) => mint == 1 ? mintGate.future : Future.value();

    final cancelled = proxy.fetchAndStore('title', entry, 0, 100);
    for (var i = 0; i < 50 && api.mints == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    proxy.abortItem('title');
    mintGate.complete();
    await expectLater(cancelled, throwsStateError);

    await proxy.fetchAndStore('title', entry, 0, 100);
    expect(api.mints, 2);
  });

  test('cancellation interrupts Retry-After backoff', () async {
    entry.setTotalLength(100);
    final retryStarted = Completer<void>();
    respond = (request, start, end) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.set(HttpHeaders.retryAfterHeader, '5');
      await request.response.close();
      if (!retryStarted.isCompleted) retryStarted.complete();
    };

    final transfer = proxy.fetchAndStore('title', entry, 0, 100);
    await retryStarted.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final elapsed = Stopwatch()..start();
    proxy.abortItem('title');
    await expectLater(
      transfer,
      throwsStateError,
    ).timeout(const Duration(seconds: 1));
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
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

  for (final mode in [
    'status',
    'missing',
    'offset',
    'total',
    'short',
    'long',
  ]) {
    test(
      'rejects $mode response without storing bytes; resume recovers',
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
          final adjustment = mode == 'short'
              ? -1
              : mode == 'long'
              ? 1
              : 0;
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
        expect(await entry.read(0, 100), [99, for (var i = 1; i < 100; i++) i]);
        expect(controller.progressFor('title').value.state, FillState.complete);
      },
    );
  }
}
