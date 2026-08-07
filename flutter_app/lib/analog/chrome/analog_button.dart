import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import 'analog_pressable.dart';
import 'analog_tooltip.dart';

/// What a button is for, not what colour it is.
///
/// - [primary]   the one affordance on the surface that the user came for.
///               Solid ink, no frame, and the only tone that pools light.
/// - [secondary] the quiet default: a tonal fill one step off the stage.
/// - [ghost]     ink on the stage, no fill until it is reached.
/// - [danger]    destructive. The only tone that keeps a frame, so it still
///               reads as different with the colour taken away.
enum AnalogButtonTone { primary, secondary, ghost, danger }

/// A chrome control on the analog tokens.
///
/// **A pill** ([AnalogRadius.buttonPx]), and the only piece of chrome that is.
/// It used to be a 4px-radius plate with a hairline frame, a directional edge
/// light and a cast shadow — which is a small card, on a stage already made of
/// rectangular artwork. Nothing was distinguishing the thing you press from the
/// things you look at. A pill is unambiguous: it is the only shape on the stage
/// that could not be a poster.
///
/// It answers under the finger by **scaling**, not by translating 1px onto its
/// own shadow. Scale reads at any button size; a fixed 1px nudge reads only on
/// the small ones. Hover lifts and grows a little, press shrinks past rest and
/// comes back. Still no overshoot — chrome has no mass — but the response is
/// now visible rather than something you have to be told about.
///
/// Colour does the tone work now that the frame is gone; the frame that remains
/// on [AnalogButtonTone.danger] is there so destructive stays legible in
/// greyscale.
class AnalogButton extends StatelessWidget {
  const AnalogButton({
    super.key,
    required this.label,
    this.onPressed,
    this.tone = AnalogButtonTone.secondary,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.autofocus = false,
    this.focusNode,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AnalogButtonTone tone;
  final IconData? icon;

  /// Work in flight. The button stops accepting input and swaps its glyph for a
  /// determinate-less tick mark, so "busy" is legible without colour.
  final bool busy;
  final bool expand;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Tighter padding for buttons that sit inside a row of other chrome.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    final button = AnalogPressable(
      onPressed: enabled ? onPressed : null,
      semanticLabel: label,
      autofocus: autofocus,
      focusNode: focusNode,
      builder: (context, state) =>
          _plate(context, state, expand: expand, dense: dense, tone: tone),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }

  Widget _plate(
    BuildContext context,
    AnalogControlState state, {
    required bool expand,
    required bool dense,
    required AnalogButtonTone tone,
  }) {
    final skin = _AnalogButtonSkin.resolve(tone, state);

    final Widget? leading = busy
        ? const _BusyMark()
        : (icon != null ? Icon(icon, size: 17, color: skin.ink) : null);

    return AnalogFocusRing(
      visible: state.focused,
      radius: AnalogRadius.buttonPx,
      child: AnalogReact(
        state: state,
        child: AnimatedContainer(
          duration: AnalogMotion.chromeFadeMs,
          curve: AnalogMotion.chromeFadeEase,
          constraints: const BoxConstraints(minHeight: 40),
          // Pills need their ends kept clear of the text — at the old 16px the
          // label ran into the curve.
          padding: EdgeInsets.symmetric(
            horizontal: dense ? AnalogSpace.lgPx : AnalogSpace.xlPx,
            vertical: AnalogSpace.smPx + 2,
          ),
          decoration: BoxDecoration(
            color: analogStateLayerOver(skin.fill, state),
            borderRadius: BorderRadius.circular(AnalogRadius.buttonPx),
            border: skin.lineWidth > 0
                ? Border.all(color: skin.line, width: skin.lineWidth)
                : null,
            // A soft pool under the primary only, and only while it is being
            // reached — enough to lift the one affordance the user came for off
            // the artwork, not a plate sitting on a desk.
            boxShadow: skin.glow && state.lit
                ? const [
                    BoxShadow(
                      color: AnalogColor.shadowCast,
                      blurRadius: AnalogElevation.focusBlurPx,
                      offset: Offset(0, AnalogElevation.restOffsetYPx),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading,
                const SizedBox(width: AnalogSpace.smPx),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AnalogType.sansFamily,
                    fontSize: 13.5,
                    height: 1.2,
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w600,
                    color: skin.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The physical response, shared by every control in the kit.
///
/// Hover lifts and grows a touch; press shrinks past rest and drops back to the
/// ground. One widget rather than a transform hand-rolled per control, because
/// "everything in the kit answers the same way" is the property that makes a
/// component kit feel like one thing — and it is the property that quietly
/// breaks first when each control owns its own numbers.
///
/// Deliberately no overshoot. Things with mass overshoot; chrome does not.
class AnalogReact extends StatelessWidget {
  const AnalogReact({super.key, required this.state, required this.child});

  final AnalogControlState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = !state.enabled
        ? 1.0
        : state.pressed
        ? 1 - AnalogMotion.pressScalePct / 100
        : state.lit
        ? 1 + AnalogMotion.hoverScalePct / 100
        : 1.0;
    final lift = state.enabled && state.lit && !state.pressed
        ? -AnalogMotion.hoverLiftPx
        : 0.0;

    return AnimatedContainer(
      // A press is a detent — the fastest thing in the system, because the gap
      // between finger and answer is where an interface feels slow. Releasing
      // is not urgent, so it takes the ordinary chrome fade.
      duration: state.pressed
          ? AnalogMotion.detentMs
          : AnalogMotion.chromeFadeMs,
      curve: state.pressed
          ? AnalogMotion.detentEase
          : AnalogMotion.chromeFadeEase,
      // Lift and scale ride one matrix. `AnimatedSlide` would have been the
      // obvious pairing and is wrong: its offset is a FRACTION of the child's
      // size, so a 2px lift written as an offset silently becomes "2% of
      // however tall this particular button is".
      transform: Matrix4.identity()
        ..translateByDouble(0.0, lift, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0),
      transformAlignment: Alignment.center,
      child: child,
    );
  }
}

/// An icon-only control.
///
/// [tooltip] is required and is not decoration: it is the control's accessible
/// name. An icon button with no words on it is unusable to a screen reader and
/// unlabelled on a remote, and the reference forbids hover-only affordances —
/// so the same string goes to [Semantics] and to the hover/long-press tooltip
/// together, and there is no way to construct one without it.
class AnalogIconButton extends StatelessWidget {
  const AnalogIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.tone = AnalogIconButtonTone.ghost,
    this.iconSize = 18,
    this.color,
    this.size = 34,
    this.focusNode,
  });

  final IconData icon;

  /// Accessible name *and* hover label. Required — see the class doc.
  final String tooltip;
  final VoidCallback? onPressed;
  final AnalogIconButtonTone tone;
  final double iconSize;

  /// Overrides the resting glyph colour (status reds/greens on approve/reject).
  final Color? color;

  /// The square hit target. Defaults comfortably past the 24px touch floor
  /// [AnalogHairline.hitPx] pins for the thinnest controls in the system.
  final double size;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return AnalogTooltip(
      message: tooltip,
      child: AnalogPressable(
        onPressed: onPressed,
        semanticLabel: tooltip,
        focusNode: focusNode,
        excludeSemantics: true,
        builder: (context, state) {
          final skin = _AnalogButtonSkin.resolveIcon(tone, state);
          final glyph = color != null && state.enabled
              ? (state.lit ? color! : color!.withValues(alpha: color!.a * 0.82))
              : skin.ink;
          return AnalogFocusRing(
            visible: state.focused,
            radius: AnalogRadius.buttonPx,
            inset: 4,
            child: AnalogReact(
              state: state,
              child: AnimatedContainer(
                duration: AnalogMotion.chromeFadeMs,
                curve: AnalogMotion.chromeFadeEase,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: analogStateLayerOver(skin.fill, state),
                  // A circle, being square and pill-radiused. Icon buttons are
                  // the shape a glyph actually wants — the old rounded square
                  // gave a 34px plate to an 18px mark.
                  borderRadius: BorderRadius.circular(AnalogRadius.buttonPx),
                  border: skin.lineWidth > 0
                      ? Border.all(color: skin.line, width: skin.lineWidth)
                      : null,
                  boxShadow: skin.glow && state.lit
                      ? const [
                          BoxShadow(
                            color: AnalogColor.shadowCast,
                            blurRadius: AnalogElevation.focusBlurPx,
                            offset: Offset(0, AnalogElevation.restOffsetYPx),
                          ),
                        ]
                      : const [],
                ),
                child: Center(
                  child: Icon(icon, size: iconSize, color: glyph),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fill treatment for [AnalogIconButton]: [ghost] has none until reached,
/// [outline] carries a hairline frame, [solid] carries a tonal fill, and
/// [primary] is the accent — the same weight as a primary [AnalogButton], for
/// when the page's main affordance is a glyph everybody already knows.
///
/// [primary] exists so that dropping a label is not the same as demoting the
/// action. A play triangle is the most legible mark in the medium; it should
/// not have to be a quiet ghost button just because it stopped spelling itself
/// out.
enum AnalogIconButtonTone { ghost, outline, solid, primary }

/// Busy is a state, not a colour: the glyph slot becomes a rotating tick mark
/// so the change survives greyscale and reduced-motion alike (the mark still
/// occupies the slot when animations are off).
class _BusyMark extends StatefulWidget {
  const _BusyMark();

  @override
  State<_BusyMark> createState() => _BusyMarkState();
}

class _BusyMarkState extends State<_BusyMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (!WidgetsBinding.instance.accessibilityFeatures.disableAnimations) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AnalogSpace.smPx),
      child: RotationTransition(
        turns: _spin,
        // Painted, not a bordered box.
        //
        // This used to be a BoxDecoration with shape: circle and a Border
        // whose top side was a different colour from the other three. Flutter
        // cannot paint that — "A Border can only be drawn as a circle on
        // borders with uniform colors" — so every busy button threw on every
        // frame. The exception was caught by the framework and logged rather
        // than crashing, which is why it showed up as endless console noise
        // instead of a visible failure.
        child: const SizedBox(
          width: 13,
          height: 13,
          child: CustomPaint(painter: _BusyRingPainter()),
        ),
      ),
    );
  }
}

/// The busy mark: a faint ring with one brighter quadrant, so "working" reads
/// as a SHAPE that rotates rather than as a colour change — the same rule the
/// rest of the kit follows, and the reason this is not just a tinted circle.
class _BusyRingPainter extends CustomPainter {
  const _BusyRingPainter();

  static const double _stroke = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(_stroke / 2);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = AnalogColor.inkFaint;
    canvas.drawOval(inset, ring);
    // A quarter turn of brighter ink, starting at twelve o'clock. Rotated by
    // the RotationTransition above, so this painter itself is static and
    // repaints only when its size changes.
    canvas.drawArc(
      inset,
      -math.pi / 2,
      math.pi / 2,
      false,
      ring
        ..color = AnalogColor.inkDim
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BusyRingPainter oldDelegate) => false;
}

@immutable
class _AnalogButtonSkin {
  const _AnalogButtonSkin({
    required this.fill,
    required this.ink,
    required this.line,
    required this.lineWidth,
    required this.glow,
  });

  final Color fill;
  final Color ink;
  final Color line;

  /// Zero means no border at all, which is now the common case: tone is carried
  /// by fill and ink, and a hairline on every control was most of what made
  /// them read as little cards.
  final double lineWidth;

  /// Pools light under itself while being reached. Primary only.
  final bool glow;

  static _AnalogButtonSkin resolve(
    AnalogButtonTone tone,
    AnalogControlState s,
  ) {
    if (!s.enabled) {
      // Disabled is a flat wash and faint ink — no frame, because a frame is
      // the thing that says "press me".
      return const _AnalogButtonSkin(
        fill: AnalogColor.stageSurface,
        ink: AnalogColor.inkFaint,
        line: AnalogColor.line,
        lineWidth: 0,
        glow: false,
      );
    }
    return switch (tone) {
      // Solid ink, no frame. It is the brightest thing on the stage; a border
      // around it would be a border around a light bulb.
      AnalogButtonTone.primary => const _AnalogButtonSkin(
        fill: AnalogColor.accent,
        ink: AnalogColor.onAccent,
        line: AnalogColor.accent,
        lineWidth: 0,
        glow: true,
      ),
      // Tonal: a filled pill one step off the stage, no frame. This is the
      // quiet default, and quiet should mean "less", not "same shape with a
      // thinner line".
      AnalogButtonTone.secondary => const _AnalogButtonSkin(
        fill: AnalogColor.stageSurface2,
        ink: AnalogColor.ink,
        line: AnalogColor.line,
        lineWidth: 0,
        glow: false,
      ),
      AnalogButtonTone.ghost => _AnalogButtonSkin(
        fill: const Color(0x00000000),
        ink: s.lit ? AnalogColor.ink : AnalogColor.inkDim,
        line: const Color(0x00000000),
        lineWidth: 0,
        glow: false,
      ),
      // The one control that keeps a frame. Destructive has to stay legible
      // with the colour taken away — in greyscale this is the only button on
      // the surface with an outline, and that is the whole point of it.
      AnalogButtonTone.danger => const _AnalogButtonSkin(
        fill: AnalogColor.stageSurface2,
        ink: AnalogColor.statusDanger,
        line: AnalogColor.statusDanger,
        lineWidth: AnalogPoster.framePx,
        glow: false,
      ),
    };
  }

  static _AnalogButtonSkin resolveIcon(
    AnalogIconButtonTone tone,
    AnalogControlState s,
  ) {
    const transparent = Color(0x00000000);
    if (!s.enabled) {
      return _AnalogButtonSkin(
        fill:
            tone == AnalogIconButtonTone.solid ||
                tone == AnalogIconButtonTone.primary
            ? AnalogColor.stageSurface
            : transparent,
        ink: AnalogColor.inkFaint,
        line: AnalogColor.line,
        lineWidth: tone == AnalogIconButtonTone.outline
            ? AnalogPoster.framePx
            : 0,
        glow: false,
      );
    }
    return switch (tone) {
      AnalogIconButtonTone.ghost => _AnalogButtonSkin(
        fill: transparent,
        ink: s.lit ? AnalogColor.ink : AnalogColor.inkDim,
        line: transparent,
        lineWidth: 0,
        glow: false,
      ),
      AnalogIconButtonTone.outline => _AnalogButtonSkin(
        fill: transparent,
        ink: s.lit ? AnalogColor.ink : AnalogColor.inkDim,
        line: s.lit ? AnalogColor.lineStrong : AnalogColor.line,
        lineWidth: AnalogPoster.framePx,
        glow: false,
      ),
      AnalogIconButtonTone.solid => const _AnalogButtonSkin(
        fill: AnalogColor.stageSurface2,
        ink: AnalogColor.ink,
        line: AnalogColor.line,
        lineWidth: 0,
        glow: false,
      ),
      AnalogIconButtonTone.primary => const _AnalogButtonSkin(
        fill: AnalogColor.accent,
        ink: AnalogColor.onAccent,
        line: AnalogColor.accent,
        lineWidth: 0,
        glow: true,
      ),
    };
  }
}
