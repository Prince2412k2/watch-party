import 'package:flutter/material.dart';

import '../analog_tokens.dart';
import '../palette.dart';
import 'wave_dots.dart';

/// A pill of icon-only actions that unrolls out from beside a round handle —
/// leftwards from the profile avatar in the top-right, upwards from the popcorn
/// button in the bottom-right.
///
/// Both corners used to open a labelled panel: a 250px dropdown card and a
/// 320px party sheet. Two different objects, two different shapes, on a stage
/// whose premise is that the artwork is the interface. They are one object now.
/// Everything a panel said in words this says in a glyph and a tooltip, which
/// is the trade: you lose the at-a-glance label and you get the stage back.
///
/// The direction is the caller's choice because the corner decides it — a tray
/// unrolling left from the bottom-right corner would run along the bottom edge
/// under the nav; one unrolling up gets clear air.
///
/// Callers own the handle and the [AnimationController]; this owns the reveal.
/// [Align] with a `widthFactor`/`heightFactor` pins the child's trailing edge
/// and lets the box grow the other way, so the pill appears to slide out from
/// under the handle rather than materialising beside it. The [ClipRect] is what
/// makes it a reveal and not a squash — the buttons keep their real size the
/// whole way and the tray's edge passes over them.
class IconTray extends StatelessWidget {
  const IconTray({
    super.key,
    required this.animation,
    required this.children,
    this.axis = Axis.horizontal,
    this.gap = 15,
  });

  final Animation<double> animation;

  /// Ordered away-from-handle first. The LAST child is the one nearest the
  /// handle — leftmost-to-rightmost when horizontal, top-to-bottom when
  /// vertical — and it is the one that emerges first.
  final List<Widget> children;

  /// Which way the tray unrolls. Horizontal grows leftwards from a handle on
  /// its right; vertical grows upwards from a handle beneath it.
  final Axis axis;

  /// Distance from the pill to the handle. Scaled by the reveal, so it collapses
  /// with the tray instead of leaving a permanent hole beside the handle when
  /// nothing is open.
  final double gap;

  /// Across the tray. Matches the handle so the pill reads as one object with
  /// it: [TrayButton] is [TrayButton.size] square, plus its margin, plus the
  /// tray's own cross padding.
  static const double thickness = 54;

  bool get _horizontal => axis == Axis.horizontal;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = AnalogMotion.drawerEase.transform(
          animation.value.clamp(0.0, 1.0),
        );
        final reveal = ClipRect(
          child: Align(
            alignment: _horizontal
                ? Alignment.centerRight
                : Alignment.bottomCenter,
            widthFactor: _horizontal ? t : null,
            heightFactor: _horizontal ? null : t,
            // Nothing to hit-test until it is fully out; without this the
            // part-open tray absorbs a click aimed at the artwork behind it.
            child: IgnorePointer(ignoring: t < 1, child: child),
          ),
        );

