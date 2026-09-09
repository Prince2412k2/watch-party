import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'range_set.dart';

/// On-disk cache format version. Bump to invalidate previously-written caches
/// whose bytes can't be trusted. v2 discards v1 caches, which were written
/// before the per-entry I/O lock and could contain bytes at wrong offsets from
/// interleaved concurrent writes.
// v3 invalidates unvalidated HTTP bodies from v2; never promote old ranges.
const _cacheVersion = 3;

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
    this._dataFile,
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
  final File _dataFile;
  late RandomAccessFile _raf;
  final File _metaFile;
  bool closed = false;

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

  // Serializes file I/O and the metadata state describing it. Every file op is
  // a `setPosition` followed by more awaits, while writes, read-ahead, touches,
  // and flushes may all arrive concurrently. Keeping range mutation and the
  // atomic sidecar replacement in this same queue prevents both stale metadata
  // snapshots and multiple writers racing on the shared `.tmp` path.
  Future<void> _operationLock = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() action) {
    if (closed) return Future.error(StateError('Cache entry closed'));
    final prev = _operationLock;
    final completer = Completer<void>();
    _operationLock = completer.future;
    return prev
        .then((_) async {
          // Handles live only for an I/O operation, not for every title ever opened.
          _raf = await _dataFile.open(mode: FileMode.append);
          try {
            return await action();
          } finally {
            await _raf.close();
          }
        })
        .whenComplete(completer.complete);
  }

  /// Writes [bytes] at [offset] into the sparse data file and marks that
  /// range present. Does NOT persist metadata — call [flushMetadata] once
  /// after a batch of writes (the proxy does this after each served/read-
  /// ahead range, not per-chunk, to avoid a syscall-per-network-packet).
  Future<void> write(int offset, List<int> bytes) async {
    if (bytes.isEmpty) return;
    await _locked(() async {
      await _raf.setPosition(offset);
      await _raf.writeFrom(bytes);
      rangeSet.add(offset, offset + bytes.length);
      _recomputeCachedSpans();
    });
  }

  /// Reads `[start, end)` from the data file. Callers must only call this for
  /// ranges already confirmed present via [hasRange]/[missingRanges] — this
  /// does not check, and would otherwise happily hand back zero-filled hole
  /// bytes for a range that was never fetched.
  Future<List<int>> read(int start, int end) async {
    if (end <= start) return const [];
    return _locked(() async {
      await _raf.setPosition(start);
      return _raf.read(end - start);
    });
  }

  /// Streams a present range without allocating the entire range at once.
  Stream<List<int>> readChunks(
    int start,
    int end, {
    required int chunkSize,
  }) async* {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    var offset = start;
    while (offset < end) {
      final chunkEnd = offset + chunkSize < end ? offset + chunkSize : end;
      final chunk = await read(offset, chunkEnd);
      if (chunk.length != chunkEnd - offset) {
        throw StateError('Unexpected end of cached media at byte $offset');
      }
      yield chunk;
      offset = chunkEnd;
    }
  }

  /// Bumps [lastAccess] to now and immediately persists it, so an entry that
  /// is only ever read (never written — e.g. it was already fully cached)
  /// still gets its recency tracked for eviction; [write] paths persist via
  /// [flushMetadata] separately after a batch of writes, but a touch-only
  /// request has no other flush point.
  Future<void> touch() async {
    await _locked(() async {
      lastAccess = DateTime.now();
      await _flushMetadataUnlocked();
    });
  }

  /// Atomically persists the sidecar metadata (temp file + rename), so a
  /// crash mid-write can't leave a half-written, corrupt JSON file behind.
  Future<void> flushMetadata() => _locked(_flushMetadataUnlocked);

  Future<void> _flushMetadataUnlocked() async {
    await _raf.flush();
    final tmp = File('${_metaFile.path}.tmp');
    final json = <String, dynamic>{
      'version': _cacheVersion,
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
  Future<void> close() {
    if (closed) return _operationLock;
    final result = _operationLock;
    closed = true;
    return result;
  }
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
  // Keep the public parameter name distinct from the private field.
  // ignore: prefer_initializing_formals
  RangeCacheStore({Directory? overrideDir, String? namespace})
    : _overrideDir = overrideDir, // ignore: prefer_initializing_formals
      _namespace = namespace == null
          ? null
          : sha256.convert(utf8.encode(namespace)).toString();

  final Directory? _overrideDir;
  final String? _namespace;
  RangeCacheStore forNamespace(String namespace) =>
      RangeCacheStore(overrideDir: _overrideDir, namespace: namespace);
  bool _disposed = false;
  final Map<String, Future<void>> _deleting = {};
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
  final Map<String, Future<CacheEntry>> _opening = {};

  /// Per-itemId cached-spans notifiers, created lazily and kept alive across
  /// [open] calls — [cachedSpansFor] may be called before an entry is open
  /// (e.g. the player mounts before the proxy has served a byte), so the
  /// notifier is created up front and handed to the [CacheEntry] once it
  /// opens, rather than the entry owning a fresh one.
  final Map<String, ValueNotifier<List<CachedSpan>>> _cachedSpansNotifiers = {};

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
    final dir = Directory(
      '${base.path}/$_subdirName${_namespace == null ? '' : '/v3/$_namespace'}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Lists [dir], tolerating it disappearing mid-scan. Real installs never
  /// delete the cache dir out from under the app, but a background scan
  /// (eviction, offline rehydrate) racing a teardown shouldn't throw an
  /// unhandled error — best-effort listing keeps those paths robust.
  Future<List<FileSystemEntity>> _listSafely(Directory dir) async {
    try {
      return await dir.list().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Loads (or creates) the cache entry for [itemId]. Safe to call
  /// repeatedly — subsequent calls for an already-open entry return the same
  /// instance rather than reopening the file.
  Future<CacheEntry> open(String itemId) {
    if (_disposed) return Future.error(StateError('Cache store disposed'));
    if (!RegExp(r'^[a-zA-Z0-9_=.-]+$').hasMatch(itemId) ||
        itemId == '.' ||
        itemId == '..') {
      return Future.error(ArgumentError.value(itemId, 'itemId'));
    }
    final deleting = _deleting[itemId];
    if (deleting != null) return deleting.then((_) => open(itemId));
    final existing = _open[itemId];
    if (existing != null) return _validateOpen(itemId, existing);

    final inFlight = _opening[itemId];
    if (inFlight != null) return inFlight;

    late final Future<CacheEntry> opening;
    opening = _openEntry(itemId).whenComplete(() {
      if (identical(_opening[itemId], opening)) _opening.remove(itemId);
    });
    _opening[itemId] = opening;
    return opening;
  }

  Future<CacheEntry> _validateOpen(String itemId, CacheEntry entry) async {
    var valid = !entry.closed && await entry._dataFile.exists();
    if (valid) {
      final size = await entry._dataFile.length();
      valid = !entry.rangeSet.intervals.any((iv) => iv[1] > size);
    }
    if (valid && !entry.closed && !_disposed) return entry;
    await entry.close();
    if (identical(_open[itemId], entry)) _open.remove(itemId);
    return open(itemId);
  }

  Future<CacheEntry> _openEntry(String itemId) async {
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
        final version = (raw['version'] as num?)?.toInt() ?? 1;
        if (version == _cacheVersion && raw['itemId'] == itemId) {
          totalLength = (raw['totalLength'] as num?)?.toInt();
          createdAt =
              DateTime.tryParse(raw['createdAt'] as String? ?? '') ?? createdAt;
          lastAccess =
              DateTime.tryParse(raw['lastAccess'] as String? ?? '') ??
              lastAccess;
          rangeSet = RangeSet.fromJson({
            'intervals': raw['ranges'] ?? const [],
          });
        } else {
          // Stale cache from an older format (e.g. pre-lock v1, whose bytes may
          // sit at the wrong offsets). Discard its ranges and drop the data
          // file so we start clean and re-fetch correct bytes.
          rangeSet = RangeSet();
          if (await dataFile.exists()) await dataFile.delete();
        }
      } catch (_) {
        // Corrupt sidecar — treat this title as an empty cache rather than
        // failing playback; the proxy will just re-fetch everything.
        rangeSet = RangeSet();
        totalLength = null;
      }
    }

    final size = await dataFile.exists() ? await dataFile.length() : 0;
    if (rangeSet.intervals.any(
      (iv) =>
          iv[0] < 0 ||
          iv[1] > size ||
          (totalLength != null && iv[1] > totalLength),
    )) {
      rangeSet = RangeSet();
      totalLength = null;
    }

    if (!await dataFile.exists()) {
      await dataFile.create(recursive: true);
    }
    final entry = CacheEntry._(
      itemId,
      dataFile,
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

    // Complete downloads survive automatic cleanup. Only explicit deletion
    // (or confirmed removal from the library) should remove offline content.
    final effectiveProtected = {
      ...protected,
      ..._open.keys,
      ..._opening.keys,
      ...await completedItemIds(),
    };

    final stats = <CacheStat>[];
    for (final entity in await _listSafely(dir)) {
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
        final raw =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final rawRanges = (raw['ranges'] as List?) ?? const [];
        final intervals = rawRanges
            .map(
              (pair) => [
                ((pair as List)[0] as num).toInt(),
                (pair[1] as num).toInt(),
              ],
            )
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
      if (_open.containsKey(itemId) || _opening.containsKey(itemId)) continue;
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

  /// Whether [itemId]'s cache entry fully covers `[0, totalLength)` — i.e. the
  /// title is "downloaded" (Phase 3b: download == a fully-filled cache entry).
  /// Reads the open entry if there is one, otherwise the on-disk sidecar
  /// directly, so this is cheap to call for every title at boot without
  /// opening a file handle for each.
  Future<bool> isComplete(String itemId) async {
    final dir = await _cacheDir();
    final data = File('${dir.path}/$itemId.data');
    if (!await data.exists()) return false;
    final size = await data.length();
    final open = _open[itemId];
    if (open != null) {
      final total = open.totalLength;
      return !open.closed &&
          total != null &&
          total > 0 &&
          size >= total &&
          open.hasRange(0, total);
    }

    final metaFile = File('${dir.path}/$itemId.meta.json');
    if (!await metaFile.exists()) return false;
    try {
      final raw =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      if (raw['version'] != _cacheVersion || raw['itemId'] != itemId) {
        return false;
      }
      final total = (raw['totalLength'] as num?)?.toInt();
      if (total == null || total <= 0 || size < total) return false;
      final rangeSet = RangeSet.fromJson({
        'intervals': raw['ranges'] ?? const [],
      });
      return rangeSet.contains(0, total);
    } catch (_) {
      return false;
    }
  }

  /// Every itemId with a fully-present cache entry on disk — the source of
  /// truth for "available offline" (Phase 3b), independent of any download UI
  /// state. Scans the on-disk sidecars the same way [evict] does.
  Future<List<String>> completedItemIds() async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return const [];

    final result = <String>[];
    for (final entity in await _listSafely(dir)) {
      if (entity is! File || !entity.path.endsWith('.meta.json')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final itemId = name.substring(0, name.length - '.meta.json'.length);
      if (!itemId.startsWith('source-') && await isComplete(itemId)) {
        result.add(itemId);
      }
    }
    return result;
  }

  /// Every itemId with something on disk, complete or not.
  ///
  /// [completedItemIds] answers a different question — what is watchable
  /// offline. This one is everything the cache is holding, which is what
  /// "clear the cache" has to enumerate.
  Future<List<String>> allItemIds() async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return const [];
    final result = <String>[];
    for (final entity in await _listSafely(dir)) {
      if (entity is! File || !entity.path.endsWith('.meta.json')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      result.add(name.substring(0, name.length - '.meta.json'.length));
    }
    return result;
  }

  /// Drops everything the cache is holding except [protected].
  ///
  /// Unconditional, unlike [evict]: no size cap, no age. This is the user
  /// asking for the space back, and the only thing that survives is what they
  /// asked to keep — the titles they downloaded on purpose.
  ///
  /// Returns how many entries went, so the caller can say so.
  Future<int> clear({Set<String> protected = const {}}) async {
    var removed = 0;
    for (final itemId in await allItemIds()) {
      if (protected.contains(itemId)) continue;
      await delete(itemId);
      removed++;
    }
    return removed;
  }

  /// Deletes [itemId]'s cache entirely (data + sidecar), closing an open
  /// handle first if there is one. Used when the user removes an offline
  /// title — unlike [evict], this is an explicit, unconditional delete of one
  /// title regardless of size/TTL policy.
  Future<void> delete(String itemId) {
    return _deleting.putIfAbsent(
      itemId,
      () => _delete(itemId).whenComplete(() {
        _deleting.remove(itemId);
      }),
    );
  }

  Future<void> _delete(String itemId) async {
    try {
      await _opening[itemId];
    } catch (_) {}
    final dir = await _cacheDir();

    final openEntry = _open.remove(itemId);
    if (openEntry != null) {
      try {
        await openEntry.close();
      } catch (_) {
        // Best-effort — the files are being deleted regardless.
      }
    }
    _cachedSpansNotifiers[itemId]?.value = const [];

    final dataFile = File('${dir.path}/$itemId.data');
    final metaFile = File('${dir.path}/$itemId.meta.json');
    try {
      if (await dataFile.exists()) await dataFile.delete();
    } catch (_) {}
    try {
      if (await metaFile.exists()) await metaFile.delete();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final opening in _opening.values.toList()) {
      try {
        await opening;
      } catch (_) {}
    }
    for (final entry in _open.values.toList()) {
      await entry.close();
    }
    _open.clear();
    for (final notifier in _cachedSpansNotifiers.values) {
      notifier.dispose();
    }
    _cachedSpansNotifiers.clear();
  }
}
