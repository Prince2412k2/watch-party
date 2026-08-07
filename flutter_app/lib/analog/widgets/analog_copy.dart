// The copy block's arrival, weighted by type size.
//
// Three surfaces now show the same block of text following the same cursor —
// the Movies stage, the Shows stage, and the title detail page once a show's
// episodes became a rail. They were each about to grow a private copy of this
// widget, and three copies of a motion rule is three chances for one of them
// to drift into a slightly different feel for no reason anybody could name.

import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import '../type_mass.dart';

/// One line of copy, arriving with the weight its type size implies.
///
/// Heavier text takes a later slice of the shared entry and travels further,
/// so the block assembles from its lightest parts to its heaviest instead of
/// appearing all at once. See `analog/type_mass.dart` for the law.
///
/// Every line in a block must ride ONE [entry] controller. Separate
/// controllers drift, and then there is nothing holding the block together.
class AnalogWeightedLine extends StatelessWidget {
  const AnalogWeightedLine({
    super.key,
    required this.entry,
    required this.fontSizePx,
    required this.child,
    this.direction = 1,
    this.velocity = 0,
  });

  /// The block's shared arrival, 0..1.
  final Animation<double> entry;

  /// The line's own type size, which is what makes it heavy or light.
  final double fontSizePx;

  /// Which way the cursor moved, so the copy comes in from that side.
  final int direction;

  /// 0..1 — how hard the row is being pushed, which sets how far the copy
  /// travels. A fast scroll throws the text as far as the posters.
  final double velocity;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final slice = typeSettleInterval(fontSizePx);

    // Two curves over the same slice, and they must stay two.
    //
    // The travel overshoots — it carries past its mark and comes back, the
    // same elasticity the rail settles with, so the text has weight rather
    // than gliding to a stop. The fade cannot: an overshooting curve returns
    // values above 1, and FadeTransition asserts on an opacity above 1. So the
    // fade rides the plain slice and only the position gets the spring.
    final fade = CurvedAnimation(parent: entry, curve: slice);
    final settle = CurvedAnimation(
      parent: entry,
      curve: Interval(slice.begin, slice.end, curve: AnalogMotion.settleEase),
    );

    final travel =
        (AnalogMotion.copySlidePct +
            (AnalogMotion.copySlideFastPct - AnalogMotion.copySlidePct) *
                velocity) /
        100 *
        typeTravelFactor(fontSizePx) *
        direction;

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(travel, 0),
          end: Offset.zero,
        ).animate(settle),
        child: child,
      ),
    );
  }
}
