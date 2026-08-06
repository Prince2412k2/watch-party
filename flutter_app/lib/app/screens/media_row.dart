import 'package:flutter/material.dart';

import '../../analog/chrome/analog_button.dart';
import '../../analog/chrome/analog_panel.dart';
import '../../analog/chrome/analog_progress.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/ui.dart';

/// PKG-D shared list-row idiom. Consolidates the three divergent row styles that
/// used to live on the Downloads and acquisition-Queue screens — a bespoke
/// bordered `Container`, a Material `Card`+`ListTile`, and a `Card`+`Row` — into
/// ONE [AnalogPanel]-framed row so both screens read as the same surface.
///
/// Slots (all optional except [title]):
/// - [leading]: a fixed-size visual — a poster [MediaThumb] or a status icon.
/// - [badge]: a top-right status pill (an [AppChip] or a badge).
/// - [subtitle]: a secondary line (queue metadata, or a failure message when
///   [subtitleIsError]).
/// - [progress]: when [showProgress], an [AnalogProgress] line (a null value
///   runs the indeterminate sweep). Callers must clamp values into 0..1.
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
    return AnalogPanel(
      lift: AnalogLift.flush,
      padding: const EdgeInsets.symmetric(
        horizontal: AnalogSpace.lgPx,
        vertical: AnalogSpace.mdPx,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AnalogSpace.mdPx),
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
                          fontFamily: AnalogType.sansFamily,
                          color: AnalogColor.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: AnalogSpace.smPx),
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
                        ? const TextStyle(
                            fontFamily: AnalogType.sansFamily,
                            color: AnalogColor.statusDanger,
                            fontSize: 12.5,
                          )
                        : const TextStyle(
                            fontFamily: AnalogType.sansFamily,
                            color: AnalogColor.inkDim,
                            fontSize: 13,
                          ),
                  ),
                ],
                if (showProgress) ...[
                  const SizedBox(height: AnalogSpace.smPx),
                  AnalogProgress(
                    value: progress,
                    ink: progressColor ?? AnalogColor.ink,
                    semanticLabel: title,
                  ),
                ],
                if (meta != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    meta!,
                    style: const TextStyle(
                      fontFamily: AnalogType.monoFamily,
                      fontSize: 11.5,
                      color: AnalogColor.inkDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AnalogSpace.mdPx),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A small poster thumbnail for a [MediaRow.leading] slot, with a monochrome
/// fallback when the URL is missing or fails to load.
///
/// Square-cornered, like every other piece of artwork in the app:
/// [AnalogPoster.radiusPx] is 0 "including skeletons, placeholders, seasons and
/// selected states", and a list row is not an exception to that.
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
    return ClipRect(
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
    color: AnalogColor.stageSurface2,
    child: Center(child: Icon(icon, color: AnalogColor.inkFaint, size: 20)),
  );
}

/// A leading status glyph on a tinted disc — used when a row has no poster
/// (e.g. the "needs attention" queue rows).
class MediaRowIcon extends StatelessWidget {
  const MediaRowIcon({
    super.key,
    required this.icon,
    this.color = AnalogColor.inkDim,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AnalogColor.stageSurface2,
        borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// The standard trailing action (pause/resume/cancel/remove) across PKG-D rows.
///
/// [tooltip] doubles as the control's accessible name — see [AnalogIconButton],
/// which is why it was already required here.
class MediaRowIconButton extends StatelessWidget {
  const MediaRowIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnalogIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      color: color,
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
    return AnalogPanel(
      lift: AnalogLift.flush,
      padding: const EdgeInsets.symmetric(
        horizontal: AnalogSpace.lgPx,
        vertical: AnalogSpace.mdPx,
      ),
      child: Row(
        children: [
          if (withThumb) ...[
            const LoadingSkeleton(
              width: 46,
              height: 69,
              borderRadius: AnalogPoster.radiusPx,
            ),
            const SizedBox(width: AnalogSpace.mdPx),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LoadingSkeleton(height: 13, width: 180),
                SizedBox(height: AnalogSpace.mdPx),
                SizedBox(
                  width: double.infinity,
                  child: LoadingSkeleton(
                    height: AnalogHairline.idlePx,
                    borderRadius: 0,
                  ),
                ),
                SizedBox(height: AnalogSpace.smPx),
                LoadingSkeleton(height: 10, width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
