/// Pure interval-set arithmetic backing [RangeCacheStore]'s "which bytes of
/// this title do we already have" bookkeeping. No I/O here on purpose — kept
/// separately testable from the filesystem parts.
library;

/// A half-open byte interval `[start, end)` that is NOT yet present in a
/// cache entry — what [RangeSet.missingWithin] returns.
class Gap {
  const Gap(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is Gap && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Gap($start, $end)';
}

class _Interval {
  _Interval(this.start, this.end);
  int start;
  int end;
}

/// A sorted, coalesced set of half-open `[start, end)` byte intervals. Used
/// to track which byte ranges of a title's data file are already populated.
///
/// Intervals never overlap and touching intervals are merged (`add(0,10)`
/// then `add(10,20)` collapses to a single `[0,20)`), so the set stays as
/// compact as possible and `contains`/`missingWithin` can assume this.
class RangeSet {
  RangeSet();

  final List<_Interval> _intervals = [];

  bool get isEmpty => _intervals.isEmpty;

  /// The current intervals as `[start, end]` pairs, sorted, non-overlapping.
  List<List<int>> get intervals =>
      _intervals.map((i) => [i.start, i.end]).toList(growable: false);

  /// Marks `[start, end)` as present, merging with any overlapping or
  /// adjacent intervals already in the set.
  void add(int start, int end) {
    if (end <= start) return;

    var i = 0;
    while (i < _intervals.length && _intervals[i].end < start) {
      i++;
    }

    var mergedStart = start;
    var mergedEnd = end;
    final removeFrom = i;
    var removeCount = 0;
    while (i < _intervals.length && _intervals[i].start <= mergedEnd) {
      if (_intervals[i].start < mergedStart) mergedStart = _intervals[i].start;
      if (_intervals[i].end > mergedEnd) mergedEnd = _intervals[i].end;
      i++;
      removeCount++;
    }

    _intervals.removeRange(removeFrom, removeFrom + removeCount);
    _intervals.insert(removeFrom, _Interval(mergedStart, mergedEnd));
  }

  /// Whether `[start, end)` is fully covered by the set.
  bool contains(int start, int end) {
    if (end <= start) return true;
    for (final iv in _intervals) {
      if (iv.start <= start && iv.end >= end) return true;
      if (iv.start > start) break; // sorted — no later interval can cover it
    }
    return false;
  }

  /// The sub-intervals of `[start, end)` NOT covered by the set, in order.
  /// Returns an empty list when `[start, end)` is fully present.
  List<Gap> missingWithin(int start, int end) {
    if (end <= start) return const [];
    final gaps = <Gap>[];
    var cursor = start;
    for (final iv in _intervals) {
      if (iv.end <= cursor) continue;
      if (iv.start >= end) break;
      if (iv.start > cursor) gaps.add(Gap(cursor, iv.start));
      if (iv.end > cursor) cursor = iv.end;
      if (cursor >= end) break;
    }
    if (cursor < end) gaps.add(Gap(cursor, end));
    return gaps;
  }

  Map<String, dynamic> toJson() => {'intervals': intervals};

  factory RangeSet.fromJson(Map<String, dynamic> json) {
    final rangeSet = RangeSet();
    final raw = (json['intervals'] as List?) ?? const [];
    final loaded = <_Interval>[];
    for (final entry in raw) {
      final pair = entry as List;
      final start = (pair[0] as num).toInt();
      final end = (pair[1] as num).toInt();
      if (end > start) loaded.add(_Interval(start, end));
    }
    // Persisted intervals are expected sorted+coalesced already, but a
    // corrupt/hand-edited metadata file shouldn't break the coalescing
    // invariant the rest of this class relies on — re-derive it via `add`.
    loaded.sort((a, b) => a.start.compareTo(b.start));
    for (final iv in loaded) {
      rangeSet.add(iv.start, iv.end);
    }
    return rangeSet;
  }
}
