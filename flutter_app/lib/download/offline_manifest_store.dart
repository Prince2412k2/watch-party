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

  Future<void> save(List<OfflineRecord> records) async {
    final file = await _file();
    final raw = jsonEncode(records.map((r) => r.toJson()).toList());
    await file.writeAsString(raw);
  }
}
