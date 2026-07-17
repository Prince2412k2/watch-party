import 'dart:convert';
import 'dart:io';

/// Small raw-JSON cache for private catalog responses.
class CatalogCacheStore {
  CatalogCacheStore(this.directory);

  final Directory directory;

  Future<dynamic> read(String namespace, String key) async {
    final file = File('${directory.path}/${_hash('$namespace|$key')}.json');
    try {
      if (!await file.exists()) return null;
      final envelope = jsonDecode(await file.readAsString());
      if (envelope is! Map || envelope['version'] != 1) return null;
      return envelope['body'];
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String namespace, String key, dynamic body) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/${_hash('$namespace|$key')}.json');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'body': body,
      }),
      flush: true,
    );
    await temp.rename(file.path);
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
