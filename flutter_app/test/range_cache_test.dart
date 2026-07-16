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
