// The Movies stage's expanded state: what the browse surface becomes when you
// select a title, and the pieces that only exist once you have.
//
// "On the movies list page we want to have the 1:1 page as the page after we
// select the movie with same font and everything so we can pull off this
// transition."
//
// So this is deliberately NOT a route. Pushing one rebuilds the tree, and a
// rebuilt tree has nothing left to interpolate — the title would cut rather
// than stay put, and the poster would have no source rect to fly from. The
// stage keeps its own widgets and animates between two configurations of them:
// the heading, the meta line and the overview are literally the same Text
// widgets at the same size in both states, which is what makes them appear not
// to move at all while everything around them does.
//
// The moves, all driven off one controller:
//
//   * the rail drops away and fades out
//   * the selected poster flies from its slot to the detail position
//   * the cast rises from beneath where the rail was
//   * the actions slide in from the left, after the poster has landed

import 'package:flutter/material.dart';

import '../../analog/chrome/chrome.dart';
import '../../models/models.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/widgets/authed_image.dart';

/// Stagger for the expanded state's parts.
///
/// The poster leads and everything else follows it. Ordering the moves rather
/// than running them together is the difference between a transition that reads
/// as one gesture and a set of things that happen to animate at the same time.
abstract final class MoviesDetailStagger {
  /// The rail leaves immediately — it is what the poster is leaving *from*, so
  /// it must be out of the way before the poster arrives anywhere.
  static const Interval rail = Interval(0.0, 0.45, curve: Curves.easeInCubic);

  /// The poster travels across the whole move.
  static const Interval poster = Interval(0.0, 0.82);

  /// Actions slide in once the poster is most of the way there.
  static const Interval actions = Interval(0.55, 1.0);

  /// Cast comes last, from beneath.
  static const Interval cast = Interval(0.62, 1.0);
}

/// The flying poster: artwork alone, no caption.
///
/// Drawn by the stage rather than by the rail so it can cross the boundary
/// between them. It is positioned in stage coordinates at every frame, which is
/// why the rail's geometry had to become shared rather than private.
class MoviesHeroPoster extends StatelessWidget {
  const MoviesHeroPoster({
    super.key,
    required this.imageUrl,
    required this.rect,
    required this.elevation,
  });

  final String? imageUrl;
  final Rect rect;

  /// 0..1 — how far into the move, used only for the shadow. The poster gains
  /// weight as it leaves the row, which is what sells it as lifting rather than
  /// sliding.
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Square: artwork is never rounded, in flight or at rest.
            color: AnalogColor.stageSurface,
            border: Border.all(
              color: AnalogColor.line,
              width: AnalogPoster.framePx,
            ),
            boxShadow: [
              BoxShadow(
                color: AnalogColor.shadowCastStrong,
                blurRadius: AnalogElevation.restBlurPx +
                    (AnalogElevation.focusBlurPx - AnalogElevation.restBlurPx) *
                        elevation,
                offset: Offset(
                  AnalogElevation.focusOffsetXPx * elevation,
                  AnalogElevation.focusOffsetYPx * elevation,
                ),
              ),
            ],
          ),
          // AuthedNetworkImage, not Image.network: the library image route is
          // behind the session, so a bare request 401s and renders nothing but
          // the error box.
          child: imageUrl == null
              ? const SizedBox.shrink()
              : AuthedNetworkImage(imageUrl!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// Cast, rising from beneath where the rail was.
class MoviesCastRow extends StatelessWidget {
  const MoviesCastRow({
    super.key,
    required this.people,
    required this.imageUrlFor,
    required this.height,
  });

  final List<Person> people;
  final String Function(String personId) imageUrlFor;
  final double height;

  static const double _faceWidth = 92;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The stage owns the wheel — it drives the rail. A cast row that ate
        // scroll events would make the surface behave differently depending on
        // where the pointer happened to rest.
        physics: const NeverScrollableScrollPhysics(),
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(width: AnalogSpace.mdPx),
        itemBuilder: (context, i) {
          final person = people[i];
          return SizedBox(
            width: _faceWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AnalogColor.stageSurface2,
                      border: Border.all(color: AnalogColor.line),
                    ),
                    child: SizedBox(
                      width: _faceWidth,
                      child: AuthedNetworkImage(
                        imageUrlFor(person.id),
                        fit: BoxFit.cover,
                        // Plenty of cast members genuinely have no headshot,
                        // so the fallback is a real state, not an error path.
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.person,
                            color: AnalogColor.inkFaint,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AnalogSpace.xsPx),
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AnalogType.sansFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AnalogColor.ink,
                  ),
                ),
                if ((person.role ?? '').isNotEmpty)
                  Text(
                    person.role!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AnalogType.sansFamily,
                      fontSize: 11,
                      color: AnalogColor.inkFaint,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Play / Download / Back, sliding in from the left.
///
/// Staggered against each other as well as against the poster, so the row
/// assembles rather than appearing.
class MoviesActionBar extends StatelessWidget {
  const MoviesActionBar({
    super.key,
    required this.progress,
    required this.onPlay,
    required this.onDownload,
    required this.onBack,
    required this.downloadBusy,
  });

  /// 0..1 across [MoviesDetailStagger.actions].
  final double progress;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final VoidCallback onBack;
  final bool downloadBusy;

  @override
  Widget build(BuildContext context) {
    Widget slide(int index, Widget child) {
      // Each control starts a little later than the one before it.
      final start = index * 0.16;
      final t = ((progress - start) / (1 - start)).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      return Opacity(
        opacity: eased,
        child: Transform.translate(
          offset: Offset(-36 * (1 - eased), 0),
          child: child,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        slide(
          0,
          AnalogButton(
            label: 'Play',
            icon: Icons.play_arrow,
            tone: AnalogButtonTone.primary,
            onPressed: onPlay,
          ),
        ),
        const SizedBox(width: AnalogSpace.smPx),
        slide(
          1,
          AnalogButton(
            label: downloadBusy ? 'Downloading' : 'Download',
            icon: Icons.download,
            busy: downloadBusy,
            onPressed: onDownload,
          ),
        ),
        const SizedBox(width: AnalogSpace.smPx),
        slide(
          2,
          AnalogIconButton(
            icon: Icons.close,
            tooltip: 'Back to the library',
            onPressed: onBack,
          ),
        ),
      ],
    );
  }
}
