import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';

/// A determinate or indeterminate progress line.
///
/// "Timeline and volume are precision lines, not filled bars" is written on
/// [AnalogHairline] and holds here too: this is a 2px rule, not a capsule with
/// a gradient. A null [value] runs the indeterminate sweep.
///
/// The percentage is published to [Semantics] so the state is available to a
/// screen reader without reading pixels — the bar is the only place a download
/// reports itself, and a 2px line is exactly the sort of thing a low-vision
/// user cannot read.
class AnalogProgress extends StatefulWidget {
  const AnalogProgress({
    super.key,
    this.value,
    this.ink = AnalogColor.ink,
    this.track = AnalogColor.line,
    this.semanticLabel,
    this.thickness = AnalogHairline.idlePx,
  });

  /// 0..1, or null for indeterminate.
  final double? value;
  final Color ink;
  final Color track;
  final String? semanticLabel;
  final double thickness;

  @override
  State<AnalogProgress> createState() => _AnalogProgressState();
}

class _AnalogProgressState extends State<AnalogProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _syncSweep();
  }

  @override
  void didUpdateWidget(AnalogProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSweep();
  }

  void _syncSweep() {
    final indeterminate = widget.value == null;
    final reduceMotion =
        WidgetsBinding.instance.accessibilityFeatures.disableAnimations;
    if (indeterminate && !reduceMotion) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else if (_sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return Semantics(
      label: widget.semanticLabel,
      value: value == null
          ? 'In progress'
          : '${(value.clamp(0.0, 1.0) * 100).round()}%',
      child: SizedBox(
        height: AnalogHairline.activePx,
        child: Align(
          alignment: Alignment.center,
          child: AnimatedBuilder(
            animation: _sweep,
            builder: (context, _) => CustomPaint(
              size: const Size(double.infinity, AnalogHairline.activePx),
              painter: _ProgressPainter(
                value: value,
                phase: _sweep.value,
                ink: widget.ink,
                track: widget.track,
                thickness: widget.thickness,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({
    required this.value,
    required this.phase,
    required this.ink,
    required this.track,
    required this.thickness,
  });

  final double? value;
  final double phase;
  final Color ink;
  final Color track;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final y = (size.height - thickness) / 2;
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, thickness),
      Paint()..color = track,
    );

    final paint = Paint()..color = ink;
    final v = value;
    if (v != null) {
      final w = size.width * v.clamp(0.0, 1.0);
      if (w > 0) canvas.drawRect(Rect.fromLTWH(0, y, w, thickness), paint);
      return;
    }

    // Indeterminate: one segment travels the rule and wraps, rather than a
    // pulse — a pulse reads as "stalled" at low frame rates.
    const fraction = 0.32;
    final segment = size.width * fraction;
    final travel = size.width + segment;
    final left = phase * travel - segment;
    final visible = Rect.fromLTWH(
      left,
      y,
      segment,
      thickness,
    ).intersect(Rect.fromLTWH(0, y, size.width, thickness));
    if (visible.isEmpty) return;
    canvas.drawRect(visible, paint);
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.value != value ||
      old.phase != phase ||
      old.ink != ink ||
      old.track != track ||
      old.thickness != thickness;
}
