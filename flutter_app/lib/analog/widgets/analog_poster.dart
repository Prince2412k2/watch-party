import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';
import '../../ui/widgets/authed_image.dart';
import '../../ui/widgets/pasted_artwork.dart';
import '../../ui/widgets/shaded_artwork.dart';
import '../../ui/widgets/textured_artwork.dart';
import '../browse_core.dart';

/// A single piece of poster artwork on the analog stage.
///
/// Named `AnalogPosterTile` rather than `AnalogPoster` because the generated
/// token class in `ui/analog_tokens.dart` already owns that name, and that file
/// cannot be hand-edited. Every geometry and depth value here is read from it.
///
/// The invariants this widget exists to hold (analog-interface-reference.md
/// §Browsing model):
///
/// * **Square, unrounded artwork at every size.** No `ClipRRect`, no
///   `borderRadius`, in any state — resting, focused, placeholder or skeleton.
///   `AnalogRadius.*` is chrome-only and must never reach here.
/// * **Physical depth, not a flat UI tile.** A fine square frame, directional
///   edge light from one scene direction, and a tinted (never pure black) cast
///   shadow thrown away from that light.
/// * **Focus is scale + lift + stronger shadow + brighter edge + local backdrop
///   darkening.** No perspective tilt, no bounce — every easing curve in
///   `AnalogMotion` keeps its control points inside 0..1.
///
/// Focus is *given*, not owned: [AnalogShelf] holds the selection model so it
/// can be remembered and restored across navigation.
class AnalogPosterTile extends StatelessWidget {
  const AnalogPosterTile({
    super.key,
    this.imageUrl,
    this.title,
    this.subtitle,
    this.placeholderLabel,
    this.width = 180,
    this.focused = false,
    this.onTap,
    this.heroTag,
    this.progress,
    this.aspectRatio = posterAspect,
    this.textured,
    this.textureSeed,
  });

  /// Lay a crumpled-paper sheet over the artwork. The tile's frame, edge light
  /// and cast shadow are untouched by it: the sheet creases the print, it does
  /// not change the poster's shape. Null defers to the ambient
  /// [ArtworkTextureScope], and so to the user's setting.
  final bool? textured;

  /// Picks which of the seven sheets this tile gets. An item id, so a title
  /// always creases the same way; see [ArtworkTexture.creaseFor].
  final String? textureSeed;

  /// Poster artwork, width ÷ height. The canonical 2:3 from the tokens.
  static const double posterAspect =
      AnalogPoster.aspectW / AnalogPoster.aspectH;

  /// Episode-still artwork, width ÷ height.
  ///
  /// Not a token: 16:9 is the frame the source material is already in, not a
  /// design decision this system gets to make, and it was already written
  /// literally into every episode card on the detail surfaces. Named once here
  /// so the rail and the tile cannot disagree about it.
  static const double stillAspect = 16 / 9;

  /// Same-origin artwork URL, or null to render the neutral placeholder.
  final String? imageUrl;

  /// Caption under the artwork. Null renders artwork alone.
  final String? title;
  final String? subtitle;

  /// Text the neutral placeholder carries (e.g. `S3`) when there is no artwork.
  final String? placeholderLabel;

  final double width;
  final bool focused;
  final VoidCallback? onTap;
  final String? heroTag;

  /// 0..1 watch progress, drawn as a hairline across the foot of the artwork.
  final double? progress;

  /// Artwork shape, width ÷ height. [posterAspect] for a title, [stillAspect]
  /// for an episode. The tile is otherwise identical — an episode still gets
  /// the same frame, edge light, cast shadow and focus growth a poster gets,
  /// because they are the same object at a different crop.
  final double aspectRatio;

  /// Artwork box height for [width] at [aspectRatio].
  static double artHeightFor(double width, {double aspectRatio = posterAspect}) =>
      width / aspectRatio;

  static const double _titlePx = 13;
  static const double _subtitlePx = 12;
  static const double _captionLineHeight = 1.3;

  /// Height the caption block occupies under the artwork.
  ///
  /// Line heights are pinned in [_Caption] so this is exact whatever font is
  /// resolved; a shelf slot sized from a font-dependent guess overflows the
  /// moment the font changes. The ceiling is not decoration either — a laid
  /// out paragraph is rounded up to a whole pixel, so a 16.9px line really
  /// occupies 17 and reserving 16.9 overflows by exactly 0.1.
  static double captionHeight({bool subtitle = false}) =>
      AnalogSpace.smPx +
      _lineBox(_titlePx) +
      (subtitle ? AnalogSpace.xsPx + _lineBox(_subtitlePx) : 0);

