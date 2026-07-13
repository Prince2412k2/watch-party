import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../tokens.dart';
import 'authed_image.dart';

/// FROZEN CONTRACT (PLAN §3.6). A library poster tile on an `sc.Card` frame with
/// a hover scale (1.03) and an optional [heroTag] for poster→detail Hero flight.
/// [imageUrl] is optional so mock/offline paths render a placeholder.
///
/// Signature is frozen except the ADDITIVE optional [heroTag] (PLAN allows this
/// one addition) — omit it and the card behaves exactly as before.
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
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final VoidCallback? onTap;

  /// 0.0–1.0 watch progress bar, or null for none.
  final double? progress;
  final double width;
  final double aspectRatio;

  /// When non-null, the poster image is wrapped in a [Hero] with this tag so it
  /// flies into the detail screen's hero. Null keeps the original behaviour.
  final String? heroTag;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget poster = ClipRRect(
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
                  backgroundColor: AppColors.line2,
                  color: AppColors.accent,
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.heroTag != null) {
      poster = Hero(tag: widget.heroTag!, child: poster);
    }

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            cursor: widget.onTap == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedScale(
                scale: _hover ? 1.03 : 1.0,
                duration: AppMotion.hover,
                curve: AppMotion.standard,
                child: sc.Card(
                  padding: EdgeInsets.zero,
                  filled: true,
                  fillColor: AppColors.surface2,
                  borderColor: _hover ? AppColors.line2 : Colors.transparent,
                  child: poster,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.subtitle != null)
            Text(
              widget.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.faint, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.surface2,
    child: Center(child: Icon(Icons.movie_outlined, color: AppColors.faint)),
  );
}
