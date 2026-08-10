// The analog seek timeline: a precision hairline, not a filled bar.
//
// "Keep the visible idle line approximately 2px thick while providing a much
// larger invisible pointer/touch target. During hover, focus, or scrubbing, the
// visible line expands slightly to about 4px without moving surrounding
// controls." (docs/watchparty-design/player-interface-reference.md)
//
// Every geometry constant comes from AnalogHairline so the React and Flutter
// timelines cannot drift apart.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';
import '../../ui/palette.dart';

/// A normalised `0..1` span of the timeline.
@immutable
class TimelineRange {
  const TimelineRange(this.start, this.end);

  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is TimelineRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimelineRange($start, $end)';
}

/// Turn normalised [ranges] into rects inside [track], keeping a visible
/// [gapPx] between spans that do not touch.
///
/// Pure so the layering rules ("visible gaps when the playback engine exposes
/// separate ranges") are testable without pumping a widget. Overlapping or
/// abutting spans merge into one — a seam inside a contiguous run would read as
/// a hole in the buffer — and every remaining boundary is opened up to [gapPx]
/// by pulling the LEFT span's right edge back, so a range never appears to
/// start later than it does. A span too narrow to survive that is dropped
/// rather than drawn as a sliver.
List<Rect> timelineSegments(
  List<TimelineRange> ranges,
  Rect track, {
  double gapPx = AnalogHairline.rangeGapPx,
}) {
  if (track.width <= 0 || track.height <= 0) return const [];

  final normalised = <TimelineRange>[];
  for (final range in ranges) {
    final start = range.start.clamp(0.0, 1.0);
    final end = range.end.clamp(0.0, 1.0);
    if (end > start) normalised.add(TimelineRange(start, end));
  }
  if (normalised.isEmpty) return const [];
  normalised.sort((a, b) => a.start.compareTo(b.start));

  final merged = <TimelineRange>[normalised.first];
  for (final range in normalised.skip(1)) {
    final last = merged.last;
    if (range.start <= last.end) {
      merged[merged.length - 1] = TimelineRange(
        last.start,
        math.max(last.end, range.end),
      );
    } else {
      merged.add(range);
    }
  }

  final rects = <Rect>[];
  for (var i = 0; i < merged.length; i++) {
    final left = track.left + merged[i].start * track.width;
    var right = track.left + merged[i].end * track.width;
    if (i + 1 < merged.length) {
      final nextLeft = track.left + merged[i + 1].start * track.width;
      right = math.min(right, nextLeft - gapPx);
    }
    if (right <= left) continue;
    rects.add(Rect.fromLTRB(left, track.top, right, track.bottom));
  }
  return rects;
}

/// The seek track. Layers weakest to strongest: unloaded hairline,
/// cached/offline spans, played progress — then the handle.
///
/// Replaces the Material [Slider] the transport used to wrap: a slider cannot
/// render disjoint ranges, and its thumb collapsed to radius 0 when disabled,
/// which left a read-only guest with a bar and no position marker at all.
class AnalogTimeline extends StatefulWidget {
  const AnalogTimeline({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onPreview,
    required this.onCommit,
    required this.onHoverPreview,
    required this.onHoverEnd,
    this.cached = const [],
    this.onScrubbingChanged,
    this.focusNode,
  });

  final Duration position;
  final Duration duration;

  /// Scrubbing rights. A read-only guest still gets hover previews, the handle
  /// and the full layer stack — only the write path is closed.
  final bool enabled;

  final ValueChanged<Duration> onPreview;
  final ValueChanged<Duration> onCommit;
  final void Function(Duration position, double fraction) onHoverPreview;
  final VoidCallback onHoverEnd;

  /// Cached ("downloaded") spans.
  final List<TimelineRange> cached;

  /// Raised for the length of a drag so the caller can pin the chrome open.
  final ValueChanged<bool>? onScrubbingChanged;

  final FocusNode? focusNode;

  @override
  State<AnalogTimeline> createState() => _AnalogTimelineState();
}

class _AnalogTimelineState extends State<AnalogTimeline> {
  bool _hovering = false;
  bool _focused = false;
  bool _dragging = false;

  double? _dragFraction;