  static double _lineBox(double fontSize) =>
      (fontSize * _captionLineHeight).ceilToDouble();

  /// Room a shelf must leave around a tile so the focused scale and lift are
  /// not clipped. Focus grows the artwork about its centre, so half the growth
  /// lands above the box and half below, and the lift adds to the top only.
  static double focusOverflowFor(
    double width, {
    double aspectRatio = posterAspect,
  }) {
    final growth =
        artHeightFor(width, aspectRatio: aspectRatio) *
        (AnalogSelection.focusScale - 1) /
        2;
    return growth + AnalogSelection.focusLiftPx;
  }

  @override
  Widget build(BuildContext context) {
    final art = _PosterArt(
      imageUrl: imageUrl,
      placeholderLabel: placeholderLabel,
      width: width,
      focused: focused,
      progress: progress,
      aspectRatio: aspectRatio,
      textured: textured,
      textureSeed: textureSeed ?? heroTag ?? imageUrl,
    );

    final caption = title;
    Widget tile = SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heroTag == null ? art : Hero(tag: heroTag!, child: art),
          if (caption != null) ...[
            const SizedBox(height: AnalogSpace.smPx),
            _Caption(text: caption, focused: focused, emphasis: true),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: AnalogSpace.xsPx),
            _Caption(text: subtitle!, focused: focused, emphasis: false),
          ],
        ],
      ),
    );

    if (onTap != null) {
      tile = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: tile),
      );
    }
    return tile;
  }
}

/// The artwork box: frame, edge light, cast shadow and focus response.
class _PosterArt extends StatelessWidget {
  const _PosterArt({
    required this.imageUrl,
    required this.placeholderLabel,
    required this.width,
    required this.focused,
    required this.progress,
    required this.aspectRatio,
    required this.textured,
    required this.textureSeed,
  });

  final String? imageUrl;
  final String? placeholderLabel;
  final double width;
  final bool focused;
  final double? progress;
  final double aspectRatio;
  final bool? textured;
  final String? textureSeed;

