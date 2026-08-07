import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import 'analog_button.dart' show AnalogReact;
import 'analog_pressable.dart';

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

/// The kit's one card surface.
///
/// Everything that used to be a shadcn `Card`/`SurfaceCard` is this: a warm
/// surface from the ramp, a soft [AnalogRadius.cardPx] corner (never poster
/// radius), and a directional cast shadow keyed to the same light as the
/// artwork.
///
/// The corner used to be [AnalogRadius.chromePx] — 4px, which at 400px wide
/// reads as a rectangle somebody forgot to round rather than as an object. The
/// hairline is gone from lifted panels for the same reason it left the buttons:
/// a frame plus a fill plus a shadow is three ways of saying the same thing,
/// and the one that survives greyscale is the fill. [AnalogLift.flush] keeps
/// its hairline, because with no shadow it has nothing else to sit on.
///
/// Pass [onPressed] to make the card a control: it then answers to hover and
/// press exactly as a button does, through the same [AnalogReact], and takes
/// the kit's focus ring. A card you can click that does not move under the
/// cursor is the commonest way a list of them reads as dead.
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
    this.radius = AnalogRadius.cardPx,
    this.fill,
    this.border,
    this.lift = AnalogLift.rest,
    this.translucent = false,
    this.blur = 16,
    this.onPressed,
    this.semanticLabel,
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

  /// Makes the card a control. Null leaves it inert.
  final VoidCallback? onPressed;

  /// The card's accessible name. Wanted whenever [onPressed] is set — a
  /// clickable region whose name is "a column of four Texts" is not usable on
  /// a screen reader.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (onPressed != null) {
      return AnalogPressable(
        onPressed: onPressed,
        semanticLabel: semanticLabel,
        builder: (context, state) => AnalogFocusRing(
          visible: state.focused,
          radius: radius,
          child: AnalogReact(state: state, child: _surface(context, state)),
        ),
      );
    }
    return _surface(context, null);
  }

  Widget _surface(BuildContext context, AnalogControlState? state) {
    final reduceTransparency =
        MediaQuery.maybeOf(context)?.highContrast ?? false;
    final blurred = translucent && !reduceTransparency && blur > 0;

    final fillColor =
        fill ??
        (translucent && !reduceTransparency
            ? AnalogColor.backdropScrim
            : AnalogColor.stageSurface);

    // A card being reached lightens, the same M3 state layer every control in
    // the kit uses — so a hoverable card and a hoverable button agree about
    // what "reached" looks like.
    final washed = state == null
        ? fillColor
        : analogStateLayerOver(fillColor, state);

    final decorated = AnimatedContainer(
      duration: AnalogMotion.chromeFadeMs,
      curve: AnalogMotion.chromeFadeEase,
      decoration: BoxDecoration(
        color: washed,
        borderRadius: BorderRadius.circular(radius),
        // Only the flush variant keeps a frame. A lifted panel already says
        // "separate object" with its fill and its shadow; the hairline was the
        // third telling, and it is the one that made these read as cards in
        // the pejorative sense.
        border: border != null
            ? Border.all(color: border!)
            : lift == AnalogLift.flush
            ? Border.all(color: AnalogColor.line)
            : null,
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
