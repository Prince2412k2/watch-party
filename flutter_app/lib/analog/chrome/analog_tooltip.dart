import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';

/// A hover/long-press label on the analog surface ramp.
///
/// Deliberately built on Material's [Tooltip] rather than hand-rolled: the
/// overlay placement, the pointer-exit bookkeeping and the long-press trigger
/// for touch are exactly the plumbing this app should not be reimplementing,
/// and only the paint was ever wrong.
///
/// A tooltip is never the only place a control's name appears — every control
/// in this kit also carries the string as its [Semantics] label — so this stays
/// on the right side of the reference's "No hover-only controls" guardrail.
/// [excludeFromSemantics] is on for that reason: the label is already announced
/// by the control itself, and announcing it twice is worse than not at all.
class AnalogTooltip extends StatelessWidget {
  const AnalogTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 420),
      preferBelow: false,
      padding: const EdgeInsets.symmetric(
        horizontal: AnalogSpace.smPx,
        vertical: AnalogSpace.xsPx + 2,
      ),
      margin: const EdgeInsets.all(AnalogSpace.xsPx),
      decoration: BoxDecoration(
        color: AnalogColor.stageSurface2,
        borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
        border: Border.all(color: AnalogColor.line),
        boxShadow: const [
          BoxShadow(
            color: AnalogColor.shadowCast,
            blurRadius: AnalogElevation.restBlurPx,
            offset: Offset(
              AnalogElevation.restOffsetXPx,
              AnalogElevation.restOffsetYPx,
            ),
          ),
        ],
      ),
      textStyle: const TextStyle(
        fontFamily: AnalogType.sansFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AnalogColor.ink,
      ),
      child: child,
    );
  }
}