  /// Decode the source at the largest size it is ever painted: the artwork
  /// fills its box, so `cover` needs exactly the box width, times the focus
  /// scale, times the device pixel ratio.
  int _decodeWidth(BuildContext context) =>
      (width * AnalogSelection.focusScale * MediaQuery.devicePixelRatioOf(context))
          .ceil();

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: focused ? 1 : 0),
      duration: AnalogMotion.focusStepMs,
      curve: AnalogMotion.focusStepEase,
      builder: (context, t, child) {
        final darken = AnalogSelection.focusBackdropDarkenPct / 100 * t;
        return Transform.translate(
          offset: Offset(0, -AnalogSelection.focusLiftPx * t),
          child: Transform.scale(
            scale: lerpDouble(
              AnalogSelection.restScale,
              AnalogSelection.focusScale,
              t,
            )!,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Square by construction: there is deliberately no
                // `borderRadius` on this decoration, and none below it.
                color: AnalogColor.stageSurface,
                border: Border.all(
                  color: Color.lerp(
                    AnalogColor.line,
                    AnalogColor.lineStrong,
                    t,
                  )!,
                  width: AnalogPoster.framePx,
                ),
                boxShadow: [
                  // Local backdrop shading under the focused item — the
                  // reference's "darker local backdrop shading", painted as a
                  // wide soft spread behind the artwork rather than a glow
                  // around it.
                  if (darken > 0)
                    BoxShadow(
                      color: AnalogColor.stageVoid.withValues(alpha: darken),
                      blurRadius: AnalogElevation.focusBlurPx * 2,
                      spreadRadius: AnalogSpace.xlPx,
                    ),
                  BoxShadow(
                    color: Color.lerp(
                      AnalogColor.shadowCast,
                      AnalogColor.shadowCastStrong,
                      t,
                    )!,
                    blurRadius: lerpDouble(
                      AnalogElevation.restBlurPx,
                      AnalogElevation.focusBlurPx,
                      t,
                    )!,
                    offset: Offset(
                      lerpDouble(
                        AnalogElevation.restOffsetXPx,
                        AnalogElevation.focusOffsetXPx,
                        t,
                      )!,
                      lerpDouble(
                        AnalogElevation.restOffsetYPx,
                        AnalogElevation.focusOffsetYPx,
                        t,
                      )!,
                    ),
                  ),
                ],
              ),
              child: CustomPaint(
                foregroundPainter: EdgeLightPainter(
                  angleDeg: AnalogSelection.sceneLightAngleDeg,
                  intensity: lerpDouble(0.7, 1, t)!,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: SizedBox(
        width: width,
        height: AnalogPosterTile.artHeightFor(width, aspectRatio: aspectRatio),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The sheet creases the print, and only the print. Everything the
            // interface draws on top of the artwork stays out of it.
            if (url == null)
              AnalogPosterPlaceholder(label: placeholderLabel)
            else if (textured ?? ArtworkTextureScope.of(context))
              // Pasted: the wall's relief lights it, the print bends over the
              // brick, and its own sheet of paper carries the grunge. One of
              // ten sheets, chosen from the title, so a rail shows all ten.
              ShadedArtwork(
                url: url,
                settings: ArtworkPaste.poster,
                wallSeed: ArtworkTextureScope.wallSeedOf(context),
                paperSeed: textureSeed,
                errorBuilder: (_) =>
                    AnalogPosterPlaceholder(label: placeholderLabel),
              )
            else
              AuthedNetworkImage(
                url,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                cacheWidth: _decodeWidth(context),
                errorBuilder: (_, _, _) =>
                    AnalogPosterPlaceholder(label: placeholderLabel),
              ),
            if (progress != null && progress! > 0)
              Align(
                alignment: Alignment.bottomLeft,
                child: FractionallySizedBox(
                  widthFactor: progress!.clamp(0, 1),
                  child: Container(
                    height: AnalogHairline.idlePx,
                    color: AnalogColor.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The fixed-size neutral fill shown when artwork is absent or failed.
///
/// Fixed-size on purpose: layout and focus must not move when artwork is
/// missing (analog-interface-reference.md §Shows). Square, like everything else.
class AnalogPosterPlaceholder extends StatelessWidget {
  const AnalogPosterPlaceholder({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AnalogColor.stageSurface2,
      child: label == null
          ? const SizedBox.expand()
          : Center(
              child: Text(
                label!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AnalogType.sansFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                  color: AnalogColor.inkFaint,
                ),
              ),
            ),
    );
  }
}

/// Loading state for one poster slot. Square, like the artwork it stands in for.
class AnalogPosterSkeleton extends StatefulWidget {
  const AnalogPosterSkeleton({super.key, this.width = 180, this.captioned = true});

  final double width;

  /// Reserve the caption line so the shelf does not resize when data lands.
  final bool captioned;

  @override
  State<AnalogPosterSkeleton> createState() => _AnalogPosterSkeletonState();
}

class _AnalogPosterSkeletonState extends State<AnalogPosterSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => Container(
              width: widget.width,
              height: AnalogPosterTile.artHeightFor(widget.width),
              // No borderRadius: skeletons are square too.
              decoration: BoxDecoration(
                color: Color.lerp(
                  AnalogColor.stageSurface,
                  AnalogColor.stageSurface2,
                  _pulse.value,
                ),
                border: Border.all(
                  color: AnalogColor.line,
                  width: AnalogPoster.framePx,
                ),
              ),
            ),
          ),
          if (widget.captioned) ...[
            const SizedBox(height: AnalogSpace.smPx),
            Container(
              width: widget.width * 0.62,
              height: 12,
              color: AnalogColor.stageSurface2,
            ),
          ],
        ],
      ),
    );
  }
}

/// A season tile whose artwork is resolved by the shared
/// [resolveSeasonArtwork] core: season Primary -> series Primary -> a fixed
/// neutral placeholder carrying the season number.
///
/// This is the whole fix for the season-art break. The old path read
/// `sonarrSeriesRaw['seasons'][].images`, which the server never emits, and
/// which would have pointed at a third-party CDN that `ArtworkCache` refuses
/// on same-origin grounds anyway. Here the URL can only ever come from
/// [imageUrlBuilder] applied to a Jellyfin item id, which is same-origin and
/// already whitelisted server-side.
class AnalogSeasonPoster extends StatefulWidget {
  const AnalogSeasonPoster({
    super.key,
    required this.input,
    required this.imageUrlBuilder,
    this.title,
    this.width = 180,
    this.focused = false,
    this.onTap,
  });

  final SeasonArtworkInput input;

  /// Builds a same-origin artwork URL for a Jellyfin item id and image tag.
  final String Function(String itemId, String? imageTag) imageUrlBuilder;

  final String? title;
  final double width;
  final bool focused;
  final VoidCallback? onTap;

  @override
  State<AnalogSeasonPoster> createState() => _AnalogSeasonPosterState();
}

class _AnalogSeasonPosterState extends State<AnalogSeasonPoster> {
  /// Ids whose artwork has already failed here. Held in widget state rather
  /// than recomputed so a failed season cannot flip back and loop.
  final _failed = <String>[];

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final artwork = resolveSeasonArtwork(
      SeasonArtworkInput(
        seasonId: input.seasonId,
        seasonNumber: input.seasonNumber,
        seasonImageTag: input.seasonImageTag,
        seriesId: input.seriesId,
        seriesImageTag: input.seriesImageTag,
        failedIds: [...input.failedIds, ..._failed],
      ),
    );
    final itemId = artwork.itemId;
    return AnalogPosterTile(
      key: ValueKey('season-art-${artwork.kind.name}-$itemId'),
      imageUrl: itemId == null
          ? null
          : widget.imageUrlBuilder(itemId, artwork.imageTag),
      placeholderLabel: artwork.label ?? _labelFor(input.seasonNumber),
      title: widget.title,
      width: widget.width,
      focused: widget.focused,
      onTap: widget.onTap,
    );
  }

  static String _labelFor(int? seasonNumber) =>
      seasonNumber == null ? '—' : 'S$seasonNumber';
}