  double get _fraction {
    if (_dragFraction != null) return _dragFraction!;
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  double _fractionAt(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    if (width <= 0) return 0;
    return (dx / width).clamp(0.0, 1.0);
  }

  Duration _positionFor(double fraction) => Duration(
    milliseconds: (fraction * widget.duration.inMilliseconds).round(),
  );

  bool get _seekable => widget.enabled && widget.duration.inMilliseconds > 0;

  void _setScrubbing(bool value) {
    if (_dragging == value) return;
    setState(() => _dragging = value);
    widget.onScrubbingChanged?.call(value);
  }

  void _preview(double fraction) {
    setState(() => _dragFraction = fraction);
    widget.onPreview(_positionFor(fraction));
  }

  void _commit(double fraction) {
    setState(() => _dragFraction = null);
    widget.onCommit(_positionFor(fraction));
  }

  @override
  Widget build(BuildContext context) {
    final active = _hovering || _focused || _dragging;
    final total = widget.duration.inMilliseconds;
    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.enabled,
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        cursor: _seekable ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovering = true),
        onHover: (event) {
          if (total <= 0) return;
          final fraction = _fractionAt(event.localPosition.dx);
          widget.onHoverPreview(_positionFor(fraction), fraction);
        },
        onExit: (_) {
          setState(() => _hovering = false);
          widget.onHoverEnd();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: !_seekable
              ? null
              : (details) => _commit(_fractionAt(details.localPosition.dx)),
          onHorizontalDragStart: !_seekable
              ? null
              : (details) {
                  _setScrubbing(true);
                  _preview(_fractionAt(details.localPosition.dx));
                },
          onHorizontalDragUpdate: !_seekable
              ? null
              : (details) => _preview(_fractionAt(details.localPosition.dx)),
          onHorizontalDragEnd: !_seekable
              ? null
              : (_) {
                  final fraction = _dragFraction;
                  _setScrubbing(false);
                  if (fraction != null) _commit(fraction);
                },
          onHorizontalDragCancel: !_seekable
              ? null
              : () {
                  _setScrubbing(false);
                  setState(() => _dragFraction = null);
                },
          // The hit box is AnalogHairline.hitPx tall at every state, so growing
          // the visible line from idlePx to activePx never moves the row.
          child: SizedBox(
            height: AnalogHairline.hitPx,
            width: double.infinity,
            child: CustomPaint(
              painter: AnalogTimelinePainter(
                fraction: _fraction,
                cached: widget.cached,
                active: active,
                focused: _focused && !_hovering && !_dragging,
                showHandle: active,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the four timeline layers and the handle. Exposed (rather than
/// private) so tests can drive the geometry directly.
class AnalogTimelinePainter extends CustomPainter {
  const AnalogTimelinePainter({
    required this.fraction,
    required this.cached,
    required this.active,
    required this.focused,
    required this.showHandle,
  });

  final double fraction;
  final List<TimelineRange> cached;

  /// Hover, focus or scrub — the line thickens from idlePx to activePx.
  final bool active;

  /// Keyboard focus without a pointer on the control: draws a ring around the
  /// handle instead of permanently enlarging it.
  final bool focused;
  final bool showHandle;

  static const Color playedColor = kBrandRed;

  static Rect trackRect(Size size, {required bool active}) {
    final height = active ? AnalogHairline.activePx : AnalogHairline.idlePx;
    final top = (size.height - height) / 2;
    return Rect.fromLTWH(0, top, size.width, height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final track = trackRect(size, active: active);
    final radius = Radius.circular(track.height / 2);

    // 1 — unloaded duration: the quietest line on the stage.
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = AnalogColor.line,
    );

    // 2 — cached / offline spans.
    final cachedPaint = Paint()..color = AnalogColor.inkDim;
    for (final rect in timelineSegments(cached, track)) {
      canvas.drawRect(rect, cachedPaint);
    }

    // 3 — played progress: the strongest segment.
    final playedWidth = (fraction.clamp(0.0, 1.0)) * track.width;
    if (playedWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(track.left, track.top, playedWidth, track.height),
          radius,
        ),
        Paint()..color = playedColor,
      );
    }

    if (!showHandle) return;
    final centre = Offset(track.left + playedWidth, size.height / 2);
    canvas.drawCircle(
      centre,
      AnalogHairline.handlePx / 2,
      Paint()..color = playedColor,
    );
    if (focused) {
      canvas.drawCircle(
        centre,
        AnalogHairline.handleFocusPx / 2,
        Paint()
          ..color = playedColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(AnalogTimelinePainter old) =>
      old.fraction != fraction ||
      old.active != active ||
      old.focused != focused ||
      old.showHandle != showHandle ||
      !listEquals(old.cached, cached);
}
