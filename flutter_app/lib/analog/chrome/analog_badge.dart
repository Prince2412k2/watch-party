import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import 'analog_pressable.dart';

/// A small non-interactive label — a count, a status word, a role.
///
/// Two weights only: a filled plate ([AnalogBadge]) and a hairline frame
/// ([AnalogBadge.outline]). Both take their shape from [AnalogRadius.pillPx],
/// which the token file reserves for "buttons, sheets and toasts" — a badge is
/// chrome, and this radius must never reach a poster.
class AnalogBadge extends StatelessWidget {
  const AnalogBadge({super.key, required this.child, this.leading})
    : outlined = false;

  const AnalogBadge.outline({super.key, required this.child, this.leading})
    : outlined = true;

  final Widget child;
  final Widget? leading;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: AnalogSpace.smPx,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: outlined ? const Color(0x00000000) : AnalogColor.stageSurface2,
        borderRadius: BorderRadius.circular(AnalogRadius.pillPx),
        border: Border.all(
          color: outlined ? AnalogColor.lineStrong : AnalogColor.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AnalogSpace.xsPx + 2),
          ],
          DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamily: AnalogType.sansFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AnalogColor.ink,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A small label that can also be a filter.
///
/// When [onPressed] is null this is a label and reports itself to [Semantics]
/// as one; when it is set the chip is a focusable, Enter/Space-operable
/// control.
///
/// Selection is carried by three things at once — a filled plate, a heavier
/// hairline, and a bolder label — because "the focused item grows or otherwise
/// gains physical emphasis; selection must not rely on color alone"
/// (analog-interface-reference.md §Browsing model) is a property of the system,
/// not of the poster shelf.
class AnalogChip extends StatelessWidget {
  const AnalogChip({
    super.key,
    required this.label,
    this.leading,
    this.selected = false,
    this.onPressed,
    this.ink,
  });

  final String label;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onPressed;

  /// Overrides the label colour for the reserved status tones.
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) {
      return Semantics(
        label: label,
        selected: selected,
        child: ExcludeSemantics(child: _plate(_kInert)),
      );
    }
    return AnalogPressable(
      onPressed: onPressed,
      semanticLabel: label,
      selected: selected,
      excludeSemantics: true,
      builder: (context, state) => AnalogFocusRing(
        visible: state.focused,
        radius: AnalogRadius.chromePx,
        inset: 2,
        child: _plate(state),
      ),
    );
  }

  Widget _plate(AnalogControlState state) {
    final lit = state.lit;
    final labelInk =
        ink ??
        (selected || lit ? AnalogColor.ink : AnalogColor.inkDim);

    return AnimatedContainer(
      duration: AnalogMotion.chromeFadeMs,
      curve: AnalogMotion.chromeFadeEase,
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(
        horizontal: AnalogSpace.mdPx,
        vertical: AnalogSpace.xsPx,
      ),
      decoration: BoxDecoration(
        color: selected
            ? AnalogColor.stageSurface2
            : (lit ? AnalogColor.stageSurface : const Color(0x00000000)),
        borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
        border: Border.all(
          color: selected
              ? AnalogColor.lineStrong
              : (lit ? AnalogColor.lineStrong : AnalogColor.line),
          width: selected ? AnalogPoster.framePx * 2 : AnalogPoster.framePx,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AnalogSpace.xsPx + 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AnalogType.sansFamily,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: labelInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// A label chip is never reached, so it paints the resting state forever.
const AnalogControlState _kInert = AnalogControlState(
  enabled: true,
  hovered: false,
  focused: false,
  pressed: false,
);
