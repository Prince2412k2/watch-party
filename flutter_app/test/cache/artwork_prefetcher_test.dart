import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/browse_core.dart';
import 'package:watchparty/cache/artwork_cache.dart';
import 'package:watchparty/cache/artwork_prefetcher.dart';

/// A loopback artwork origin that records what was asked of it and can be
/// stalled, so a test can inspect the queue while warms are still outstanding —
/// or prove something reached the screen while the network answered nothing at
/// all. Paths under `/missing` answer 404, which is how a failing warm is
/// staged.
class _Origin {
  _Origin(this._server) {
    _server.listen((request) async {
      paths.add(request.uri.path);
      await _gate?.future;
      final missing = request.uri.path.startsWith('/missing');
      request.response.statusCode = missing
          ? HttpStatus.notFound
          : HttpStatus.ok;
      if (!missing) request.response.add(bytes);
      try {
        await request.response.close();
      } catch (_) {
        // The client gave up first. Nothing to report.
      }
    });
  }

  static Future<_Origin> bind() async =>
      _Origin(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  static const List<int> bytes = [1, 2, 3];

  final HttpServer _server;

  /// Request paths in arrival order.
  final List<String> paths = [];

  Completer<void>? _gate;

  late final String baseUrl = 'http://${_server.address.host}:${_server.port}';

  /// Accept requests but answer none of them until [release].
  void stall() => _gate ??= Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  Future<void> close() async {
    release();
    await _server.close(force: true);
  }
}

typedef _Warmer = ({ArtworkCache cache, ArtworkPrefetcher prefetcher});

void main() {
  late _Origin origin;

  setUp(() async {
    origin = await _Origin.bind();
    addTearDown(origin.close);
  });

  Future<_Warmer> warmer({int maxConcurrent = 2}) async {
    final directory = await Directory.systemTemp.createTemp('artwork-warm-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = ArtworkCache(
      Dio(BaseOptions(baseUrl: origin.baseUrl)),
      directory: directory,
    );
    final prefetcher = ArtworkPrefetcher(cache, maxConcurrent: maxConcurrent);
    addTearDown(prefetcher.dispose);
    return (cache: cache, prefetcher: prefetcher);
  }

  List<int> requestedIndices() =>
      [for (final path in origin.paths) int.parse(path.split('/').last)]..sort();

  test('the warm set is exactly the shared rail window', () async {
    const total = 40;
    const slots = 5;

    // Cursor at the start, mid-rail, and pinned against the end — the three
    // shapes railWindow clamps differently.
    for (final offset in [0, 17, total - 1]) {
      origin.paths.clear();
      // A fresh cache per case: artwork already on disk is warmed without a
      // request, and it is the request set being measured.
      final warm = await warmer();
      warm.prefetcher.warmRail(
        slot: 'rail',
        total: total,
        offset: offset,
        slots: slots,
        urlsFor: (index) => ['/poster/$index'],
      );
      await warm.prefetcher.settle();

      final window = railWindow(
        RailWindowInput(total: total, offset: offset, slots: slots),
      );
      expect(
        requestedIndices(),
        window.prefetch,
        reason: 'offset $offset warmed something other than the shared window',
      );
      // The window never covers what is on screen, so a warm can never
      // duplicate the fetch a visible card is already making for itself.
      final visible = window.visible.toSet();
      expect(window.prefetch.where(visible.contains), isEmpty);
    }
  });

  test('every url an index carries is warmed, not just the first', () async {
    final warm = await warmer();
    warm.prefetcher.warmRail(
      slot: 'rail',
      total: 8,
      offset: 0,
      slots: 2,
      lookahead: 2,
      behind: 0,
      urlsFor: (index) => ['/poster/$index', '/backdrop/$index'],
    );
    await warm.prefetcher.settle();

    expect(origin.paths..sort(), [
      '/backdrop/2',
      '/backdrop/3',
      '/poster/2',
      '/poster/3',
    ]);
  });

  test('a warmed poster paints without waiting on the network', () async {
    final warm = await warmer();
    warm.prefetcher.warm(const ['/poster/1'], slot: 'rail');
    await warm.prefetcher.settle();
    expect(origin.paths, ['/poster/1'], reason: 'the warm cost one request');

    // Nothing is answered from here on. The poster must still reach the screen,
    // which is the entire claim: its bytes are already local.
    origin.stall();
    expect(await warm.cache.load('/poster/1').first, _Origin.bytes);
    expect(origin.paths, ['/poster/1'], reason: 'and cost no second request');
  });

  test('a fast scroll leaves bounded work behind it', () async {
    const total = 400;
    const slots = 5;
    origin.stall();
    final warm = await warmer();

    // Fifty windows in a row with nothing completing — the pathological case
    // for a queue that appends instead of replacing.
    for (var offset = 0; offset < 50; offset++) {
      warm.prefetcher.warmRail(
        slot: 'rail',
        total: total,
        offset: offset,
        slots: slots,
        urlsFor: (index) => ['/poster/$index'],
      );
    }

    final lastWindow = railWindow(
      const RailWindowInput(total: total, offset: 49, slots: slots),
    ).prefetch;
    expect(warm.prefetcher.inFlight, 2, reason: 'the concurrency cap holds');
    expect(
      warm.prefetcher.pending,
      lessThanOrEqualTo(lastWindow.length),
      reason: 'the queue holds one window, not fifty',
    );

    // And the network saw only what the cap allows, not a window's worth per
    // scroll step.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(origin.paths.length, lessThanOrEqualTo(2));

    origin.release();
    // Drain before teardown pulls the cache directory out from under a write.
    await warm.prefetcher.settle();
  });

  test('independent windows do not cancel each other', () async {
    final warm = await warmer();
    warm.prefetcher.warm(const ['/poster/1'], slot: 'poster');
    warm.prefetcher.warm(const ['/backdrop/1'], slot: 'backdrop');
    await warm.prefetcher.settle();

    expect(origin.paths..sort(), ['/backdrop/1', '/poster/1']);
  });

  test('cross-origin artwork is never warmed', () async {
    final warm = await warmer();
    warm.prefetcher.warm(const [
      'https://images.example.com/poster.jpg',
    ], slot: 'rail');

    expect(warm.prefetcher.pending, 0);
    expect(warm.prefetcher.inFlight, 0);
    await warm.prefetcher.settle();
    expect(origin.paths, isEmpty);
  });

  test('a failing warm is a non-event', () async {
    final warm = await warmer();
    warm.prefetcher.warm(const ['/missing/1', '/missing/2'], slot: 'rail');
    // No unhandled error escapes, and the queue drains rather than wedging.
    await warm.prefetcher.settle();
    expect(warm.prefetcher.inFlight, 0);
    expect(warm.prefetcher.pending, 0);
    expect(origin.paths..sort(), ['/missing/1', '/missing/2']);
  });

  test('artwork already warm is not warmed again', () async {
    final warm = await warmer();
    warm.prefetcher.warm(const ['/poster/1'], slot: 'rail');
    await warm.prefetcher.settle();

    warm.prefetcher.warm(const ['/poster/1'], slot: 'rail');
    await warm.prefetcher.settle();
    expect(origin.paths, ['/poster/1']);
  });
}
