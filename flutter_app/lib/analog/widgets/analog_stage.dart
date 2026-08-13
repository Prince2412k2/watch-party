import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import '../../ui/widgets/authed_image.dart';
import '../../ui/widgets/artwork_wall.dart';
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
    this.textured,
    this.wallSeed,
  });

  final Widget child;

  /// Same-origin backdrop URL for the focused item, or null for bare ground.
  final String? backdropUrl;

  /// Crease the backdrop. Null defers to the ambient [ArtworkTextureScope], and
  /// so to the user's setting; pass it to force one stage either way.
  final bool? textured;

  /// Which wall this room is papered with. A library name, not the backdrop
  /// URL: the wall is the room, and a room that redecorates every time the
  /// selection moves is a strobe, not a stage.
  final String? wallSeed;

  /// How much wall shows around the pasted backdrop. Without a margin the sheet
  /// covers the room and there is no wall left to be pasted onto.
  static const double kPasteInset = 0.0;

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
    final textured = widget.textured ?? ArtworkTextureScope.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AnalogColor.stageGround),
              if (textured)
                WallLayer(
                  index: ArtworkWall.indexFor(widget.wallSeed),
                  withTint: ArtworkWall.kTintOpacity > 0,
                  strength: ArtworkWall.kReliefStrength,
                  brightness: ArtworkWall.kReliefBrightness,
                  contrast: ArtworkWall.kReliefContrast,
                  builder: (context, depth, tint) => Stack(
                    fit: StackFit.expand,
                    children: [
                      WallRelief(
                        depth: depth,
                        strength: ArtworkWall.kReliefStrength,
                        child: const ColoredBox(color: AnalogColor.stageGround),
                      ),
                      if (tint != null && ArtworkWall.kTintOpacity > 0)
                        Opacity(
                          opacity: ArtworkWall.kTintOpacity,
                          child: RawImage(image: tint, fit: BoxFit.cover),
                        ),
                    ],
                  ),
                ),
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
                    : _PastedBackdrop(
                        key: ValueKey(_backdropRevision),
                        url: url,
                        textured: textured,
                        wallSeed: widget.wallSeed,
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
        // The stage is what decides which room this is, so it publishes its
        // wall to everything standing in it. Without this the posters would
        // read the app-level scope, land on a different wall from the stage
        // behind them, and the courses would stop dead at every poster edge —
        // which is the one thing the whole effect depends on not happening.
        ArtworkTextureScope(
          enabled: textured,
          wallSeed: widget.wallSeed,
          child: widget.child,
        ),
      ],
    );
  }
}

/// The selected title's backdrop, pasted on the wall as a large sheet.
///
/// Inset rather than full-bleed, because a sheet that reaches every edge is
/// indistinguishable from a background — the wall has to show around it for the
/// paste to read at all. It takes the wall's relief at the same strength a
/// poster does, so the courses run through it and out onto the brick.
class _PastedBackdrop extends StatelessWidget {
  const _PastedBackdrop({
    super.key,
    required this.url,
    required this.textured,
    required this.wallSeed,
  });

  final String url;
  final bool textured;
  final String? wallSeed;

  @override
  Widget build(BuildContext context) {
    final art = AuthedNetworkImage(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );
    if (!textured) return art;

    final inset = MediaQuery.sizeOf(context).shortestSide *
        AnalogStage.kPasteInset;
    return Padding(
      padding: EdgeInsets.all(inset),
      child: WallLayer(
        index: ArtworkWall.indexFor(wallSeed),
        strength: ArtworkWall.kBackdropPasteStrength,
        brightness: ArtworkWall.kReliefBrightness,
        contrast: ArtworkWall.kReliefContrast,
        builder: (context, depth, _) => WallRelief(
          depth: depth,
          strength: ArtworkWall.kBackdropPasteStrength,
          // Seeded by the URL so the paper changes with the title rather than
          // on every rebuild.
          child: TexturedArtwork(
            seed: url,
            portrait: false,
            enabled: true,
            opacity: ArtworkTexture.kBackdropPaperOpacity,
            child: art,
          ),
        ),
      ),
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
