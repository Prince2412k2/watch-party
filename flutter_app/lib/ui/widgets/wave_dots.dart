// Three dots travelling in a wave — "something is happening, and it has not
// failed".
//
// A static dot cannot say that. It looks identical whether the connection is
// three seconds old or has been dead for a minute, so the one thing a person
// wants to know while waiting is exactly the thing it withholds.
//
// The dots ride a sine, each a third of a period behind the last, so the motion
// reads as one travelling crest rather than three independent blinks. Deliberately
// small amplitude: this sits inside chrome, next to text, and a big bounce next
// to a label reads as a toy.
//
// IMPORTANT: this ticks forever by design, so it must only be MOUNTED while
// something is genuinely in flight. The app's persistent chrome (the popcorn, on
// every screen) will hang `pumpAndSettle` in unrelated tests if a never-settling
// ticker is left running in it — the same trap the join-pending pulse is bounded
// against.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class WaveDots extends StatefulWidget {
  const WaveDots({
    super.key,
    required this.color,
    this.dotSize = 4,
    this.gap = 3,
    this.amplitude = 2.5,
    this.period = const Duration(milliseconds: 1100),
  });

  final Color color;
  final double dotSize;
  final double gap;

  /// How far each dot travels from the centre line, in logical pixels.
  final double amplitude;

  final Duration period;

  @override
  State<WaveDots> createState() => _WaveDotsState();
}

class _WaveDotsState extends State<WaveDots>
    with SingleTickerProviderStateMixin {
  static const int _count = 3;

  /// Built in initState rather than as a `late final` initializer. A lazy field
  /// whose first reader is `dispose()` constructs an AnimationController during
  /// unmount, which looks up TickerMode on a deactivated element and throws.
  /// That has already happened once in this codebase.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void didUpdateWidget(WaveDots old) {
    super.didUpdateWidget(old);
    if (widget.period != old.period) {
      _c.duration = widget.period;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tall enough for the full travel in both directions, so the row's height
    // does not change as the dots move and nothing beside them shifts.
    final height = widget.dotSize + widget.amplitude * 2;
    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _count; i++) ...[
              if (i > 0) SizedBox(width: widget.gap),
              Transform.translate(
                offset: Offset(0, _offsetFor(i)),
                child: _Dot(
                  size: widget.dotSize,
                  // The leading dot is brightest, so the crest has a direction
                  // and the group reads as travelling rather than pulsing.
                  color: widget.color.withValues(alpha: _alphaFor(i)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _phaseFor(int index) =>
      (_c.value - index / _count) * 2 * math.pi;

  double _offsetFor(int index) => -math.sin(_phaseFor(index)) * widget.amplitude;

  double _alphaFor(int index) {
    // sin maps to [-1, 1]; lift it into a readable [0.45, 1] so the trailing
    // dots stay visible rather than disappearing.
    final wave = (math.sin(_phaseFor(index)) + 1) / 2;
    return 0.45 + wave * 0.55;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}
