import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../palette.dart';
import '../theme.dart';

/// Circular progress ring — a track circle plus a progress arc, with the
/// percent centered in JetBrains Mono. Neutral (theme text) by default; dimmed
/// when paused. Mirrors `DownloadDetail.tsx`'s SVG `DownloadRing` (arc via a
/// sweep angle instead of stroke-dashoffset).
class DownloadRing extends StatelessWidget {
  const DownloadRing({
    super.key,
    required this.pct,
    this.size = 72,
    this.stroke = 6,
    this.color,
    this.trackColor,
    this.labelColor,
    this.labelSize,
  });

  /// 0–100.
  final double pct;
  final double size;
  final double stroke;
  final Color? color;
  final Color? trackColor;
  final Color? labelColor;
  final double? labelSize;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final clamped = pct.clamp(0, 100).toDouble();
    final ls = labelSize ?? math.max(11.0, size * 0.26);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: clamped),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(
            pct: value,
            stroke: stroke,
            color: color ?? wp.text,
            track: trackColor ?? wp.text.withValues(alpha: 0.18),
          ),
          child: Center(
            child: Text(
              '${clamped.round()}%',
              style: AppTheme.mono.copyWith(
                fontSize: ls,
                fontWeight: FontWeight.w700,
                color: labelColor ?? Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.pct,
    required this.stroke,
    required this.color,
    required this.track,
  });

  final double pct;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    if (pct > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      final sweep = 2 * math.pi * (pct / 100);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.pct != pct ||
      old.stroke != stroke ||
      old.color != color ||
      old.track != track;
}
