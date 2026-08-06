import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import '../browse_core.dart';
import 'analog_poster.dart';

/// Builds one slot of a shelf. [focused] is the shelf's single selection.
typedef AnalogShelfItemBuilder =
    Widget Function(BuildContext context, int index, bool focused);

/// A horizontal strip of items, exactly one of which owns focus.
///
/// This is the replacement for the four independent ad-hoc steppers that grew
/// up around the old browse tree (`poster_shelf.dart`, the season and episode
/// wheels in `show_stage.dart`, the home rail arrows). All of them invented
/// their own wheel handling; none agreed with the web client. Here the wheel
/// goes through [steppedScroll], the shared core pinned by
/// `app/shared/design/interaction.json` and mirrored in TypeScript, so
/// "one deliberate gesture moves one item" means the same thing in both
/// clients on the same hardware.
///
/// Selection is **controlled**: [focusedIndex] comes in and [onFocusChanged]
/// goes out. The old shelf kept a private `int _selectedIndex`, which is why
/// Back could never return to the item you left from. Lifting it out is what
/// makes [restoreFocus] usable.
///
/// Input, all landing on the same model (§Cross-input contract):
///
/// * wheel and trackpad — [steppedScroll], momentum absorbed;
/// * arrow left/right — one step, with a detent at each end;
/// * arrow up/down — deliberately **not** handled, so Flutter's directional
///   traversal walks to the next shelf. This is also what makes a TV remote's
///   D-pad work, which nothing in the old tree supported;
/// * Enter / Space / Select — activate;
/// * click — focus then activate;
/// * hover — focus, but only once the pointer has really moved (see
///   [_hoverArmed]).
class AnalogShelf extends StatefulWidget {
  const AnalogShelf({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemWidth,
    required this.itemHeight,
    this.title,
    this.gap = AnalogPoster.gapPx,
    this.focusedIndex = 0,
    this.onFocusChanged,
    this.onActivate,
    this.onEdge,
    this.onShelfFocusChanged,
    this.semanticLabelBuilder,
    this.autofocus = false,
    this.focusNode,
    this.nowMs,
    this.scrollConfig = kSteppedScrollDefaults,
  });

  final int itemCount;
  final AnalogShelfItemBuilder itemBuilder;
  final double itemWidth;

  /// Laid-out height of one slot, artwork plus whatever caption it carries.
  /// The shelf adds its own room for the focus lift, scale and cast shadow.
  final double itemHeight;

  final String? title;
  final double gap;

  final int focusedIndex;
  final ValueChanged<int>? onFocusChanged;
  final ValueChanged<int>? onActivate;

  /// Fired when a step would run off the end: `-1` past the start, `+1` past
  /// the end. "Scroll moves focus through items and then into the next
  /// collection or level" — the surface decides what the next level is.
  final ValueChanged<int>? onEdge;

  /// Whether this shelf is the one that owns focus.
  final ValueChanged<bool>? onShelfFocusChanged;

  final String Function(int index)? semanticLabelBuilder;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Clock for [steppedScroll], injectable so its timing can be driven in
  /// tests without waiting in real time.
  final double Function()? nowMs;

  final SteppedScrollConfig scrollConfig;

  static const double _titlePx = 20;
  static const double _titleLineHeight = 1.2;

  /// Height of the heading block — one pinned title line plus the gap beneath
  /// it — for a shelf that has a [title].
  ///
  /// Pinned rather than measured because a surface has to reserve this space
  /// before the text is laid out. Leaving the line height to the font's own
  /// metrics is what made an earlier version of this overflow by 11px: the
  /// same arithmetic is right for one font and wrong for the next. Rounded up
  /// because a laid out paragraph occupies whole pixels.
  static final double headingHeight =
      (_titlePx * _titleLineHeight).ceilToDouble() + AnalogSpace.mdPx;

  @override
  State<AnalogShelf> createState() => _AnalogShelfState();
}

class _AnalogShelfState extends State<AnalogShelf> {
  final _scroll = ScrollController();
  final _scrollState = SteppedScrollState();
  FocusNode? _ownedFocusNode;

