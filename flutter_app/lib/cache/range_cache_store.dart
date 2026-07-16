import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'range_set.dart';

/// A cached byte range expressed as a fraction (`0..1`) of a title's total
/// length — what the player's seek bar overlay draws.
///
/// Byte-fraction only approximates time-fraction for variable-bitrate media
/// (a byte range near the start of a VBR file doesn't necessarily cover the
/// same fraction of *duration* as one near the end); that's an acceptable
/// approximation for an indicator, not for anything that needs to be exact.
class CachedSpan {
  const CachedSpan(this.start, this.end);
  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is CachedSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'CachedSpan($start, $end)';
}

/// Pure computation of [CachedSpan]s from a set of present byte intervals and
/// a title's total length. Kept top-level/pure so it's unit-testable without
/// touching a [RangeSet] or any I/O.
List<CachedSpan> cachedSpansFromIntervals(
  List<List<int>> intervals,
  int? totalLength,
) {
  if (totalLength == null || totalLength <= 0) return const [];
  return intervals
      .map((iv) => CachedSpan(iv[0] / totalLength, iv[1] / totalLength))
      .toList(growable: false);
}

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
    this._cachedSpans,
  ) {
    _recomputeCachedSpans();
  }

  final String itemId;
  final RandomAccessFile _raf;
  final File _metaFile;

  /// Pure interval bookkeeping for which byte ranges are present. Exposed for
  /// tests; playback code should go through [hasRange]/[missingRanges].
  final RangeSet rangeSet;

  int? _totalLength;
  DateTime createdAt;
  DateTime lastAccess;

  /// Cached spans as 0..1 fractions of [totalLength], kept in sync with
  /// [rangeSet]/[totalLength] so the player's seek-bar overlay can observe
  /// the cache growing. Shared with (and owned by) the [RangeCacheStore] that
  /// opened this entry, so a listener attached before [open] completes keeps
  /// working afterwards.
  final ValueNotifier<List<CachedSpan>> _cachedSpans;

  ValueListenable<List<CachedSpan>> get cachedSpans => _cachedSpans;

  void _recomputeCachedSpans() {
    _cachedSpans.value = cachedSpansFromIntervals(
      rangeSet.intervals,
      _totalLength,
    );
  }

  int? get totalLength => _totalLength;

  void setTotalLength(int length) {
    _totalLength = length;
    _recomputeCachedSpans();
  }

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
    _recomputeCachedSpans();
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

  // Note: does NOT dispose [_cachedSpans] — that notifier is owned by the
  // [RangeCacheStore] (keyed by itemId, outliving any single open/close of
  // this entry), not by this entry.
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

  /// Per-itemId cached-spans notifiers, created lazily and kept alive across
  /// [open] calls — [cachedSpansFor] may be called before an entry is open
  /// (e.g. the player mounts before the proxy has served a byte), so the
  /// notifier is created up front and handed to the [CacheEntry] once it
  /// opens, rather than the entry owning a fresh one.
  final Map<String, ValueNotifier<List<CachedSpan>>> _cachedSpansNotifiers =
      {};

  /// A [ValueListenable] of [CachedSpan]s for [itemId], as fractions of the
  /// title's total length, updating as the on-device cache grows. Empty
  /// until the entry is open and its total length is known.
  ValueListenable<List<CachedSpan>> cachedSpansFor(String itemId) =>
      _notifierFor(itemId);

  ValueNotifier<List<CachedSpan>> _notifierFor(String itemId) =>
      _cachedSpansNotifiers.putIfAbsent(
        itemId,
        () => ValueNotifier<List<CachedSpan>>(const []),
      );

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
      _notifierFor(itemId),
    );
    _open[itemId] = entry;
    return entry;
  }
}
