import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/artwork_cache.dart';

void main() {
  test('artwork survives restart and refreshes after cached bytes', () async {
    final directory = await Directory.systemTemp.createTemp('artwork-cache-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });

    var responseBytes = <int>[1, 2, 3];
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..add(responseBytes)
        ..close();
    });
    // ArtworkCache now refuses to fetch anything off the authenticated dio's
    // own origin (it must never carry the session cookie to a third-party
    // host) — so the test dio needs a baseUrl matching the test server, same
    // as the real app's dio matches the configured backend.
    final base = 'http://${server.address.host}:${server.port}';
    const url = '/poster';

    final first = ArtworkCache(Dio(BaseOptions(baseUrl: base)), directory: directory);
    expect(await first.load(url).single, responseBytes);

    responseBytes = <int>[4, 5, 6];
    final afterRestart = ArtworkCache(Dio(BaseOptions(baseUrl: base)), directory: directory);
    final emissions = await afterRestart.load(url).toList();

    expect(emissions, [
      <int>[1, 2, 3],
      <int>[4, 5, 6],
    ]);
  });

  test(
    'recent artwork is synchronously reusable and memory is bounded',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'artwork-memory-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        await directory.delete(recursive: true);
      });

      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..add([request.uri.path == '/one' ? 1 : 2, 3])
          ..close();
      });
      final base = 'http://${server.address.host}:${server.port}';
      final cache = ArtworkCache(
        Dio(BaseOptions(baseUrl: base)),
        directory: directory,
        maxMemoryBytes: 3,
      );

      final first = await cache.load('$base/one').single;
      expect(identical(cache.peek('$base/one'), first), isTrue);

      await cache.load('$base/two').single;
      expect(cache.peek('$base/one'), isNull);
      expect(cache.peek('$base/two'), isA<Uint8List>());
    },
  );
}
