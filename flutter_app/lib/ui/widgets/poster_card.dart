import 'package:flutter/material.dart';

import '../tokens.dart';

/// FROZEN CONTRACT (PLAN §3.6). A library poster tile. [imageUrl] is optional so
/// the mock/offline paths can render a placeholder. E3 wires real image loading.
class PosterCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Material(
                color: AppColors.surface2,
                child: InkWell(
                  onTap: onTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl != null)
                        Image.network(imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const _PosterFallback())
                      else
                        const _PosterFallback(),
                      if (progress != null && progress! > 0)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: progress!.clamp(0, 1),
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
          const SizedBox(height: AppSpacing.sm),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
          if (subtitle != null)
            Text(subtitle!,
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
