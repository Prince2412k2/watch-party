import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';

/// A frosted glass plate: what is behind it, blurred, tinted and bent slightly
/// at the edges.
///
/// Three effects stack to make it read as a physical pane rather than a
/// translucent rectangle:
///
/// * **Frost** — the tint at [frost] opacity over a [blur]-sigma blur of the
///   backdrop. Alone this is the flat "semi-transparent panel" look.
/// * **Refraction** — the backdrop is magnified by [distortion] about the
///   plate's centre before it is blurred, so what shows through sits slightly
///   off from what is behind it, the way it does through thick glass. It is
///   folded into the SAME filter as the frost rather than drawn as a separate
///   pass, which is what keeps it seamless; the widget needs its own size
///   ([LayoutBuilder]) because a scale matrix applies about the ORIGIN, so the
///   centre has to be translated back by hand or the sample slides off to the
///   corner.
///
///   This began as a magnified band clipped to the rim — a real lens is
///   thickest at the edge — and that shipped a visible artifact: the band
///   sampled at a different blur sigma to the interior, so the two met at a
///   hard ClipPath boundary and drew a crisp rectangle inside the panel. One
///   uniform sample has no boundary to give itself away.
/// * **Sheen** — a directional gradient keyed to
///   [AnalogSelection.sceneLightAngleDeg], plus a bright hairline along the
///   top edge and a dark one along the bottom. The stage is lit from above
///   left; glass in that scene catches the light on the top rim.
///
/// [opaque] is the reduced-transparency swap. A viewer who asked the platform
/// for less transparency gets a solid plate of equivalent contrast — the blur
/// is decoration, the legibility underneath it is not. Callers pass
/// `MediaQuery.of(context).highContrast`.
///
/// BackdropFilter is not free: it forces a saveLayer over its clip. Use this
/// for chrome that is occasionally on screen (toasts, the chat drawer), never
/// for something in a scrolling list.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AnalogRadius.cardPx),
    ),
    this.frost = 0.2,
    this.blur = 20,
    this.distortion = 1.04,
    this.tint = AnalogColor.stageGround,
    this.opaque = false,
    this.border = true,
    this.shadow,
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Tint opacity over the blurred backdrop. 0.2 is the house frosting.
  final double frost;

  /// Gaussian sigma for the main frost pass.
  final double blur;

  /// Backdrop magnification. 1.0 disables refraction entirely. Keep it small:
  /// this displaces the whole sample, and past a few percent the offset between
  /// what is behind the panel and what shows through it stops reading as glass
  /// and starts reading as a misaligned screenshot.
  final double distortion;

  final Color tint;
  final bool opaque;
  final bool border;
  final List<BoxShadow>? shadow;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    // Reduced transparency: one solid plate, no layers, no filters.
    if (opaque) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(tint.withValues(alpha: 0.92), Colors.black),
          borderRadius: borderRadius,
          border: border
              ? Border.all(color: AnalogColor.lineStrong)
              : null,
          boxShadow: shadow,
        ),
        child: ClipRRect(borderRadius: borderRadius, child: content),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.passthrough,
              children: [
                // 1 — the frost: the backdrop, magnified and blurred in ONE
                // filter, under a tint wash. Two passes at different sigmas is
                // what drew a visible rectangle inside the panel; there is now
                // a single sample with no internal boundary anywhere.
                Positioned.fill(
                  child: BackdropFilter(
                    filter: _frostFilter(constraints.biggest),
                    child: ColoredBox(color: tint.withValues(alpha: frost)),
                  ),
                ),

                // 2 — the sheen, lit from above-left, and the rim hairlines.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0x1FFFF6E8),
                            Color(0x00FFF6E8),
                            Color(0x14000000),
                          ],
                          stops: [0.0, 0.45, 1.0],
                        ),
                        borderRadius: borderRadius,
                        border: border
                            ? Border.all(color: AnalogColor.edgeLight, width: 1)
                            : null,
                      ),
                    ),
                  ),
                ),

                content,
              ],
            );
          },
        ),
      ),
    );
  }

  /// Blur, over a magnification about the plate's CENTRE.
  ///
  /// `ImageFilter.matrix` scales about the origin, so a bare `scale(1.04)` on a
  /// 300x200 plate pushes the sample 6px right and 4px down as well as
  /// magnifying it — the translate is what keeps the centre pinned.
  ///
  /// Composed inner-then-outer: magnify the backdrop first, blur the result.
  /// The other order blurs, then stretches the blur, which softens unevenly
  /// across the plate.
  ui.ImageFilter _frostFilter(Size size) {
    final blurFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    if (distortion <= 1.0 || size.isEmpty) return blurFilter;
    final dx = size.width * (1 - distortion) / 2;
    final dy = size.height * (1 - distortion) / 2;
    final matrix = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(distortion, distortion, 1, 1);
    return ui.ImageFilter.compose(
      outer: blurFilter,
      inner: ui.ImageFilter.matrix(matrix.storage),
    );
  }
}
