import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import 'analog_pressable.dart';

/// A two-position mechanical switch.
///
/// The knob travels between two hard stops on [AnalogMotion.detentMs] — short
/// travel, clear detent, no bounce. **Position** is the state signal; the fill
/// only reinforces it. That is deliberate and testable: with every colour in
/// the widget collapsed to one value, the knob is still on the left when off
/// and on the right when on.
///
/// Operable from the keyboard three ways: Enter/Space toggle, and the arrow
/// keys set the switch directly so a remote's left/right does the obvious
/// thing.
class AnalogSwitch extends StatelessWidget {
  const AnalogSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;

  /// Null disables the switch — it stops taking focus, hover and keys together.
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  static const double _trackWidth = 44;
  static const double _trackHeight = 24;
  static const double _knob = 18;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (value) onChanged!(false);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (!value) onChanged!(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnalogPressable(
        onPressed: enabled ? () => onChanged!(!value) : null,
        semanticLabel: semanticLabel,
        toggled: value,
        button: false,
        builder: (context, state) => AnalogFocusRing(
          visible: state.focused,
          inset: 2,
          child: SizedBox(
            // The visible track is 24px tall; the hit target is the 44x36 box
            // around it, comfortably past AnalogHairline.hitPx.
            width: _trackWidth,
            height: 36,
            child: Center(
              child: AnimatedContainer(
                duration: AnalogMotion.detentMs,
                curve: AnalogMotion.detentEase,
                width: _trackWidth,
                height: _trackHeight,
                padding: const EdgeInsets.all(2),
                alignment: value
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: !state.enabled
                      ? AnalogColor.stageGround
                      : analogStateLayerOver(
                          value
                              ? AnalogColor.stageSurface3
                              : AnalogColor.stageSurface,
                          state,
                        ),
                  borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
                  border: Border.all(
                    color: !state.enabled
                        ? AnalogColor.line
                        : (state.lit
                              ? AnalogColor.lineStrong
                              : AnalogColor.line),
                  ),
                ),
                child: Container(
                  width: _knob,
                  height: _knob - 2,
                  decoration: BoxDecoration(
                    color: !state.enabled
                        ? AnalogColor.inkFaint
                        : (value ? AnalogColor.ink : AnalogColor.inkDim),
                    borderRadius: BorderRadius.circular(
                      AnalogRadius.chromePx - 2,
                    ),
                    boxShadow: state.enabled
                        ? const [
                            BoxShadow(
                              color: AnalogColor.shadowCast,
                              blurRadius: 6,
                              offset: Offset(1, 2),
                            ),
                          ]
                        : const [],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One option in an [AnalogSegmented].
@immutable
class AnalogSegment<T> {
  const AnalogSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// A segmented control — the kit's replacement for a button group of toggles.
///
/// Radio semantics: activating the already-selected segment is a no-op, so
/// there is no gesture that lands the control in an empty state.
///
/// The selected segment is marked three ways — a filled plate, a bolder label,
/// and the mechanical detent hairline underneath it, the same
/// [AnalogHairline.idlePx]/[AnalogHairline.activePx] pair the bottom-edge mode
/// strip uses. Colour is the least of them.
class AnalogSegmented<T> extends StatelessWidget {
  const AnalogSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<AnalogSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
          border: Border.all(color: AnalogColor.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++)
              _Segment<T>(
                key: ValueKey('analog-segment-${segments[i].value}'),
                segment: segments[i],
                selected: segments[i].value == value,
                first: i == 0,
                last: i == segments.length - 1,
                onPressed: onChanged == null
                    ? null
                    : () {
                        if (segments[i].value != value) {
                          onChanged!(segments[i].value);
                        }
                      },
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    super.key,
    required this.segment,
    required this.selected,
    required this.first,
    required this.last,
    required this.onPressed,
  });

  final AnalogSegment<T> segment;
  final bool selected;
  final bool first;
  final bool last;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnalogPressable(
      onPressed: onPressed,
      semanticLabel: segment.label,
      selected: selected,
      button: false,
      excludeSemantics: true,
      builder: (context, state) {
        final lit = state.lit || selected;
        return AnalogFocusRing(
          visible: state.focused,
          inset: 2,
          child: AnimatedContainer(
            duration: AnalogMotion.chromeFadeMs,
            curve: AnalogMotion.chromeFadeEase,
            constraints: const BoxConstraints(minHeight: 34, minWidth: 72),
            padding: const EdgeInsets.fromLTRB(
              AnalogSpace.mdPx,
              AnalogSpace.smPx,
              AnalogSpace.mdPx,
              AnalogSpace.smPx - 2,
            ),
            decoration: BoxDecoration(
              color: analogStateLayerOver(
                selected ? AnalogColor.stageSurface2 : const Color(0x00000000),
                state,
              ),
              border: Border(
                left: BorderSide(
                  color: first ? const Color(0x00000000) : AnalogColor.line,
                ),
              ),
            ),
            // The enclosing Row is min-size, so a segment is laid out with an
            // unbounded max width. IntrinsicWidth resolves the column to the
            // label's own width first, which is what lets the detent below
            // stretch to the segment instead of asking for infinity.
            child: IntrinsicWidth(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  segment.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AnalogType.sansFamily,
                    fontSize: 12.5,
                    letterSpacing: 0.3,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: lit ? AnalogColor.ink : AnalogColor.inkDim,
                  ),
                ),
                const SizedBox(height: AnalogSpace.xsPx),
                _SegmentDetent(active: selected),
              ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The detent under the current segment: a hairline that thickens and runs the
/// segment's full width, exactly as the bottom-edge mode strip's does.
class _SegmentDetent extends StatelessWidget {
  const _SegmentDetent({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: active ? 1 : 0),
      duration: AnalogMotion.detentMs,
      curve: AnalogMotion.detentEase,
      builder: (context, t, _) => SizedBox(
        height: AnalogHairline.activePx,
        child: Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            widthFactor: 0.2 + 0.8 * t,
            child: Container(
              height:
                  AnalogHairline.idlePx +
                  (AnalogHairline.activePx - AnalogHairline.idlePx) * t,
              color: Color.lerp(
                const Color(0x00000000),
                AnalogColor.ink,
                t,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
