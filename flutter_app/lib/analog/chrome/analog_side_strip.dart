import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';
import 'analog_pressable.dart';

/// The vertical position picker that lives down the right side of a stage:
/// Season 1 / Season 2 / … on a show, Singles / Collections on the movie
/// library. Plain text positions, each carrying its own detent rule.
///
/// It exists as one widget because there used to be two, a stage apart, with a
/// comment on each saying it was written to read like the other. They agreed on
/// the day they were written and then drifted — same face, different home:
/// the season picker sat centred in a tall aside where it reads as one of the
/// page's controls, while the movie one was pinned to the top corner at the
/// same small size and read as a label someone had left there. Size and
/// alignment are now decided here, once.
///
/// Not a segmented control or a pill: those are Material's idiom for a choice
/// between adjacent options, and this is a wheel — the rail scrolls under a
/// fixed cursor, and this says which track it is on.
class AnalogSideStrip extends StatelessWidget {
  const AnalogSideStrip({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.fontSize = defaultFontSize,
  });

  /// The positions, top to bottom, as `(value, label)`.
  final List<({String label, Object value})> options;

  /// Which one is current — matched by `==` against each option's value.
  final Object? selected;

  final ValueChanged<Object> onSelected;

  final double fontSize;

  /// Big enough to be read as a control from across a room, which is the size
  /// this is used at. Both stages take the default; the parameter exists so a
  /// cramped window can step it down rather than clip.
  static const double defaultFontSize = 19;

  /// The gap between positions, scaled with the type so the strip keeps its
  /// rhythm at any size.
  double get _gap => fontSize * 0.75;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          AnalogSideStripPosition(
            label: options[i].label,
            active: options[i].value == selected,
            fontSize: fontSize,
            onPressed: () => onSelected(options[i].value),
          ),
          if (i != options.length - 1) SizedBox(height: _gap),
        ],
      ],
    );
  }
}

/// One position on the strip. Public because the season picker builds its rows
/// from richer data than a `(value, label)` pair and only wants the paint.
class AnalogSideStripPosition extends StatelessWidget {
  const AnalogSideStripPosition({
    super.key,
    required this.label,
    required this.active,
    required this.onPressed,
    this.fontSize = AnalogSideStrip.defaultFontSize,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return AnalogPressable(
      onPressed: onPressed,
      semanticLabel: label,
      selected: active,
      button: false,
      builder: (context, state) => AnalogFocusRing(
        visible: state.focused,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AnalogSpace.smPx,
            vertical: AnalogSpace.xsPx,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: AnalogType.sansFamily,
                  fontSize: fontSize,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active || state.lit
                      ? AnalogColor.ink
                      : AnalogColor.inkFaint,
                ),
              ),
              SizedBox(height: fontSize * 0.2),
              // The detent, not a tint: the active position is marked by
              // geometry so it survives a monochrome display. It grows with the
              // type, so the mark stays proportional to the word it underlines.
              AnimatedContainer(
                duration: AnalogMotion.detentMs,
                curve: AnalogMotion.detentEase,
                height: active
                    ? AnalogHairline.activePx
                    : AnalogHairline.idlePx,
                width: active ? fontSize * 2.3 : fontSize,
                color: active ? AnalogColor.ink : AnalogColor.line,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
