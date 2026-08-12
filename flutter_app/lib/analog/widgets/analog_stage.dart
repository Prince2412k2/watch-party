import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import '../../ui/widgets/authed_image.dart';
import '../../ui/widgets/textured_artwork.dart';

/// The full-stage backdrop the whole browsing model hangs off.
///
/// "The selected media item is the visual anchor. Its backdrop fills the stage
/// and changes as selection moves." (analog-interface-reference.md §Browsing
/// model.) So the backdrop is a property of *focus*, not of the route: callers
/// pass the focused item's backdrop URL and it cross-fades on
/// [AnalogMotion.backdropCrossMs] / [AnalogMotion.backdropCrossEase].
///
/// Layered bottom to top, in [AnalogZ] order:
///
/// 1. `AnalogColor.stageGround` — warm black, never `#000`.
/// 2. the backdrop artwork, cross-faded.
/// 3. a warm scrim plus a vignette, so text and artwork stay legible over any
///    frame the backdrop happens to land on.
/// 4. fine, low-contrast grain.
/// 5. [child].
///
/// Everything below [child] is wrapped in [IgnorePointer]: the stage is scenery
/// and must never eat a gesture meant for a shelf.
class AnalogStage extends StatefulWidget {
  const AnalogStage({
    super.key,
    required this.child,
    this.backdropUrl,
    this.focused = false,
    this.textured = true,
  });

  final Widget child;

  /// Same-origin backdrop URL for the focused item, or null for bare ground.
  final String? backdropUrl;

  /// Print the backdrop on aged stock. Off restores the plain artwork, which is
  /// what the layout tests measure and what a caller wants when the treatment
  /// is being judged side by side.
  final bool textured;

  /// Whether something on the stage currently owns focus. Raises the grain by
  /// [AnalogGrain.focusedBoostPct], which is the whole of that token's job.
  final bool focused;

  @override
  State<AnalogStage> createState() => _AnalogStageState();
}

class _AnalogStageState extends State<AnalogStage> {
  var _backdropRevision = 0;

  @override
  void didUpdateWidget(AnalogStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backdropUrl != widget.backdropUrl) _backdropRevision++;
  }

  @override
  Widget build(BuildContext context) {
    final grain =
        (AnalogGrain.opacityPct +
            (widget.focused ? AnalogGrain.focusedBoostPct : 0)) /
        100;
    final url = widget.backdropUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AnalogColor.stageGround),
              AnimatedSwitcher(
                duration: AnalogMotion.backdropCrossMs,
                switchInCurve: AnalogMotion.backdropCrossEase,
                switchOutCurve: AnalogMotion.backdropCrossEase,
                // Cross-fade, not fade-out-then-in: the outgoing frame has to
                // still be there while the new one arrives or the stage blinks
                // to black on every focus step.
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: url == null
                    ? SizedBox.expand(key: ValueKey(_backdropRevision))
                    : TexturedArtwork(
                        key: ValueKey(_backdropRevision),
                        // Seeded by the URL, so the stage does not re-crease
                        // itself on every focus step — only when the backdrop
                        // behind it actually changes.
                        seed: url,
                        enabled: widget.textured,
                        child: AuthedNetworkImage(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.expand(),
                        ),
                      ),
              ),
              const _StageScrim(),
              RepaintBoundary(
                child: CustomPaint(
                  painter: AnalogGrainPainter(opacity: grain),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// The warm scrim and vignette that sit between artwork and content.
class _StageScrim extends StatelessWidget {
  const _StageScrim();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [AnalogColor.backdropScrim, AnalogColor.stageGround],
              stops: [0.15, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.25, -0.3),
              radius: 1.1,
              colors: [Color(0x00070605), AnalogColor.backdropVignette],
              stops: [0.35, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fine, low-contrast film grain over the stage.
///
/// "Fine, low-contrast grain that does not reduce text or artwork clarity" —
/// so this is single-pixel points at a few percent alpha, not a texture.
///
/// One [AnalogGrain.tilePx] tile of points is generated once from a fixed seed
/// and repeated. A fixed seed matters: regenerating per frame makes the grain
/// crawl, which is exactly the "fake static" the reference rules out.
@visibleForTesting
class AnalogGrainPainter extends CustomPainter {
  const AnalogGrainPainter({required this.opacity});

  final double opacity;

  /// Roughly one speck per 24 square pixels — dense enough to read as grain,
  /// sparse enough that a full-screen tile sweep stays cheap.
  static const double _pixelsPerSpeck = 24;

  static final Float32List _tile = _buildTile();

  static Float32List _buildTile() {
    final random = math.Random(0x616E616C);
    final count = (AnalogGrain.tilePx * AnalogGrain.tilePx / _pixelsPerSpeck)
        .round();
    final points = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      points[i * 2] = random.nextDouble() * AnalogGrain.tilePx;
      points[i * 2 + 1] = random.nextDouble() * AnalogGrain.tilePx;
    }
    return points;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || size.isEmpty) return;
    final paint = Paint()
      ..color = AnalogColor.ink.withValues(alpha: opacity)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    const tile = AnalogGrain.tilePx;
    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        canvas
          ..save()
          ..clipRect(
            Rect.fromLTWH(
              x,
              y,
              math.min(tile, size.width - x),
              math.min(tile, size.height - y),
            ),
          )
          ..translate(x, y)
          ..drawRawPoints(ui.PointMode.points, _tile, paint)
          ..restore();
      }
    }
  }

  @override
  bool shouldRepaint(AnalogGrainPainter old) => old.opacity != opacity;
}
