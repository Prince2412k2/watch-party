import 'package:flutter/material.dart';

import '../palette.dart';
import '../theme.dart';

/// A horizontal poster shelf — the library/discover primitive (design guide
/// §Library and discovery shelves). A Circular-Light section heading with the
/// scroll arrows on its right, over a horizontally scrolling rail of
/// [PosterCard]s. Never a poster grid.
///
/// The rail pads generously and does NOT clip (`clipBehavior: Clip.none`) so
/// the emphasized first poster's scale and the hover shadow are contained
/// rather than cut off at the rail boundary. The caller supplies the built
/// children (marking whichever is first/selected via `PosterCard.emphasized`);
/// this widget owns only layout + scrolling.
class PosterShelf extends StatefulWidget {
  const PosterShelf({
    super.key,
    required this.title,
    required this.children,
    this.spacing = 16,
    this.leftInset = 0,
  });

  final String title;
  final List<Widget> children;

  /// Gap between posters.
  final double spacing;

  /// Extra start padding so the rail begins near — but not at — the left edge.
  final double leftInset;

  @override
  State<PosterShelf> createState() => _PosterShelfState();
}

class _PosterShelfState extends State<PosterShelf> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _nudge(int direction) {
    if (!_controller.hasClients) return;
    final extent = _controller.position.viewportDimension * 0.8;
    final target = (_controller.offset + direction * extent).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final children = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      if (i > 0) children.add(SizedBox(width: widget.spacing));
      children.add(widget.children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: widget.leftInset, right: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.headlineLarge.copyWith(color: wp.text),
                ),
              ),
              _ShelfArrow(icon: Icons.chevron_left, onTap: () => _nudge(-1)),
              const SizedBox(width: 7),
              _ShelfArrow(icon: Icons.chevron_right, onTap: () => _nudge(1)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Fixed rail height comes from the tallest poster + its meta; the parent
        // supplies it via an intrinsic/bounded height. Rail is bottom-aligned so
        // the emphasized poster grows upward without clipping.
        SizedBox(
          height: _railHeight,
          child: ListView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.only(
              left: widget.leftInset,
              right: 40,
              top: 20,
              bottom: 30,
            ),
            children: [
              for (final child in children)
                Align(
                  alignment: Alignment.bottomLeft,
                  widthFactor: 1,
                  child: child,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// A comfortable rail height for the clamped poster width band (150–205)
  /// at the guide's 3/5 art ratio, plus room for the centered title + rating
  /// and the top/bottom rail padding that contains scale + shadow.
  double get _railHeight {
    const posterWidth = 190.0;
    const artHeight = posterWidth * 5 / 3;
    return artHeight + 68 + 50;
  }
}

class _ShelfArrow extends StatefulWidget {
  const _ShelfArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ShelfArrow> createState() => _ShelfArrowState();
}

class _ShelfArrowState extends State<_ShelfArrow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hover ? wp.surface : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: 22,
            color: _hover ? wp.text : wp.dim,
          ),
        ),
      ),
    );
  }
}
