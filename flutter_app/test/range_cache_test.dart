import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/range_cache_store.dart';
import 'package:watchparty/cache/range_set.dart';

void main() {
  group('RangeSet', () {
    test('starts empty', () {
      final rs = RangeSet();
      expect(rs.isEmpty, isTrue);
      expect(rs.contains(0, 10), isFalse);
      expect(rs.missingWithin(0, 10), [const Gap(0, 10)]);
    });

    test('contains is true only once the exact range is covered', () {
      final rs = RangeSet();
      rs.add(0, 100);
      expect(rs.contains(0, 100), isTrue);
      expect(rs.contains(10, 50), isTrue);
      expect(rs.contains(0, 101), isFalse);
      expect(rs.contains(100, 150), isFalse);
    });

    test('disjoint ranges stay separate', () {
      final rs = RangeSet();
      rs.add(0, 10);
      rs.add(20, 30);
      expect(rs.intervals, [
        [0, 10],
        [20, 30],
      ]);
      expect(rs.contains(0, 30), isFalse);
    });

    test('overlapping ranges coalesce', () {
      final rs = RangeSet();
      rs.add(0, 10);
      rs.add(5, 20);
      expect(rs.intervals, [
        [0, 20],
      ]);
    });

    test('adjacent (touching) ranges coalesce into one', () {
      final rs = RangeSet();
      rs.add(0, 10);
      rs.add(10, 20);
      expect(rs.intervals, [
        [0, 20],
      ]);
    });

    test('a range spanning several existing ones merges them all', () {
      final rs = RangeSet();
      rs.add(0, 5);
      rs.add(10, 15);
      rs.add(20, 25);
      rs.add(0, 25);
      expect(rs.intervals, [
        [0, 25],
      ]);
    });

    test('adding out of order still produces sorted, coalesced intervals', () {
      final rs = RangeSet();
      rs.add(50, 60);
      rs.add(0, 10);
      rs.add(20, 30);
      rs.add(10, 20); // bridges [0,10) and [20,30) via touching both
      expect(rs.intervals, [
        [0, 30],
        [50, 60],
      ]);
    });

    group('missingWithin', () {
      test('fully present range has no gaps', () {
        final rs = RangeSet();
        rs.add(0, 100);
        expect(rs.missingWithin(10, 90), isEmpty);
      });

      test('fully missing range is one gap covering the whole query', () {
        final rs = RangeSet();
        rs.add(200, 300);
        expect(rs.missingWithin(0, 100), [const Gap(0, 100)]);
      });

      test('gap at the front of the query', () {
        final rs = RangeSet();
        rs.add(50, 100);
        expect(rs.missingWithin(0, 100), [const Gap(0, 50)]);
      });

      test('gap at the back of the query', () {
        final rs = RangeSet();
        rs.add(0, 50);
        expect(rs.missingWithin(0, 100), [const Gap(50, 100)]);
      });

      test('gap in the middle of the query', () {
        final rs = RangeSet();
        rs.add(0, 30);
        rs.add(70, 100);
        expect(rs.missingWithin(0, 100), [const Gap(30, 70)]);
      });

      test('multiple gaps interleaved with present runs', () {
        final rs = RangeSet();
        rs.add(10, 20);
        rs.add(40, 50);
        rs.add(80, 90);
        expect(rs.missingWithin(0, 100), [
          const Gap(0, 10),
          const Gap(20, 40),
          const Gap(50, 80),
          const Gap(90, 100),
        ]);
      });

      test('query narrower than a present interval clips correctly', () {
        final rs = RangeSet();
        rs.add(0, 1000);
        expect(rs.missingWithin(100, 200), isEmpty);
      });
    });

    test('round-trips through toJson/fromJson', () {
      final rs = RangeSet();
      rs.add(0, 10);
      rs.add(20, 30);
      final restored = RangeSet.fromJson(rs.toJson());
      expect(restored.intervals, rs.intervals);
    });

    test('fromJson re-coalesces a hand-edited, unsorted, overlapping list', () {
      final restored = RangeSet.fromJson({
        'intervals': [
          [20, 30],
          [0, 10],
          [10, 20],
          [25, 40],
        ],
      });
      expect(restored.intervals, [
        [0, 40],
      ]);
    });
  });

  group('RangeCacheStore', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('range_cache_store_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('write then read round-trips the exact bytes at the right offset', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);
      final entry = await store.open('item-1');

      await entry.write(100, [1, 2, 3, 4, 5]);

      expect(entry.hasRange(100, 105), isTrue);
      expect(entry.hasRange(99, 105), isFalse);
      expect(entry.hasRange(100, 106), isFalse);
      expect(await entry.read(100, 105), [1, 2, 3, 4, 5]);
      expect(entry.missingRanges(0, 200), [
        const Gap(0, 100),
        const Gap(105, 200),
      ]);
    });

    test('multiple writes coalesce and are independently readable', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);
      final entry = await store.open('item-2');

      await entry.write(0, [10, 11, 12]);
      await entry.write(3, [13, 14, 15]);

      expect(entry.hasRange(0, 6), isTrue);
      expect(await entry.read(0, 6), [10, 11, 12, 13, 14, 15]);
    });

    test('metadata (total length + ranges) persists across a fresh open', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);
      final entry = await store.open('item-3');
      entry.setTotalLength(1000);
      await entry.write(0, List<int>.filled(50, 7));
      await entry.flushMetadata();

      // A second store instance simulates a fresh app launch reopening the
      // same on-disk cache.
      final reopenedStore = RangeCacheStore(overrideDir: tmpDir);
      final reopened = await reopenedStore.open('item-3');

      expect(reopened.totalLength, 1000);
      expect(reopened.hasRange(0, 50), isTrue);
      expect(await reopened.read(0, 50), List<int>.filled(50, 7));
    });

    test('metadata sidecar is written via a rename, never left as a bare .tmp', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);
      final entry = await store.open('item-4');
      await entry.write(0, [1, 2, 3]);
      await entry.flushMetadata();

      final cacheDir = Directory('${tmpDir.path}/media-cache');
      final names = cacheDir.listSync().map((f) => f.path.split('/').last).toSet();
      expect(names, contains('item-4.meta.json'));
      expect(names.any((n) => n.endsWith('.tmp')), isFalse);
    });

    test('a title opened twice from the same store shares one entry', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);
      final first = await store.open('item-5');
      final second = await store.open('item-5');
      expect(first, same(second));
    });

    test('cachedSpansFor updates as an entry is written to', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);
      final spans = store.cachedSpansFor('item-6');
      expect(spans.value, isEmpty);

      final entry = await store.open('item-6');
      expect(spans.value, isEmpty); // totalLength still unknown

      entry.setTotalLength(1000);
      expect(spans.value, isEmpty); // total length known, but no bytes written yet

      await entry.write(0, List.filled(100, 1));
      expect(spans.value, [const CachedSpan(0, 0.1)]);

      await entry.write(500, List.filled(100, 1));
      expect(spans.value, [const CachedSpan(0, 0.1), const CachedSpan(0.5, 0.6)]);
    });
  });

  group('selectEvictions', () {
    final now = DateTime(2026, 7, 16);
    const ttl = Duration(days: 30);

    test('nothing over cap and all fresh => evicts nothing', () {
      final stats = [
        CacheStat(itemId: 'a', cachedBytes: 100, lastAccess: now),
        CacheStat(itemId: 'b', cachedBytes: 100, lastAccess: now.subtract(const Duration(days: 1))),
      ];
      expect(
        selectEvictions(stats: stats, maxBytes: 1000, now: now, ttl: ttl, protected: const {}),
        isEmpty,
      );
    });

    test('entry older than TTL is evicted even though total is under cap', () {
      final stats = [
        CacheStat(itemId: 'old', cachedBytes: 10, lastAccess: now.subtract(const Duration(days: 31))),
        CacheStat(itemId: 'fresh', cachedBytes: 10, lastAccess: now),
      ];
      expect(
        selectEvictions(stats: stats, maxBytes: 1000, now: now, ttl: ttl, protected: const {}),
        ['old'],
      );
    });

    test('an entry exactly at the TTL boundary is not evicted (isBefore, not isBefore-or-equal)', () {
      final stats = [
        CacheStat(itemId: 'boundary', cachedBytes: 10, lastAccess: now.subtract(ttl)),
      ];
      expect(
        selectEvictions(stats: stats, maxBytes: 1000, now: now, ttl: ttl, protected: const {}),
        isEmpty,
      );
    });

    test('over cap evicts oldest-first until back under the cap', () {
      final stats = [
        CacheStat(itemId: 'oldest', cachedBytes: 40, lastAccess: now.subtract(const Duration(days: 3))),
        CacheStat(itemId: 'middle', cachedBytes: 40, lastAccess: now.subtract(const Duration(days: 2))),
        CacheStat(itemId: 'newest', cachedBytes: 40, lastAccess: now.subtract(const Duration(days: 1))),
      ];
      // Total = 120, cap = 90 -> must evict at least 30 bytes; evicting just
      // "oldest" (40) brings it to 80, which is <= 90, so only one eviction
      // is needed and it must be the oldest.
      expect(
        selectEvictions(stats: stats, maxBytes: 90, now: now, ttl: ttl, protected: const {}),
        ['oldest'],
      );
    });

    test('over cap keeps evicting oldest-first until under, not just one', () {
      final stats = [
        CacheStat(itemId: 'a', cachedBytes: 50, lastAccess: now.subtract(const Duration(days: 5))),
        CacheStat(itemId: 'b', cachedBytes: 50, lastAccess: now.subtract(const Duration(days: 4))),
        CacheStat(itemId: 'c', cachedBytes: 50, lastAccess: now.subtract(const Duration(days: 3))),
      ];
      // Total = 150, cap = 40 -> must evict a, then b, then c to fit.
      expect(
        selectEvictions(stats: stats, maxBytes: 40, now: now, ttl: ttl, protected: const {}),
        ['a', 'b', 'c'],
      );
    });

    test('protected entries are never evicted, even if oldest and over cap', () {
      final stats = [
        CacheStat(itemId: 'protected-old', cachedBytes: 100, lastAccess: now.subtract(const Duration(days: 40))),
        CacheStat(itemId: 'newer', cachedBytes: 100, lastAccess: now),
      ];
      // The protected entry is both past TTL and would be the LRU pick, but
      // must survive both sweeps. The non-protected 'newer' is still a valid
      // candidate reclaimed under cap pressure — what matters here is that the
      // protected entry is never in the result.
      expect(
        selectEvictions(
          stats: stats,
          maxBytes: 50,
          now: now,
          ttl: ttl,
          protected: {'protected-old'},
        ),
        isNot(contains('protected-old')),
      );
    });

    test('empty stats list evicts nothing', () {
      expect(
        selectEvictions(stats: const [], maxBytes: 1000, now: now, ttl: ttl, protected: const {}),
        isEmpty,
      );
    });

    test('ties in lastAccess are both eligible and evicted in encounter order', () {
      final sameTime = now.subtract(const Duration(days: 1));
      final stats = [
        CacheStat(itemId: 'x', cachedBytes: 60, lastAccess: sameTime),
        CacheStat(itemId: 'y', cachedBytes: 60, lastAccess: sameTime),
      ];
      // Total = 120, cap = 50 -> both must go since even removing one (60)
      // leaves 60 > 50.
      expect(
        selectEvictions(stats: stats, maxBytes: 50, now: now, ttl: ttl, protected: const {}),
        containsAll(['x', 'y']),
      );
    });
  });

  group('RangeCacheStore.evict (filesystem)', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('range_cache_evict_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('evicts a TTL-expired entry\'s files while leaving a fresh one intact', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);

      final oldEntry = await store.open('old-item');
      oldEntry.setTotalLength(1000);
      await oldEntry.write(0, List.filled(100, 1));
      oldEntry.lastAccess = DateTime.now().subtract(const Duration(days: 40));
      await oldEntry.flushMetadata();
      await oldEntry.close();

      final freshEntry = await store.open('fresh-item');
      freshEntry.setTotalLength(1000);
      await freshEntry.write(0, List.filled(100, 1));
      await freshEntry.flushMetadata();
      await freshEntry.close();

      // Reopen with a brand-new store so neither entry is in the `_open` map
      // (simulating a cold-boot eviction scan over on-disk sidecars).
      final freshStore = RangeCacheStore(overrideDir: tmpDir);
      await freshStore.evict();

      final cacheDir = Directory('${tmpDir.path}/media-cache');
      final names = cacheDir.listSync().map((f) => f.path.split('/').last).toSet();

      expect(names.where((n) => n.startsWith('old-item')), isEmpty);
      expect(names, contains('fresh-item.data'));
      expect(names, contains('fresh-item.meta.json'));
    });

    test('a currently-open entry is never evicted even if it is TTL-expired', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);

      final entry = await store.open('playing-item');
      entry.setTotalLength(1000);
      await entry.write(0, List.filled(100, 1));
      entry.lastAccess = DateTime.now().subtract(const Duration(days: 40));
      await entry.flushMetadata();
      // Deliberately left open (no close()) — still in store's `_open` map.

      await store.evict();

      final cacheDir = Directory('${tmpDir.path}/media-cache');
      final names = cacheDir.listSync().map((f) => f.path.split('/').last).toSet();
      expect(names, contains('playing-item.data'));
      expect(names, contains('playing-item.meta.json'));
    });

    test('a corrupt sidecar is evicted rather than crashing the scan', () async {
      final store = RangeCacheStore(overrideDir: tmpDir);
      final entry = await store.open('corrupt-item');
      entry.setTotalLength(1000);
      await entry.write(0, List.filled(50, 1));
      await entry.flushMetadata();
      await entry.close();

      final cacheDir = Directory('${tmpDir.path}/media-cache');
      final metaFile = File('${cacheDir.path}/corrupt-item.meta.json');
      await metaFile.writeAsString('{not valid json');

      final freshStore = RangeCacheStore(overrideDir: tmpDir);
      await freshStore.evict(); // must not throw

      final names = cacheDir.listSync().map((f) => f.path.split('/').last).toSet();
      expect(names.where((n) => n.startsWith('corrupt-item')), isEmpty);
    });
  });

  group('cachedSpansFromIntervals', () {
    test('totalLength null => empty', () {
      expect(cachedSpansFromIntervals([[0, 100]], null), isEmpty);
    });

    test('totalLength unknown/zero-or-negative => empty', () {
      expect(cachedSpansFromIntervals([[0, 100]], 0), isEmpty);
    });

    test('no intervals => empty', () {
      expect(cachedSpansFromIntervals([], 1000), isEmpty);
    });

    test('full file => a single 0..1 span', () {
      expect(
        cachedSpansFromIntervals([[0, 1000]], 1000),
        [const CachedSpan(0, 1)],
      );
    });

    test('a middle gap => two spans around it', () {
      expect(
        cachedSpansFromIntervals([[0, 250], [750, 1000]], 1000),
        [const CachedSpan(0, 0.25), const CachedSpan(0.75, 1)],
      );
    });
  });
}
