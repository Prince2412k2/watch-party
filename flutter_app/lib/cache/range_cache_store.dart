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

  /// Bumps [lastAccess] to now and immediately persists it, so an entry that
  /// is only ever read (never written — e.g. it was already fully cached)
  /// still gets its recency tracked for eviction; [write] paths persist via
  /// [flushMetadata] separately after a batch of writes, but a touch-only
  /// request has no other flush point.
  Future<void> touch() async {
    lastAccess = DateTime.now();
    await flushMetadata();
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

/// A snapshot of one title's cache footprint, as seen by [selectEvictions] —
/// deliberately just the three fields eviction cares about, so the selection
/// logic stays decoupled from how/where those numbers were read from.
class CacheStat {
  const CacheStat({
    required this.itemId,
    required this.cachedBytes,
    required this.lastAccess,
  });

  final String itemId;

  /// Sum of present-range lengths (NOT the sparse file's logical length,
  /// which can be the whole title's size while only a sliver is downloaded).
  final int cachedBytes;
  final DateTime lastAccess;
}

/// Picks which itemIds an eviction pass should remove, given a snapshot of
/// every entry's size/recency. Pure and deterministic — no I/O, no clock
/// reads — so the size-cap and TTL policy is fully covered by unit tests
/// without touching the filesystem.
///
/// Two-phase policy:
///  1. Any non-protected entry whose [CacheStat.lastAccess] is older than
///     `now - ttl` is evicted outright (TTL sweep).
///  2. If the remaining total still exceeds [maxBytes], the remaining
///     non-protected entries are evicted oldest-`lastAccess`-first until back
///     under the cap (LRU sweep).
///
/// A protected itemId (currently open/in-use) is never evicted by either
/// phase, even if it's the oldest or the sole thing over cap.
List<String> selectEvictions({
  required List<CacheStat> stats,
  required int maxBytes,
  required DateTime now,
  required Duration ttl,
  required Set<String> protected,
}) {
  final cutoff = now.subtract(ttl);
  final evicted = <String>{};
  final remaining = <CacheStat>[];
  var remainingBytes = 0;

  for (final stat in stats) {
    if (!protected.contains(stat.itemId) && stat.lastAccess.isBefore(cutoff)) {
      evicted.add(stat.itemId);
    } else {
      remaining.add(stat);
      remainingBytes += stat.cachedBytes;
    }
  }

  if (remainingBytes > maxBytes) {
    final byAge = remaining.where((s) => !protected.contains(s.itemId)).toList()
      ..sort((a, b) => a.lastAccess.compareTo(b.lastAccess));
    for (final stat in byAge) {
      if (remainingBytes <= maxBytes) break;
      evicted.add(stat.itemId);
      remainingBytes -= stat.cachedBytes;
    }
  }

  return evicted.toList(growable: false);
}

/// Opens/creates per-title [CacheEntry]s under a `media-cache/` subdirectory
/// of the app's support directory (overridable for tests). Keeps opened
/// entries (and their file handles) alive for the process lifetime.
///
/// Phase 3a adds bounded-size, LRU/TTL [evict]ion on top of the Phase 2
/// storage shape above — nothing about [open]/[CacheEntry] changed shape for
/// it.
class RangeCacheStore {
  RangeCacheStore({Directory? overrideDir}) : _overrideDir = overrideDir;

  final Directory? _overrideDir;
  static const _subdirName = 'media-cache';

  /// Total on-disk cache size (summed over actually-present bytes, not
  /// sparse-file logical length) above which [evict] starts removing
  /// least-recently-accessed entries. A plain const so it's a one-line change
  /// later without touching call sites.
  static const maxCacheBytes = 20 * 1024 * 1024 * 1024; // 20 GiB

  /// Entries idle longer than this are evicted outright by [evict],
  /// regardless of total cache size.
  static const ttl = Duration(days: 30);

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

  /// Runs one size-cap + TTL eviction pass (see [selectEvictions] for the
  /// policy). Scans the on-disk `.meta.json` sidecars rather than assuming
  /// every entry has been [open]ed this run — a title downloaded in a past
  /// session and never touched since must still be eligible for TTL removal.
  ///
  /// [protected] itemIds (typically whatever the caller is about to play or
  /// is mid-download-fill) are never evicted; every currently-[_open] entry
  /// is protected automatically on top of that, since an open handle means
  /// "in use" regardless of what the caller passed.
  ///
  /// Safe to call with no titles cached (no-op) and safe to call repeatedly —
  /// it's a plain scan-and-delete, not incremental state.
  Future<void> evict({Set<String> protected = const {}}) async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return;

    final effectiveProtected = {...protected, ..._open.keys};

    final stats = <CacheStat>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.meta.json')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final itemId = name.substring(0, name.length - '.meta.json'.length);

      final openEntry = _open[itemId];
      if (openEntry != null) {
        stats.add(
          CacheStat(
            itemId: itemId,
            cachedBytes: _cachedBytesOf(openEntry.rangeSet.intervals),
            lastAccess: openEntry.lastAccess,
          ),
        );
        continue;
      }

      try {
        final raw = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final rawRanges = (raw['ranges'] as List?) ?? const [];
        final intervals = rawRanges
            .map((pair) => [
                  ((pair as List)[0] as num).toInt(),
                  (pair[1] as num).toInt(),
                ])
            .toList();
        final lastAccess =
            DateTime.tryParse(raw['lastAccess'] as String? ?? '') ??
                DateTime.now();
        stats.add(
          CacheStat(
            itemId: itemId,
            cachedBytes: _cachedBytesOf(intervals),
            lastAccess: lastAccess,
          ),
        );
      } catch (_) {
        // Corrupt/unreadable sidecar — treat as evictable-safe: unknown size
        // (contributes nothing to the size-cap accounting either way) and
        // "ancient" recency so the TTL sweep clears it out rather than the
        // scan crashing.
        stats.add(
          CacheStat(
            itemId: itemId,
            cachedBytes: 0,
            lastAccess: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
    }

    final toEvict = selectEvictions(
      stats: stats,
      maxBytes: maxCacheBytes,
      now: DateTime.now(),
      ttl: ttl,
      protected: effectiveProtected,
    );

    for (final itemId in toEvict) {
      final openEntry = _open.remove(itemId);
      if (openEntry != null) {
        try {
          await openEntry.close();
        } catch (_) {
          // Best-effort — the files are being deleted regardless.
        }
      }
      _cachedSpansNotifiers.remove(itemId);

      final dataFile = File('${dir.path}/$itemId.data');
      final metaFile = File('${dir.path}/$itemId.meta.json');
      try {
        if (await dataFile.exists()) await dataFile.delete();
      } catch (_) {}
      try {
        if (await metaFile.exists()) await metaFile.delete();
      } catch (_) {}
    }
  }

  int _cachedBytesOf(List<List<int>> intervals) =>
      intervals.fold<int>(0, (sum, iv) => sum + (iv[1] - iv[0]));
}
