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
/// * **Refraction** — a second backdrop sample in a band around the rim,
///   magnified by [distortion] about the plate's centre, so content near the
///   edge bends the way it does through the thick part of a lens. This is what
///   distinguishes glass from a scrim, and it is why the widget needs its own
///   size ([LayoutBuilder]) — a scale matrix is applied about the ORIGIN, so
///   the centre has to be translated back by hand or the whole sample slides
///   off to the corner.
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
    this.distortion = 1.08,
    this.rimPx = 18,
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

  /// Edge magnification. 1.0 disables refraction entirely.
  final double distortion;

  /// Width of the refracting rim band, in logical pixels.
  final double rimPx;

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
                // 1 — the frost: blurred backdrop under a tint wash.
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: ColoredBox(color: tint.withValues(alpha: frost)),
                  ),
                ),

                // 2 — the rim refraction.
                if (distortion > 1.0 && constraints.hasBoundedWidth)
                  Positioned.fill(
                    child: ClipPath(
                      clipper: _RimClipper(
                        borderRadius: borderRadius,
                        inset: rimPx,
                      ),
                      child: BackdropFilter(
                        filter: _magnify(
                          constraints.biggest,
                          distortion,
                          blur * 0.35,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                // 3 — the sheen, lit from above-left, and the rim hairlines.
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

  /// Scale [size] up by [factor] ABOUT ITS CENTRE, then blur a little.
  ///
  /// `ImageFilter.matrix` scales about the origin, so a bare `scale(1.08)` on a
  /// 300x200 plate pushes the sample 12px right and 8px down as well as
  /// magnifying it — the translate is what keeps the centre pinned.
  static ui.ImageFilter _magnify(Size size, double factor, double sigma) {
    final dx = size.width * (1 - factor) / 2;
    final dy = size.height * (1 - factor) / 2;
    final matrix = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1);
    return ui.ImageFilter.compose(
      outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      inner: ui.ImageFilter.matrix(matrix.storage),
    );
  }
}

/// The band between the plate's outer edge and an inset copy of it — the part
/// of a lens that is thick enough to bend what is behind it.
class _RimClipper extends CustomClipper<Path> {
  const _RimClipper({required this.borderRadius, required this.inset});

  final BorderRadius borderRadius;
  final double inset;

  @override
  Path getClip(Size size) {
    final outer = Path()
      ..addRRect(borderRadius.toRRect(Offset.zero & size));
    // deflate() can drive a radius negative on a small plate; RRect treats that
    // as a straight corner rather than throwing, but clamping keeps the inner
    // edge concentric with the outer one.
    final gap = inset.clamp(0.0, size.shortestSide / 2);
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            gap,
            gap,
            (size.width - gap * 2).clamp(0.0, double.infinity),
            (size.height - gap * 2).clamp(0.0, double.infinity),
          ),
          topLeft: _shrink(borderRadius.topLeft, gap),
          topRight: _shrink(borderRadius.topRight, gap),
          bottomLeft: _shrink(borderRadius.bottomLeft, gap),
          bottomRight: _shrink(borderRadius.bottomRight, gap),
        ),
      );
    return Path.combine(PathOperation.difference, outer, inner);
  }

  static Radius _shrink(Radius r, double by) => Radius.elliptical(
    (r.x - by).clamp(0.0, double.infinity),
    (r.y - by).clamp(0.0, double.infinity),
  );

  @override
  bool shouldReclip(_RimClipper old) =>
      old.borderRadius != borderRadius || old.inset != inset;
}
