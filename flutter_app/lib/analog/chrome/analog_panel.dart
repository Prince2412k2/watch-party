import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';

/// How far a panel stands off the stage.
///
/// The offsets are directional ([AnalogElevation] x is positive, y is positive)
/// because the scene has one light above-left, so every shadow in the app falls
/// the same way. A panel that floats without a direction is the "generic black
/// drop shadow" the reference rules out.
enum AnalogLift {
  /// On the stage. Hairline only.
  flush,

  /// A plate resting on the stage.
  rest,

  /// A surface over content — a dialog, a menu, a toast.
  over,
}

/// The kit's one framed surface.
///
/// Everything that used to be a shadcn `Card`/`SurfaceCard` is this: a warm
/// surface from the ramp, a fine hairline, chrome radius (never poster radius),
/// and a directional cast shadow keyed to the same light as the artwork.
///
/// [translucent] is for chrome that sits over moving picture — the party
/// overlays and the toast rail. It blurs what is behind it rather than hiding
/// it, and collapses to an opaque surface of equivalent contrast when the
/// platform asks for reduced transparency, so the content never simply
/// disappears for those users.
class AnalogPanel extends StatelessWidget {
  const AnalogPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AnalogSpace.lgPx),
    this.radius = AnalogRadius.chromePx,
    this.fill,
    this.border,
    this.lift = AnalogLift.rest,
    this.translucent = false,
    this.blur = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Defaults to [AnalogColor.stageSurface] (or the scrim, when translucent).
  final Color? fill;
  final Color? border;
  final AnalogLift lift;
  final bool translucent;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final reduceTransparency = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final blurred = translucent && !reduceTransparency && blur > 0;

    final fillColor =
        fill ??
        (translucent && !reduceTransparency
            ? AnalogColor.backdropScrim
            : AnalogColor.stageSurface);

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? AnalogColor.line),
        boxShadow: switch (lift) {
          AnalogLift.flush => const [],
          AnalogLift.rest => const [
            BoxShadow(
              color: AnalogColor.shadowCast,
              blurRadius: AnalogElevation.restBlurPx,
              offset: Offset(
                AnalogElevation.restOffsetXPx,
                AnalogElevation.restOffsetYPx,
              ),
            ),
          ],
          AnalogLift.over => const [
            BoxShadow(
              color: AnalogColor.shadowCastStrong,
              blurRadius: AnalogElevation.focusBlurPx,
              offset: Offset(
                AnalogElevation.focusOffsetXPx,
                AnalogElevation.focusOffsetYPx,
              ),
            ),
          ],
        },
      ),
      child: Padding(padding: padding, child: child),
    );

    if (!blurred) return decorated;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: decorated,
      ),
    );
  }
}
