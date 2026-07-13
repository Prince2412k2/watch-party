import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../../ui/ui.dart';

/// PKG-D shared list-row idiom. Consolidates the three divergent row styles that
/// used to live on the Downloads and acquisition-Queue screens — a bespoke
/// bordered `Container`, a Material `Card`+`ListTile`, and a `Card`+`Row` — into
/// ONE `sc.Card`-framed row so both screens read as the same surface.
///
/// Slots (all optional except [title]):
/// - [leading]: a fixed-size visual — a poster [MediaThumb] or a status icon.
/// - [badge]: a top-right status pill (an [AppChip] / `sc` badge).
/// - [subtitle]: a secondary line (queue metadata, or a failure message when
///   [subtitleIsError]).
/// - [progress]: when [showProgress], an `sc.Progress` bar (a null value renders
///   the indeterminate animation). Callers must clamp values into 0..1.
/// - [meta]: a monospace readout line (percentage / speed / seeds).
/// - [trailing]: the action cluster ([MediaRowIconButton]s or an [AppButton]).
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleIsError = false,
    this.subtitleMaxLines = 1,
    this.badge,
    this.showProgress = false,
    this.progress,
    this.progressColor,
    this.meta,
    this.trailing,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool subtitleIsError;
  final int subtitleMaxLines;
  final Widget? badge;
  final bool showProgress;

  /// 0..1, or null for an indeterminate bar. Only read when [showProgress].
  final double? progress;
  final Color? progressColor;
  final String? meta;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return sc.Card(
      filled: true,
      fillColor: AppColors.surface,
      borderColor: AppColors.line,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      badge!,
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleIsError
                        ? const TextStyle(color: AppColors.red, fontSize: 12.5)
                        : AppTheme.dim,
                  ),
                ],
                if (showProgress) ...[
                  const SizedBox(height: AppSpacing.sm),
                  sc.Progress(
                    progress: progress,
                    color: progressColor ?? AppColors.accent,
                    backgroundColor: AppColors.line2,
                  ),
                ],
                if (meta != null) ...[
                  const SizedBox(height: 6),
                  Text(meta!, style: AppTheme.mono),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A small rounded poster thumbnail for a [MediaRow.leading] slot, with a
/// monochrome fallback when the URL is missing or fails to load.
class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    this.posterUrl,
    this.width = 46,
    this.height = 69,
    this.icon = Icons.movie_outlined,
  });

  final String? posterUrl;
  final double width;
  final double height;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: SizedBox(
        width: width,
        height: height,
        child: posterUrl != null
            ? AuthedNetworkImage(
                posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback,
              )
            : _fallback,
      ),
    );
  }

  Widget get _fallback => ColoredBox(
    color: AppColors.surface2,
    child: Center(child: Icon(icon, color: AppColors.faint, size: 20)),
  );
}

/// A leading status glyph on a tinted disc — used when a row has no poster
/// (e.g. the "needs attention" queue rows).
class MediaRowIcon extends StatelessWidget {
  const MediaRowIcon({
    super.key,
    required this.icon,
    this.color = AppColors.dim,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// A ghost `sc` icon-button with a `sc` tooltip — the standard trailing action
/// (pause/resume/cancel/remove) across PKG-D rows.
class MediaRowIconButton extends StatelessWidget {
  const MediaRowIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color = AppColors.text,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return sc.Tooltip(
      tooltip: (context) => sc.TooltipContainer(child: Text(tooltip)),
      child: sc.IconButton.ghost(
        icon: Icon(icon, color: color, size: 18),
        onPressed: onPressed,
      ),
    );
  }
}

/// A shimmering placeholder shaped like a [MediaRow] — unifies the loading
/// state on [LoadingSkeleton] instead of a bare `CircularProgressIndicator`.
class MediaRowSkeleton extends StatelessWidget {
  const MediaRowSkeleton({super.key, this.withThumb = false});

  final bool withThumb;

  @override
  Widget build(BuildContext context) {
    return sc.Card(
      filled: true,
      fillColor: AppColors.surface,
      borderColor: AppColors.line,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          if (withThumb) ...[
            const LoadingSkeleton(
              width: 46,
              height: 69,
              borderRadius: AppSpacing.radiusSm,
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LoadingSkeleton(height: 13, width: 180),
                SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: LoadingSkeleton(
                    height: 6,
                    borderRadius: AppSpacing.radiusPill,
                  ),
                ),
                SizedBox(height: AppSpacing.sm),
                LoadingSkeleton(height: 10, width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
