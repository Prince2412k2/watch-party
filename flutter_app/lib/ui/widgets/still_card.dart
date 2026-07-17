import 'package:flutter/material.dart';

import '../palette.dart';
import '../theme.dart';
import 'authed_image.dart';

/// A 16:9 "still" card — the Continue watching / Next up rail primitive (web
/// `StillCard`, Library.tsx). Landscape thumbnail art with an optional bottom
/// watch-progress bar, a title, and a mono subtitle below.
///
/// Per the design guide, hover strengthens the shadow but never translates the
/// card upward. [onHover] lets a shelf drive the ambient wash off the card the
/// pointer is over (mirrors the web `setBalancedPoster` on hover/focus).
class StillCard extends StatefulWidget {
  const StillCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.progress,
    this.onTap,
    this.onHover,
    this.heroTag,
    this.width = 300,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;

  /// 0.0–1.0 watch progress bar, or null for none.
  final double? progress;
  final VoidCallback? onTap;
  final VoidCallback? onHover;
  final String? heroTag;
  final double width;

  @override
  State<StillCard> createState() => _StillCardState();
}

class _StillCardState extends State<StillCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;

    Widget art = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.imageUrl != null)
              AuthedNetworkImage(
                widget.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _StillFallback(),
              )
            else
              const _StillFallback(),
            if (widget.progress != null && widget.progress! > 0)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  value: widget.progress!.clamp(0, 1),
                  minHeight: 4,
                  backgroundColor: wp.text.withValues(alpha: 0.15),
                  color: wp.text,
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.heroTag != null) {
      art = Hero(tag: widget.heroTag!, child: art);
    }

    final poster = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: wp.surface,
        boxShadow: _hover ? wp.posterShadowHover : wp.posterShadow,
      ),
      child: art,
    );

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: widget.onTap == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onEnter: (_) {
              setState(() => _hover = true);
              widget.onHover?.call();
            },
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(onTap: widget.onTap, child: poster),
          ),
          const SizedBox(height: 9),
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: wp.text,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              widget.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono.copyWith(color: wp.faint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _StillFallback extends StatelessWidget {
  const _StillFallback();
  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return ColoredBox(
      color: wp.surface2,
      child: Center(child: Icon(Icons.movie_outlined, color: wp.faint)),
    );
  }
}
