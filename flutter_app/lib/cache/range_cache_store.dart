import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'range_set.dart';

/// One title's on-disk cache: a sparse data file (only the byte ranges we've
/// actually fetched are non-zero-cost on disk — most filesystems keep
/// unwritten regions as holes) plus a JSON sidecar tracking which ranges are
/// present.
///
/// Phase 2 (this class) only ever grows an entry via [write]; nothing here
/// evicts or truncates. Phase 3 hangs an LRU/TTL sweep and the "download =
/// background-fill this same entry" driver off [RangeCacheStore.open] without
/// this class changing shape.
class CacheEntry {
  CacheEntry._(
    this.itemId,
    this._raf,
    this._metaFile,
    this.rangeSet,
    this._totalLength,
    this.createdAt,
    this.lastAccess,
  );

  final String itemId;
  final RandomAccessFile _raf;
  final File _metaFile;

  /// Pure interval bookkeeping for which byte ranges are present. Exposed for
  /// tests; playback code should go through [hasRange]/[missingRanges].
  final RangeSet rangeSet;

  int? _totalLength;
  DateTime createdAt;
  DateTime lastAccess;

  int? get totalLength => _totalLength;

  void setTotalLength(int length) => _totalLength = length;

  bool hasRange(int start, int end) => rangeSet.contains(start, end);

  List<Gap> missingRanges(int start, int end) =>
      rangeSet.missingWithin(start, end);

  /// Writes [bytes] at [offset] into the sparse data file and marks that
  /// range present. Does NOT persist metadata — call [flushMetadata] once
  /// after a batch of writes (the proxy does this after each served/read-
  /// ahead range, not per-chunk, to avoid a syscall-per-network-packet).
  Future<void> write(int offset, List<int> bytes) async {
    if (bytes.isEmpty) return;
    await _raf.setPosition(offset);
    await _raf.writeFrom(bytes);
    rangeSet.add(offset, offset + bytes.length);
  }

  /// Reads `[start, end)` from the data file. Callers must only call this for
  /// ranges already confirmed present via [hasRange]/[missingRanges] — this
  /// does not check, and would otherwise happily hand back zero-filled hole
  /// bytes for a range that was never fetched.
  Future<List<int>> read(int start, int end) async {
    if (end <= start) return const [];
    await _raf.setPosition(start);
    return _raf.read(end - start);
  }

  Future<void> touch() async {
    lastAccess = DateTime.now();
  }

  /// Atomically persists the sidecar metadata (temp file + rename), so a
  /// crash mid-write can't leave a half-written, corrupt JSON file behind.
  Future<void> flushMetadata() async {
    final tmp = File('${_metaFile.path}.tmp');
    final json = <String, dynamic>{
      'itemId': itemId,
      'totalLength': _totalLength,
      'createdAt': createdAt.toIso8601String(),
      'lastAccess': lastAccess.toIso8601String(),
      'ranges': rangeSet.intervals,
    };
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(_metaFile.path);
  }

  Future<void> close() => _raf.close();
}

/// Opens/creates per-title [CacheEntry]s under a `media-cache/` subdirectory
/// of the app's support directory (overridable for tests). Keeps opened
/// entries (and their file handles) alive for the process lifetime — Phase 3
/// will add closing/evicting idle entries.
class RangeCacheStore {
  RangeCacheStore({Directory? overrideDir}) : _overrideDir = overrideDir;

  final Directory? _overrideDir;
  static const _subdirName = 'media-cache';

  final Map<String, CacheEntry> _open = {};

  Future<Directory> _cacheDir() async {
    final base = _overrideDir ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_subdirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Loads (or creates) the cache entry for [itemId]. Safe to call
  /// repeatedly — subsequent calls for an already-open entry return the same
  /// instance rather than reopening the file.
  Future<CacheEntry> open(String itemId) async {
    final existing = _open[itemId];
    if (existing != null) return existing;

    final dir = await _cacheDir();
    final dataFile = File('${dir.path}/$itemId.data');
    final metaFile = File('${dir.path}/$itemId.meta.json');

    var rangeSet = RangeSet();
    int? totalLength;
    var createdAt = DateTime.now();
    var lastAccess = createdAt;

    if (await metaFile.exists()) {
      try {
        final raw =
            jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        totalLength = (raw['totalLength'] as num?)?.toInt();
        createdAt =
            DateTime.tryParse(raw['createdAt'] as String? ?? '') ?? createdAt;
        lastAccess =
            DateTime.tryParse(raw['lastAccess'] as String? ?? '') ??
                lastAccess;
        rangeSet = RangeSet.fromJson({'intervals': raw['ranges'] ?? const []});
      } catch (_) {
        // Corrupt sidecar — treat this title as an empty cache rather than
        // failing playback; the proxy will just re-fetch everything.
        rangeSet = RangeSet();
      }
    }

    if (!await dataFile.exists()) {
      await dataFile.create(recursive: true);
    }
    // FileMode.append: created without truncating an existing file (unlike
    // FileMode.write, which truncates), and the RandomAccessFile it returns
    // still honours explicit `setPosition` for both reads and writes — it
    // only affects the *initial* position, not every write like POSIX
    // O_APPEND — which is exactly the "open once, read/write anywhere"
    // handle a sparse cache file needs.
    final raf = await dataFile.open(mode: FileMode.append);

    final entry = CacheEntry._(
      itemId,
      raf,
      metaFile,
      rangeSet,
      totalLength,
      createdAt,
      lastAccess,
    );
    _open[itemId] = entry;
    return entry;
  }
}
