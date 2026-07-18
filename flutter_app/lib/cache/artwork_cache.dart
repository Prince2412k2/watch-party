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
      final fresh = await _inflight.putIfAbsent(
        url,
        () => _fetchAndStore(url, file),
      );
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
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.statusCode != 200 || response.data == null) {
      throw StateError('Artwork request failed: HTTP ${response.statusCode}');
    }
    return Uint8List.fromList(response.data!);
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
