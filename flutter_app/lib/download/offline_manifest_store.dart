import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Persists the completed-download manifest (`List<OfflineRecord>`) as a
/// small JSON file under the app support directory. background_downloader
/// already persists in-flight task state in its own sqlite/local-store DB
/// (see [Downloader]); this store only holds the richer, post-completion
/// metadata (title/poster/runtime) that isn't part of a bare download task.
class OfflineManifestStore {
  OfflineManifestStore({this.overrideDir});

  final Directory? overrideDir;
  static const _fileName = 'offline_manifest.json';

  /// Tail of the chain of in-flight [save]s (see [_serialize]).
  Future<void> _writes = Future<void>.value();

  Future<File> _file() async {
    final dir = overrideDir ?? await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$_fileName');
  }

  Future<List<OfflineRecord>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List;
      return raw
          .map((e) => OfflineRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      // Corrupt manifest shouldn't crash the app — treat as empty.
      return const [];
    }
  }

  /// Writes [records] as the whole manifest. Serialized against every other
  /// save on this store (two overlapping writes used to interleave inside
  /// `writeAsString`) and atomic (temp file + rename), so a reader — or a save
  /// racing an app kill — never sees a half-written manifest. Mirrors
  /// [CatalogCacheStore.write]'s temp-then-rename idiom.
  ///
  /// Serialization is per-instance: the app has exactly one store (owned by
  /// [OfflineNotifier]), and the temp name is shared, so a second store over
  /// the same directory would still race. Tests that want isolation should
  /// give each store its own `overrideDir`.
  Future<void> save(List<OfflineRecord> records) => _serialize(() async {
        final file = await _file();
        final raw = jsonEncode(records.map((r) => r.toJson()).toList());
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(raw, flush: true);
        await temp.rename(file.path);
      });

  Future<void> _serialize(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    // Swallow failures on the *chain* only (the caller still gets [result]) so
    // one failed write can't wedge every later save behind a rejected future.
    _writes = result.then((_) {}, onError: (_) {});
    return result;
  }
}