/// Paints the one-pixel directional edge light around square artwork.
///
/// The scene has a single light at [angleDeg] (`AnalogSelection
/// .sceneLightAngleDeg`, 315deg = above-left). Edges whose outward normal faces
/// the light take [AnalogColor.edgeLight]; the two facing away take
/// [AnalogColor.edgeShade]. Deriving both from the same angle is what keeps the
/// highlight and the cast shadow (whose offsets are positive x/y, i.e.
/// below-right) telling the same story.
@visibleForTesting
class EdgeLightPainter extends CustomPainter {
  const EdgeLightPainter({required this.angleDeg, required this.intensity});

  final double angleDeg;

  /// 0..1 scale on the highlight, raised on focus for a brighter edge.
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final rad = angleDeg * math.pi / 180;
    // Unit vector pointing from the artwork towards the light source.
    final lx = math.sin(rad);
    final ly = -math.cos(rad);
    const w = AnalogPoster.framePx;

    void edge(Rect rect, double facing) {
      if (facing.abs() < 0.01) return;
      final lit = facing > 0;
      final base = lit ? AnalogColor.edgeLight : AnalogColor.edgeShade;
      final strength = facing.abs() * (lit ? intensity : 1.0);
      canvas.drawRect(
        rect,
        Paint()..color = base.withValues(alpha: base.a * strength),
      );
    }

    // Outward normals: top (0,-1), left (-1,0), right (1,0), bottom (0,1).
    edge(Rect.fromLTWH(0, 0, size.width, w), -ly);
    edge(Rect.fromLTWH(0, 0, w, size.height), -lx);
    edge(Rect.fromLTWH(size.width - w, 0, w, size.height), lx);
    edge(Rect.fromLTWH(0, size.height - w, size.width, w), ly);
  }

  @override
  bool shouldRepaint(EdgeLightPainter old) =>
      old.angleDeg != angleDeg || old.intensity != intensity;
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.text,
    required this.focused,
    required this.emphasis,
  });

  final String text;
  final bool focused;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: AnalogMotion.focusStepMs,
      curve: AnalogMotion.focusStepEase,
      style: TextStyle(
        fontFamily: AnalogType.sansFamily,
        fontSize: emphasis
            ? AnalogPosterTile._titlePx
            : AnalogPosterTile._subtitlePx,
        height: AnalogPosterTile._captionLineHeight,
        fontWeight: emphasis && focused ? FontWeight.w700 : FontWeight.w500,
        letterSpacing: 0.2,
        color: focused
            ? AnalogColor.ink
            : (emphasis ? AnalogColor.inkDim : AnalogColor.inkFaint),
      ),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
