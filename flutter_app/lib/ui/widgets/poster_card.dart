import 'package:flutter/material.dart';

import '../tokens.dart';

/// FROZEN CONTRACT (PLAN §3.6). A library poster tile. [imageUrl] is optional so
/// the mock/offline paths can render a placeholder. E3 wires real image loading.
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
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final VoidCallback? onTap;

  /// 0.0–1.0 watch progress bar, or null for none.
  final double? progress;
  final double width;
  final double aspectRatio;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                border: Border.all(color: _hover ? AppColors.line2 : Colors.transparent),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: Material(
                    color: AppColors.surface2,
                    child: InkWell(
                      onTap: widget.onTap,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.imageUrl != null)
                            Image.network(widget.imageUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const _PosterFallback())
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
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
          if (widget.subtitle != null)
            Text(widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.faint, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: AppColors.surface2, child: Center(child: Icon(Icons.movie_outlined, color: AppColors.faint)));
}
