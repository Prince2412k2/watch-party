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
    this.heroTag,
  });

  final String id;
  final String label;
  final String? imageUrl;
  final String? subtitle;
  final String? badge;

  /// 0..1 watch progress.
  final double? progress;
  final String? placeholderLabel;

  /// Shared-element tag. Set to the tag the destination screen uses and the
  /// artwork flies across the route rather than cutting.
  final String? heroTag;
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
    this.maxHeightPx,
    this.hideSelected = false,
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

  /// Ceiling on the row's height, including the enlarged selection.
  ///
  /// Posters are sized from the available *width*, which on a short window
  /// produces a row taller than the stage has left after the details — the
  /// overflow this exists to prevent. Given a budget, the rail shrinks its
  /// posters to fit rather than pushing the layout past its bounds.
  final double? maxHeightPx;

  /// Suppress the selected poster's artwork, leaving its slot empty.
  ///
  /// Set while the stage is flying that poster out of the rail, so the title is
  /// not drawn twice in two places during the move.
  final bool hideSelected;

  @override
  State<AnalogRail> createState() => _AnalogRailState();
}

class _AnalogRailState extends State<AnalogRail> {
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

  @override
  Widget build(BuildContext context) {
    final motion = widget.motion ?? motionProfile(false);

    if (widget.items.isEmpty) {
      return _EmptyRail(label: widget.emptyLabel, size: widget.size);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final anySubtitle = widget.items.any((i) => i.subtitle != null);
        final metrics = analogRailMetrics(
          usableWidthPx: constraints.maxWidth,
          maxHeightPx: widget.maxHeightPx,
          size: widget.size,
          subtitle: anySubtitle,
        );

        final cursor = railCursor(
          total: widget.items.length,
          selection: widget.selection,
          slots: metrics.slots,
        );
        final rendered = railRendered(cursor);
        final trail = railTrailPx(metrics.posterWidthPx, metrics.gapPx);

        // Sized for the *selected* poster, which is the tallest thing in the
        // row. The rest bottom-align to it so their captions stay on one
        // baseline while only the artwork grows upward.
        final captionHeight = AnalogPosterTile.captionHeight(
          subtitle: anySubtitle,
        );
        // The selected tile is scaled twice: once by the rail's own falloff
        // (its width) and again by the tile's focus growth about its centre.
        // The row has to leave room for both or the caption is clipped.
        final selectedWidth = metrics.posterWidthPx * kRailSelectedScale;
        final railHeight =
            AnalogPosterTile.artHeightFor(selectedWidth) +
            captionHeight +
            AnalogPosterTile.focusOverflowFor(selectedWidth);

        return Focus(
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          // No wheel handling here on purpose. The stage listens for pointer
          // signals across its whole surface so scrolling works anywhere, and
          // a Listener here as well would see the same event and step twice.
          child: SizedBox(
              // Full width explicitly: the Stack below holds only positioned
              // children, so under loose constraints it would shrink-wrap to
              // nothing and the rail would silently vanish.
              width: double.infinity,
              height: railHeight,
              // The track is wider than the viewport by design; clipping is
              // what makes the row read as sliding under a fixed cursor
              // rather than as a list that reflows.
              child: ClipRect(
                child: _TrailFade(
                  trailPx: trail,
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Only the rendered range is mounted — visible plus the
                    // warmed neighbours, so the poster arriving under the
                    // cursor was laid out and decoded a step ago.
                    for (final index in rendered)
                      () {
                        final distance = index - widget.selection;
                        final width =
                            metrics.posterWidthPx * railScaleAt(distance);
                        return AnimatedPositioned(
                          key: ValueKey(widget.items[index].id),
                          duration: motion.focusStep,
                          curve: AnalogMotion.focusStepEase,
                          left:
                              trail +
                              railOffsetFor(
                                index,
                                widget.selection,
                                metrics.posterWidthPx,
                                metrics.gapPx,
                              ),
                          // Bottom-aligned: captions share a baseline and the
                          // selected poster grows upward out of the row.
                          bottom: 0,
                          width: width,
                          // Deliberately no height: the tile's column is
                          // mainAxisSize.min and knows its own intrinsic
                          // height, including whatever the focus treatment
                          // adds. Forcing a computed height here means
                          // re-deriving the tile's internals from outside it,
                          // and being 19px wrong clips the caption.
                          child: _RailSlot(
                          item: widget.items[index],
                          width: width,
                          focused: index == widget.selection,
                          hidden:
                              widget.hideSelected &&
                              index == widget.selection,
                          // Depth: what is ahead of the cursor is dimmed, what
                          // is behind it is dimmed harder. The selection is the
                          // only thing at full strength, which is what makes
                          // the row read as moving past a fixed point rather
                          // than as a flat strip of equals.
                          dim: index == widget.selection
                              ? 1
                              : index < widget.selection
                              ? _passedOpacity
                              : _aheadOpacity,
                          motion: motion,
                          onTap: () => index == widget.selection
                              ? widget.onActivate(index)
                              : widget.onSelect(index),
                        ),
                        );
                      }(),
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

/// Opacity for titles the cursor has already passed, and for those ahead of it.
const double _passedOpacity = 0.34;
const double _aheadOpacity = 0.62;

/// Height the row needs for [posterWidthPx], including the enlarged selection
/// and the room its focus growth wants above the caption baseline.
double analogRailHeight(double posterWidthPx, {bool subtitle = false}) {
  final selected = posterWidthPx * kRailSelectedScale;
  return AnalogPosterTile.artHeightFor(selected) +
      AnalogPosterTile.captionHeight(subtitle: subtitle) +
      AnalogPosterTile.focusOverflowFor(selected);
}

/// The rail's fitted geometry.
///
/// Public and shared rather than private to the widget because the Movies
/// stage has to know exactly where the selected poster sits: the select
/// transition flies that poster out of the rail, and a hero that starts a few
/// pixels off its source is the one thing that makes a shared-element move look
/// broken. Two copies of this arithmetic would be two chances to disagree.
RailMetrics analogRailMetrics({
  required double usableWidthPx,
  required double? maxHeightPx,
  required StageSize size,
  bool subtitle = false,
}) {
  final metrics = railMetrics(usableWidthPx, size);
  if (maxHeightPx == null || maxHeightPx <= 0) return metrics;

  // The row's height is linear in the poster width — the artwork and the focus
  // growth both scale with it, the caption and the focus lift do not — so the
  // fitting width solves directly rather than needing a search.
  final fixed =
      AnalogPosterTile.captionHeight(subtitle: subtitle) +
      AnalogSelection.focusLiftPx;
  final tall = analogRailHeight(metrics.posterWidthPx, subtitle: subtitle);
  if (tall <= maxHeightPx || tall <= fixed) return metrics;

  var fitted = (metrics.posterWidthPx * (maxHeightPx - fixed) / (tall - fixed))
      .floorToDouble();
  // The solve is exact in real numbers, but the tile rounds its caption and
  // artwork up to whole pixels, so the result can land a fraction over. Walk it
  // down until it genuinely fits rather than trusting the arithmetic through
  // two ceilings.
  while (fitted > 1 &&
      analogRailHeight(fitted, subtitle: subtitle) > maxHeightPx) {
    fitted -= 1;
  }
  return metrics.withPosterWidth(fitted, usableWidthPx);
}

class _RailSlot extends StatelessWidget {
  const _RailSlot({
    required this.item,
    required this.width,
    required this.focused,
    required this.dim,
    required this.motion,
    required this.onTap,
    this.hidden = false,
  });

  final AnalogRailItem item;
  final double width;
  final bool focused;
  final double dim;
  final bool hidden;
  final MotionProfile motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: motion.focusStep,
      curve: AnalogMotion.focusStepEase,
      opacity: hidden ? 0 : dim,
      child: _tile(),
    );
  }

  Widget _tile() {
    return AnalogPosterTile(
      imageUrl: item.imageUrl,
      title: item.label,
      subtitle: item.subtitle,
      placeholderLabel: item.placeholderLabel,
      // Only the selection is a hero: a Hero tag must be unique on screen, and
      // more importantly the row is what gets left behind — animating a poster
      // nobody selected would be flying the wrong artwork.
      heroTag: focused ? item.heroTag : null,
      width: width,
      focused: focused,
      progress: item.progress,
      onTap: onTap,
    );
  }
}

/// Fades the leading edge of the rail so the trail dissolves rather than being
/// cut off by the clip.
///
/// A hard clip reads as "the row is truncated here"; a fade reads as "these
/// have gone past". Same geometry, opposite meaning.
class _TrailFade extends StatelessWidget {
  const _TrailFade({required this.trailPx, required this.child});

  final double trailPx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || width <= 0 || trailPx <= 0) return child;
        final stop = (trailPx / width).clamp(0.0, 1.0);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0x00000000),
              Color(0x66000000),
              Color(0xFF000000),
            ],
            stops: [0.0, stop * 0.6, stop],
          ).createShader(rect),
          child: child,
        );
      },
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