        // The drop shadow is cast from OUT HERE, around the clip, not from the
        // pill inside it.
        //
        // It used to be part of the pill's own decoration, which put it inside
        // the ClipRect — and a 34px blur clipped to the box that casts it is not
        // a shadow, it is a grey rectangle with hard edges, which is exactly
        // what showed up around the tray. The reveal has to clip the pill (that
        // is what makes it a reveal), so the shadow has to live outside the
        // thing being clipped.
        //
        // The gap to the handle moves out here with it: as the pill's margin it
        // sat inside the clip, so the shadow was being blurred into that band
        // and then cut off at its edge. Still scaled by the reveal out here, so
        // it goes on collapsing with the tray.
        final lead = gap * t;
        return Padding(
          padding: _horizontal
              ? EdgeInsets.only(right: lead)
              : EdgeInsets.only(bottom: lead),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AnalogRadius.pillPx),
              // Nothing is out yet at t == 0, and a zero-height box still casts
              // a blur — a shadow under a closed tray.
              boxShadow: t <= 0
                  ? const []
                  : [
                      BoxShadow(
                        color: wp.shadow,
                        blurRadius: 34,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
            child: reveal,
          ),
        );
      },
      child: _TrayAxis(
        axis: axis,
        child: Container(
          height: _horizontal ? thickness : null,
          width: _horizontal ? null : thickness,
          // Extra along the run of the pill, so the round caps do not crowd the
          // end buttons.
          padding: _horizontal
              ? const EdgeInsets.symmetric(horizontal: 9, vertical: 3)
              : const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
          // The gap to the handle is the builder's padding now — see the note
          // on the shadow there.
          decoration: BoxDecoration(
            color: wp.surface,
            borderRadius: BorderRadius.circular(AnalogRadius.pillPx),
            border: Border.all(color: wp.line),
          ),
          child: Flex(
            direction: axis,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++)
                // Overlapping action: the far end of the tray is still catching
                // up while the near end has arrived. A tray whose contents all
                // land together reads as a printed sheet; this reads as a thing
                // being pulled out.
                _Lagged(
                  animation: animation,
                  axis: axis,
                  // Counted from the handle, because that is the end that
                  // emerges first.
                  slot: children.length - 1 - i,
                  slots: children.length,
                  child: children[i],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carries the tray's direction down to [TrayButton] and [TrayDivider] so a
/// caller never has to pass it twice and the two can never disagree.
class _TrayAxis extends InheritedWidget {
  const _TrayAxis({required this.axis, required super.child});

  final Axis axis;

  static Axis of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TrayAxis>()?.axis ??
      Axis.horizontal;

  @override
  bool updateShouldNotify(_TrayAxis old) => old.axis != axis;
}

/// Fades and slides one tray child in behind the tray's own edge, delayed by
/// its distance from the handle.
class _Lagged extends StatelessWidget {
  const _Lagged({
    required this.animation,
    required this.axis,
    required this.slot,
    required this.slots,
    required this.child,
  });

  final Animation<double> animation;
  final Axis axis;
  final int slot;
  final int slots;
  final Widget child;

  /// Share of the travel given over to the stagger. The rest is the child's own
  /// move, so even the last one out still gets most of the clock.
  static const double _stagger = 0.4;

  /// How far back each child starts, along the tray's own direction — so a
  /// vertical tray's buttons rise, they do not drift in sideways. Scaled with
  /// the buttons: a 14px slide under a 90px glyph reads as a twitch.
  static const double _travel = 21;

  @override
  Widget build(BuildContext context) {
    final start = slots < 2 ? 0.0 : _stagger * (slot / (slots - 1));
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, 1, curve: AnalogMotion.drawerEase),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final back = _travel * (1 - curved.value);
        return Opacity(
          // Chrome, so the curve does not overshoot and this stays in range —
          // but clamped anyway, because an opacity above 1 is not a look, it is
          // an assertion failure.
          opacity: curved.value.clamp(0.0, 1.0),
          child: Transform.translate(
            // Positive on both axes: the handle is to the right of a horizontal
            // tray and below a vertical one, so "back towards the handle" is
            // right and down respectively.
            offset: axis == Axis.horizontal ? Offset(back, 0) : Offset(0, back),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// One icon action. Square, so it sits the same in a tray running either way,
/// with an M3 state layer rather than a fill swap — every button in every tray
/// responds identically.
class TrayButton extends StatefulWidget {
  const TrayButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.tint,
    this.badge = false,
    this.busy = false,
    this.progress,
  });

  /// Square. [IconTray.thickness] is derived from it.
  static const double size = 45;

  /// The glyph inside it.
  static const double iconSize = 24;

  final IconData icon;

  /// The label the panel used to print. It is the only text left, and it is the
  /// whole reason removing the labels is not lossy — write it as the sentence
  /// the button would have said.
  final String tooltip;

  final VoidCallback? onTap;
  final Color? tint;

  /// A dot in the corner — something is waiting here.
  final bool badge;

  /// Dims the button and refuses taps while a request is in flight.
  ///
  /// Deliberately NOT a spinner. An indeterminate progress indicator never
  /// stops animating, and this control is mounted on every shelled screen —
  /// so a tray that happened to be busy pinned the compositor and, worse, hung
  /// `pumpAndSettle` in three tests that only wanted to boot the app.
  final bool busy;

  /// Fraction done, 0..1, when the work in flight can say how far along it is.
  ///
  /// Shown as a live percentage in place of the glyph, with a ring around it.
  /// [busy] alone renders an ellipsis, which is honest for work of unknown
  /// length and useless for a download — the figure was reachable only by
  /// hovering for a tooltip, so the one control that knew how far along it was
  /// made you ask. Still no indeterminate animation: the ring is drawn to a
  /// value, so it settles.
  final double? progress;

  @override
  State<TrayButton> createState() => _TrayButtonState();
}

class _TrayButtonState extends State<TrayButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final enabled = widget.onTap != null && !widget.busy;
    final color = enabled ? (widget.tint ?? wp.text) : wp.dim;
    final layer = !enabled
        ? 0.0
        : _down
        ? AnalogStateLayer.pressedPct
        : _hover
        ? AnalogStateLayer.hoverPct
        : 0.0;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      // A vertical tray is a column of buttons; a tooltip below one covers the
      // next. Put it to the side instead.
      preferBelow: _TrayAxis.of(context) == Axis.horizontal,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AnalogMotion.chromeFadeMs,
            curve: AnalogMotion.chromeFadeEase,
            width: TrayButton.size,
            height: TrayButton.size,
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              // The state layer washes the CONTAINER, composited under the
              // glyph — so a hovered button lightens without its icon shifting
              // colour along with it.
              color: color.withValues(alpha: layer / 100),
              borderRadius: BorderRadius.circular(AnalogRadius.pillPx),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (widget.progress != null)
                  _Percent(value: widget.progress!, color: color)
                else if (widget.busy)
                  // Work of unknown length, in flight. This was
                  // `Icons.more_horiz` — a motionless three dots, which is the
                  // same picture whether the request left a second ago or the
                  // server stopped answering, so the button said "wait" without
                  // ever saying "still going".
                  //
                  // Still not a CircularProgressIndicator. That is what the
                  // ellipsis replaced: an indeterminate spinner pinned the
                  // compositor and hung `pumpAndSettle` in three tests that
                  // only wanted to boot the app, because this control is
                  // mounted on every shelled screen. WaveDots has the same
                  // never-settling property, so the bound that matters is
                  // unchanged and worth restating: it is mounted ONLY while
                  // busy, and busy is only ever true across an in-flight
                  // request.
                  WaveDots(color: color, dotSize: 4.5, amplitude: 2.5)
                else
                  Icon(widget.icon, size: TrayButton.iconSize, color: color),
                if (widget.badge)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: kBrandRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline across the tray, so "act on the room" and "leave the room" do not
/// read as the same list. Lies across the run, whichever way the tray runs.
class TrayDivider extends StatelessWidget {
  const TrayDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final horizontal = _TrayAxis.of(context) == Axis.horizontal;
    return Container(
      width: horizontal ? 1 : 24,
      height: horizontal ? 24 : 1,
      margin: horizontal
          ? const EdgeInsets.symmetric(horizontal: 6)
          : const EdgeInsets.symmetric(vertical: 6),
      color: context.wp.line2,
    );
  }
}

/// A live percentage inside a determinate ring — the tray's answer to "how far
/// along is it". Sized to sit in the same square a glyph does.
class _Percent extends StatelessWidget {
  const _Percent({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (value.clamp(0.0, 1.0) * 100).round();
    return SizedBox.square(
      dimension: TrayButton.iconSize + 6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Determinate, so it has an end state and never spins forever.
          Positioned.fill(
            child: CircularProgressIndicator(
              value: value.clamp(0.0, 1.0),
              strokeWidth: 2,
              backgroundColor: color.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '$pct',
            style: TextStyle(
              fontFamily: AnalogType.monoFamily,
              color: color,
              // Two or three digits inside a 30px ring; tabular so the figure
              // does not jitter sideways as it counts up.
              fontSize: pct >= 100 ? 8.5 : 10,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
