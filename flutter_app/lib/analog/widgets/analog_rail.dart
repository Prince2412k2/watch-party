// The fixed-cursor rail widget.
//
// "Our selection cursor will always be the first position. The whole row will
// move when we scroll or move it, and it will snap the movie/show in place."
//
// Every number this draws comes from movie_rail.dart, which is a pure port of
// the web's. The widget's only job is to turn `railCursor` into a translated
// track and to route input into `stepRailSelection`. It derives no geometry of
// its own — that is what keeps the two clients showing the same items for the
// same selection.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/analog_tokens.dart';
import '../movie_rail.dart';
import '../stage_layout.dart';
import 'analog_poster.dart';

/// One title on the rail. Deliberately not a Jellyfin item: the rail is also
/// used by Discover and Downloads, whose items come from other services.
@immutable
class AnalogRailItem {
  const AnalogRailItem({
    required this.id,
    required this.label,
    this.imageUrl,
    this.subtitle,
    this.badge,
    this.progress,
    this.placeholderLabel,
  });

  final String id;
  final String label;
  final String? imageUrl;
  final String? subtitle;
  final String? badge;

  /// 0..1 watch progress.
  final double? progress;
  final String? placeholderLabel;
}

/// A row whose cursor does not move.
///
/// The cursor sits in the leftmost slot and the track slides underneath it,
/// except at the tail of the rail where the row has run out of travel and the
/// cursor walks the last page itself — see [railCursor].
class AnalogRail extends StatefulWidget {
  const AnalogRail({
    super.key,
    required this.items,
    required this.selection,
    required this.onSelect,
    required this.onActivate,
    required this.size,
    this.motion,
    this.onEscape,
    this.onCrossAxis,
    this.autofocus = false,
    this.emptyLabel = 'Nothing here yet',
  });

  final List<AnalogRailItem> items;

  /// The single source of position. "Which item is selected" and "how far the
  /// row has scrolled" are the same number.
  final int selection;

  final ValueChanged<int> onSelect;
  final ValueChanged<int> onActivate;
  final StageSize size;
  final MotionProfile? motion;

  final VoidCallback? onEscape;

  /// Up/Down leave the rail — on the Movies stage they drive the
  /// Singles/Collections slider, which is the stage's business, not the rail's.
  final ValueChanged<int>? onCrossAxis;

  final bool autofocus;
  final String emptyLabel;

  @override
  State<AnalogRail> createState() => _AnalogRailState();
}

class _AnalogRailState extends State<AnalogRail> {
  /// Wheel deltas arrive in bursts and must not be laundered into a jump: one
  /// notch is one step, and the remainder is dropped rather than accumulated
  /// into a second step on the next event.
  static const double _wheelThreshold = 24;
  double _wheelAccum = 0;

  void _step(int direction) {
    final next = stepRailSelection(
      widget.selection,
      widget.items.length,
      direction,
    );
    if (next != widget.selection) widget.onSelect(next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _step(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _step(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        widget.onCrossAxis?.call(-1);
        return widget.onCrossAxis == null
            ? KeyEventResult.ignored
            : KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        widget.onCrossAxis?.call(1);
        return widget.onCrossAxis == null
            ? KeyEventResult.ignored
            : KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.gameButtonA:
        if (widget.items.isNotEmpty) widget.onActivate(widget.selection);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.backspace:
        widget.onEscape?.call();
        return widget.onEscape == null
            ? KeyEventResult.ignored
            : KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // A trackpad's horizontal axis and a mouse wheel's vertical one both drive
    // the rail: on a row, "scroll" means along it whichever axis the hardware
    // reports.
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    _wheelAccum += delta;
    if (_wheelAccum.abs() < _wheelThreshold) return;
    _step(_wheelAccum.sign.toInt());
    _wheelAccum = 0;
  }

  @override
  Widget build(BuildContext context) {
    final motion = widget.motion ?? motionProfile(false);

    if (widget.items.isEmpty) {
      return _EmptyRail(label: widget.emptyLabel, size: widget.size);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = railMetrics(constraints.maxWidth, widget.size);
        final cursor = railCursor(
          total: widget.items.length,
          selection: widget.selection,
          slots: metrics.slots,
        );
        final rendered = railRendered(cursor);
        final step = railStepPx(metrics.posterWidthPx, metrics.gapPx);
        final translate = railTranslatePx(
          cursor.start,
          metrics.posterWidthPx,
          metrics.gapPx,
        );

        final artHeight = AnalogPosterTile.artHeightFor(metrics.posterWidthPx);
        // Uniform slots: size for the tallest caption any item needs, so a
        // single subtitled title does not make its own slot taller than the
        // row around it.
        final anySubtitle = widget.items.any((i) => i.subtitle != null);
        final railHeight =
            artHeight + AnalogPosterTile.captionHeight(subtitle: anySubtitle);

        return Focus(
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: SizedBox(
              height: railHeight,
              // The track is wider than the viewport by design; clipping is
              // what makes the row read as sliding under a fixed cursor
              // rather than as a list that reflows.
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Only the rendered range is mounted — visible plus the
                    // warmed neighbours, so the poster arriving under the
                    // cursor was laid out and decoded a step ago.
                    for (final index in rendered)
                      AnimatedPositioned(
                        key: ValueKey(widget.items[index].id),
                        duration: motion.focusStep,
                        curve: AnalogMotion.focusStepEase,
                        left: index * step + translate,
                        top: 0,
                        width: metrics.posterWidthPx,
                        height: railHeight,
                        child: _RailSlot(
                          item: widget.items[index],
                          width: metrics.posterWidthPx,
                          focused: index == widget.selection,
                          motion: motion,
                          onTap: () => index == widget.selection
                              ? widget.onActivate(index)
                              : widget.onSelect(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RailSlot extends StatelessWidget {
  const _RailSlot({
    required this.item,
    required this.width,
    required this.focused,
    required this.motion,
    required this.onTap,
  });

  final AnalogRailItem item;
  final double width;
  final bool focused;
  final MotionProfile motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnalogPosterTile(
      imageUrl: item.imageUrl,
      title: item.label,
      subtitle: item.subtitle,
      placeholderLabel: item.placeholderLabel,
      width: width,
      focused: focused,
      progress: item.progress,
      onTap: onTap,
    );
  }
}

class _EmptyRail extends StatelessWidget {
  const _EmptyRail({required this.label, required this.size});

  final String label;
  final StageSize size;

  @override
  Widget build(BuildContext context) {
    // An empty rail says so rather than collapsing to nothing, which is
    // indistinguishable from a surface that failed to load.
    final metrics = railMetrics(400, size);
    return SizedBox(
      height:
          AnalogPosterTile.artHeightFor(metrics.posterWidthPx) +
          AnalogPosterTile.captionHeight(),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AnalogType.sansFamily,
            fontSize: 13,
            color: AnalogColor.inkFaint,
          ),
        ),
      ),
    );
  }
}