  /// Flutter re-delivers hover events when content slides under a stationary
  /// cursor. Every focus step slides cards under the cursor, so an unguarded
  /// hover handler would let whichever card happens to land there steal focus
  /// back. Hover only counts once the pointer has actually moved.
  bool _hoverArmed = false;
  Offset? _lastPointer;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode(debugLabel: 'AnalogShelf'));

  double get _stride => widget.itemWidth + widget.gap;

  double get _overflowTop =>
      AnalogPosterTile.focusOverflowFor(widget.itemWidth);

  double get _overflowBottom =>
      AnalogPosterTile.focusOverflowFor(widget.itemWidth) +
      AnalogElevation.focusOffsetYPx;

  double _now() =>
      widget.nowMs?.call() ??
      DateTime.now().millisecondsSinceEpoch.toDouble();

  @override
  void didUpdateWidget(AnalogShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedIndex != widget.focusedIndex ||
        oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealFocused());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  /// Bring the focused slot inside the viewport, keeping
  /// [AnalogPoster.shelfPeekPx] of the neighbour visible so the strip always
  /// reads as continuing past the edge.
  void _revealFocused() {
    if (!mounted || !_scroll.hasClients || widget.itemCount == 0) return;
    final position = _scroll.position;
    final start = widget.focusedIndex * _stride;
    final end = start + widget.itemWidth;
    const peek = AnalogPoster.shelfPeekPx;

    var target = position.pixels;
    if (start - peek < target) {
      target = start - peek;
    } else if (end + peek > target + position.viewportDimension) {
      target = end + peek - position.viewportDimension;
    }
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return;
    _scroll.animateTo(
      target,
      duration: AnalogMotion.focusStepMs,
      curve: AnalogMotion.focusStepEase,
    );
  }

  void _step(int direction) {
    final next = widget.focusedIndex + direction;
    if (widget.itemCount == 0 || next < 0 || next >= widget.itemCount) {
      widget.onEdge?.call(direction);
      return;
    }
    _hoverArmed = false;
    widget.onFocusChanged?.call(next);
  }

  void _focusIndex(int index) {
    if (index == widget.focusedIndex) return;
    widget.onFocusChanged?.call(index.clamp(0, widget.itemCount - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _step(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _step(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.gameButtonA:
        if (widget.itemCount > 0) widget.onActivate?.call(widget.focusedIndex);
        return KeyEventResult.handled;
      default:
        // Up/down fall through on purpose: directional traversal owns them,
        // which is how a remote walks between shelves.
        return KeyEventResult.ignored;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Claim the event so the vertical page scroller underneath does not also
    // act on it. The inner list runs NeverScrollableScrollPhysics, so it never
    // competes for registration here.
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scroll = resolved as PointerScrollEvent;
      final delta = scroll.scrollDelta.dx.abs() > scroll.scrollDelta.dy.abs()
          ? scroll.scrollDelta.dx
          : scroll.scrollDelta.dy;
      final step = steppedScroll(
        _scrollState,
        delta,
        _now(),
        widget.scrollConfig,
      );
      if (step == 0) return;
      _focusNode.requestFocus();
      _step(step);
    });
  }

  void _onHover(PointerHoverEvent event) {
    final moved =
        _lastPointer == null || (event.position - _lastPointer!).distance > 2;
    _lastPointer = event.position;
    if (moved) _hoverArmed = true;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AnalogSpace.xsPx,
              bottom: AnalogSpace.mdPx,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AnalogType.sansFamily,
                fontSize: AnalogShelf._titlePx,
                height: AnalogShelf._titleLineHeight,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AnalogColor.ink,
              ),
            ),
          ),
        Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          onFocusChange: (has) => widget.onShelfFocusChanged?.call(has),
          child: MouseRegion(
            onHover: _onHover,
            onExit: (_) => _hoverArmed = false,
            child: Listener(
              onPointerDown: (_) => _focusNode.requestFocus(),
              onPointerSignal: _onPointerSignal,
              child: SizedBox(
                height: widget.itemHeight + _overflowTop + _overflowBottom,
                child: ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  // The shelf owns its own motion; the list must never coast
                  // on raw wheel delta, and it must not register for pointer
                  // signals ahead of the stepped handler above.
                  physics: const NeverScrollableScrollPhysics(),
                  clipBehavior: Clip.hardEdge,
                  padding: EdgeInsets.only(
                    top: _overflowTop,
                    bottom: _overflowBottom,
                    right: AnalogPoster.shelfPeekPx,
                  ),
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, _) => SizedBox(width: widget.gap),
                  itemBuilder: _buildSlot,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlot(BuildContext context, int index) {
    final focused = index == widget.focusedIndex;
    return MouseRegion(
      key: ValueKey('analog-shelf-item-$index'),
      onEnter: (_) {
        if (!_hoverArmed) return;
        _focusNode.requestFocus();
        _focusIndex(index);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _focusNode.requestFocus();
          _focusIndex(index);
          widget.onActivate?.call(index);
        },
        child: Semantics(
          selected: focused,
          button: widget.onActivate != null,
          label: widget.semanticLabelBuilder?.call(index),
          child: SizedBox(
            width: widget.itemWidth,
            height: widget.itemHeight,
            child: widget.itemBuilder(context, index, focused),
          ),
        ),
      ),
    );
  }
}
