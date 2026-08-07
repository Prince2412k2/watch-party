import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import 'analog_pressable.dart';
import 'analog_tooltip.dart';

/// What a button is for, not what colour it is.
///
/// - [primary]  the one affordance on the surface that the user came for.
/// - [secondary] the quiet default: a surface plate with a hairline frame.
/// - [ghost]    text on the stage, no plate until it is reached.
/// - [danger]   destructive. Carries the reserved red *and* a doubled frame, so
///              it still reads as different with the colour taken away.
enum AnalogButtonTone { primary, secondary, ghost, danger }

/// A rectangular chrome control on the analog tokens.
///
/// Square-ish by [AnalogRadius.chromePx] — 4px, the chrome radius, never the
/// poster radius. Light comes from above-left exactly as it does on artwork
/// ([AnalogSelection.sceneLightAngleDeg]), so the top and left edges carry
/// [AnalogColor.edgeLight] and the cast shadow falls below-right. Pressing sinks
/// the plate into its own shadow; nothing bounces.
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
      child: AnimatedContainer(
        duration: AnalogMotion.chromeFadeMs,
        curve: AnalogMotion.chromeFadeEase,
        // A press drops the plate onto its shadow rather than scaling it: short
        // travel, clear detent, no bounce (AnalogMotion §mechanical).
        transform: Matrix4.translationValues(0, state.pressed ? 1 : 0, 0),
        constraints: const BoxConstraints(minHeight: 38),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? AnalogSpace.mdPx : AnalogSpace.lgPx,
          vertical: AnalogSpace.smPx + 2,
        ),
        decoration: BoxDecoration(
          color: analogStateLayerOver(skin.fill, state),
          borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
          border: Border.all(color: skin.line, width: skin.lineWidth),
          boxShadow: skin.raised && !state.pressed
              ? const [
                  BoxShadow(
                    color: AnalogColor.shadowCast,
                    blurRadius: AnalogElevation.restBlurPx,
                    offset: Offset(
                      AnalogElevation.restOffsetXPx,
                      AnalogElevation.restOffsetYPx,
                    ),
                  ),
                ]
              : const [],
        ),
        child: _EdgeLit(
          lit: skin.raised && !state.pressed,
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
            inset: 4,
            child: AnimatedContainer(
              duration: AnalogMotion.chromeFadeMs,
              curve: AnalogMotion.chromeFadeEase,
              transform: Matrix4.translationValues(0, state.pressed ? 1 : 0, 0),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: analogStateLayerOver(skin.fill, state),
                borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
                border: Border.all(color: skin.line, width: skin.lineWidth),
              ),
              child: Center(child: Icon(icon, size: iconSize, color: glyph)),
            ),
          );
        },
      ),
    );
  }
}

/// Plate treatment for [AnalogIconButton]: [ghost] has none until reached,
/// [outline] always carries a hairline frame, [solid] always carries a plate.
enum AnalogIconButtonTone { ghost, outline, solid }

/// The directional edge light, on chrome.
///
/// The scene light is at [AnalogSelection.sceneLightAngleDeg] (315deg, above
/// left), so a raised plate catches it on its top and left edges while the cast
/// shadow falls below-right. Same story as the artwork frame in
/// `analog_poster.dart`, told with a border instead of a painter because chrome
/// plates are small and their corners are rounded.
class _EdgeLit extends StatelessWidget {
  const _EdgeLit({required this.lit, required this.child});

  final bool lit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!lit) return child;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AnalogColor.edgeLight,
            width: AnalogPoster.framePx,
          ),
          left: BorderSide(
            color: AnalogColor.edgeLight,
            width: AnalogPoster.framePx,
          ),
        ),
      ),
      position: DecorationPosition.foreground,
      child: child,
    );
  }
}

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
        child: const SizedBox(
          width: 13,
          height: 13,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AnalogColor.inkDim, width: 2),
                left: BorderSide(color: AnalogColor.inkFaint, width: 2),
                right: BorderSide(color: AnalogColor.inkFaint, width: 2),
                bottom: BorderSide(color: AnalogColor.inkFaint, width: 2),
              ),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class _AnalogButtonSkin {
  const _AnalogButtonSkin({
    required this.fill,
    required this.ink,
    required this.line,
    required this.lineWidth,
    required this.raised,
  });

  final Color fill;
  final Color ink;
  final Color line;
  final double lineWidth;
  final bool raised;

  static _AnalogButtonSkin resolve(
    AnalogButtonTone tone,
    AnalogControlState s,
  ) {
    if (!s.enabled) {
      // Disabled drops the plate flat and takes the frame down with the ink, so
      // the control reads as inert by depth as well as by contrast.
      return const _AnalogButtonSkin(
        fill: AnalogColor.stageSurface,
        ink: AnalogColor.inkFaint,
        line: AnalogColor.line,
        lineWidth: AnalogPoster.framePx,
        raised: false,
      );
    }
    return switch (tone) {
      AnalogButtonTone.primary => _AnalogButtonSkin(
        fill: AnalogColor.accent,
        ink: AnalogColor.onAccent,
        line: AnalogColor.accent,
        lineWidth: AnalogPoster.framePx,
        raised: true,
      ),
      AnalogButtonTone.secondary => _AnalogButtonSkin(
        fill: AnalogColor.stageSurface2,
        ink: AnalogColor.ink,
        line: s.lit ? AnalogColor.lineStrong : AnalogColor.line,
        lineWidth: AnalogPoster.framePx,
        raised: true,
      ),
      AnalogButtonTone.ghost => _AnalogButtonSkin(
        fill: const Color(0x00000000),
        ink: s.lit ? AnalogColor.ink : AnalogColor.inkDim,
        line: s.lit ? AnalogColor.line : const Color(0x00000000),
        lineWidth: AnalogPoster.framePx,
        raised: false,
      ),
      // The doubled frame is what makes danger legible without the red.
      AnalogButtonTone.danger => _AnalogButtonSkin(
        fill: AnalogColor.stageSurface2,
        ink: AnalogColor.statusDanger,
        line: AnalogColor.statusDanger,
        lineWidth: AnalogPoster.framePx * 2,
        raised: true,
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
        fill: tone == AnalogIconButtonTone.solid
            ? AnalogColor.stageSurface
            : transparent,
        ink: AnalogColor.inkFaint,
        line: tone == AnalogIconButtonTone.ghost
            ? transparent
            : AnalogColor.line,
        lineWidth: AnalogPoster.framePx,
        raised: false,
      );
    }
    return switch (tone) {
      AnalogIconButtonTone.ghost => _AnalogButtonSkin(
        fill: transparent,
        ink: s.lit ? AnalogColor.ink : AnalogColor.inkDim,
        line: transparent,
        lineWidth: AnalogPoster.framePx,
        raised: false,
      ),
      AnalogIconButtonTone.outline => _AnalogButtonSkin(
        fill: transparent,
        ink: s.lit ? AnalogColor.ink : AnalogColor.inkDim,
        line: s.lit ? AnalogColor.lineStrong : AnalogColor.line,
        lineWidth: AnalogPoster.framePx,
        raised: false,
      ),
      AnalogIconButtonTone.solid => _AnalogButtonSkin(
        fill: AnalogColor.stageSurface2,
        ink: AnalogColor.ink,
        line: s.lit ? AnalogColor.lineStrong : AnalogColor.line,
        lineWidth: AnalogPoster.framePx,
        raised: true,
      ),
    };
  }
}
