import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Persistent artwork bytes with stale-while-revalidate delivery.
class ArtworkCache {
  ArtworkCache(
    this._dio, {
    required this.directory,
    this.maxMemoryBytes = 64 * 1024 * 1024,
  });

  final Directory directory;
  final int maxMemoryBytes;
  final Dio _dio;
  final Map<String, Future<Uint8List>> _inflight = {};
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  var _memoryBytes = 0;

  /// Returns recently displayed artwork without touching the filesystem.
  Uint8List? peek(String url) {
    final bytes = _memory.remove(url);
    if (bytes != null) _memory[url] = bytes;
    return bytes;
  }

  Future<void> evict({
    int maxBytes = 512 * 1024 * 1024,
    Duration maxAge = const Duration(days: 90),
  }) async {
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(maxAge);
    final files = <({File file, FileStat stat})>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.image')) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
      } else {
        files.add((file: entity, stat: stat));
      }
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var total = files.fold<int>(0, (sum, entry) => sum + entry.stat.size);
    for (final entry in files) {
      if (total <= maxBytes) break;
      await entry.file.delete();
      total -= entry.stat.size;
    }
  }

  Stream<Uint8List> load(String url) async* {
    final file = File('${directory.path}/${_hash(url)}.image');
    Uint8List? cached = peek(url);
    if (cached != null) {
      yield cached;
    } else {
      try {
        if (await file.exists()) {
          cached = await file.readAsBytes();
          if (cached.isNotEmpty) {
            _remember(url, cached);
            unawaited(
              file.setLastModified(DateTime.now()).catchError((_) => file),
            );
            yield cached;
          } else {
            cached = null;
          }
        }
      } catch (_) {}
    }

    try {
      final pending = _inflight.putIfAbsent(
        url,
        () => _fetchAndStore(url, file),
      );
      // The shared future outlives this subscription: when the only listener is
      // disposed mid-fetch (an episode card scrolled out of view), a failure has
      // no awaiter left and escapes as an unhandled zone error — hundreds of
      // them for a series whose stills 404. ignore() attaches an error listener
      // so that can't happen; our own await below still sees the error.
      pending.ignore();
      final fresh = await pending;
      if (cached == null || !listEquals(cached, fresh)) {
        _remember(url, fresh);
        yield fresh;
      }
    } catch (_) {
      if (cached == null) rethrow;
    } finally {
      _inflight.remove(url);
    }
  }

  Future<Uint8List> _fetchAndStore(String url, File file) async {
    final fresh = await _fetch(url);
    await directory.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(fresh, flush: true);
    await temp.rename(file.path);
    return fresh;
  }

  Future<Uint8List> _fetch(String url) async {
    // `_dio` is the app's authenticated client — it carries the session
    // cookie on every request. The server now only ever hands the client a
    // relative same-origin proxy path for artwork (never a raw third-party
    // CDN URL — see posterUrlFromImage/shapeImages in arr.js), so a URL that
    // doesn't resolve to our own origin has no business here. Refuse it
    // outright rather than fetching it unauthenticated: the point isn't to
    // degrade gracefully, it's that this client must never be handed such a
    // URL in the first place.
    if (!isSameOrigin(url)) {
      throw StateError('Refusing to fetch cross-origin artwork: $url');
    }
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.statusCode != 200 || response.data == null) {
      throw StateError('Artwork request failed: HTTP ${response.statusCode}');
    }
    return Uint8List.fromList(response.data!);
  }

  /// Whether [load] would be willing to fetch [url] at all.
  ///
  /// A relative path resolves against `_dio`'s own baseUrl by definition; an
  /// absolute URL must match it exactly (scheme + host + port).
  ///
  /// Public because prefetch needs to ask *before* queueing: [_fetch] throws on
  /// a cross-origin URL, and a queue slot spent on a guaranteed failure is one
  /// the visible artwork wanted. Callers still get the same answer either way —
  /// this only moves the refusal earlier.
  bool isSameOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (!uri.hasScheme && !uri.hasAuthority) return true;
    final base = Uri.tryParse(_dio.options.baseUrl);
    if (base == null) return false;
    return uri.scheme == base.scheme &&
        uri.host == base.host &&
        uri.port == base.port;
  }

  void _remember(String url, Uint8List bytes) {
    final previous = _memory.remove(url);
    if (previous != null) _memoryBytes -= previous.lengthInBytes;
    _memory[url] = bytes;
    _memoryBytes += bytes.lengthInBytes;
    while (_memoryBytes > maxMemoryBytes && _memory.isNotEmpty) {
      final oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.lengthInBytes;
    }
  }
}

String _hash(String value) {
  var hash = 0xcbf29ce484222325;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
