import 'package:flutter/material.dart';

import '../palette.dart';
import '../theme.dart';
import '../tokens.dart';
import 'authed_image.dart';

/// A library poster tile — the shelf primitive.
///
/// Design guide §Library shelves: the title is centered below the artwork with
/// the rating beneath it; hover strengthens the shadow but never translates the
/// poster upward; the artwork corners are rounded and never clipped (the shelf
/// pads for the shadow). [emphasized] renders the first/selected poster subtly
/// larger. There is no `trailer` label.
///
/// The public signature is backward-compatible — the original
/// title/imageUrl/subtitle/onTap/progress/width/aspectRatio/heroTag params are
/// unchanged; [rating] and [emphasized] are additive optionals.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.onTap,
    this.progress,
    this.width = 160,
    this.aspectRatio = 2 / 3,
    this.heroTag,
    this.rating,
    this.emphasized = false,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final VoidCallback? onTap;

  /// 0.0–1.0 watch progress bar, or null for none.
  final double? progress;
  final double width;
  final double aspectRatio;

  /// When non-null, the poster image is wrapped in a [Hero] with this tag.
  final String? heroTag;

  /// Community rating on Jellyfin's 0–10 scale, shown as five brand-red stars.
  final double? rating;

  /// First/currently-selected poster — rendered subtly larger.
  final bool emphasized;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;

    Widget art = ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.imageUrl != null)
              AuthedNetworkImage(
                widget.imageUrl!,
                fit: BoxFit.cover,
                cacheWidth:
                    (widget.width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                errorBuilder: (_, _, _) => const _PosterFallback(),
              )
            else
              const _PosterFallback(),
            if (widget.progress != null && widget.progress! > 0)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  value: widget.progress!.clamp(0, 1),
                  minHeight: 3,
                  backgroundColor: wp.line2,
                  color: wp.accent,
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.heroTag != null) {
      art = Hero(tag: widget.heroTag!, child: art);
    }

    // Shadow lives on an AnimatedContainer BEHIND the clipped artwork so it
    // strengthens on hover without ever translating the poster.
    Widget poster = AnimatedContainer(
      duration: AppMotion.hover,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        color: wp.surface,
        boxShadow: _hover ? wp.posterShadowHover : wp.posterShadow,
      ),
      child: art,
    );

    if (widget.emphasized) {
      poster = Transform.scale(
        scale: 1.035,
        alignment: Alignment.bottomLeft,
        child: poster,
      );
    }

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            cursor: widget.onTap == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(onTap: widget.onTap, child: poster),
          ),
          const SizedBox(height: 9),
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.posterTitle.copyWith(color: wp.text),
          ),
          if (widget.rating != null) ...[
            const SizedBox(height: 4),
            _Stars(rating: widget.rating!),
          ],
          if (widget.subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: wp.faint, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  /// Jellyfin community rating, 0–10.
  final double rating;

  @override
  Widget build(BuildContext context) {
    final filled = (rating / 2).round().clamp(0, 5);
    final empty = context.wp.text.withValues(alpha: 0.18);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            Icons.star_rounded,
            size: 12,
            color: i < filled ? AppColors.brandRed : empty,
          ),
      ],
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();
  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return ColoredBox(
      color: wp.surface2,
      child: Center(child: Icon(Icons.movie_outlined, color: wp.faint)),
    );
  }
}
