import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'media_kit_player_controller.dart';
import 'player_controller.dart';

/// Netflix-style subtitle appearance for media_kit's built-in [SubtitleView].
///
/// Netflix renders subtitles as clean, semibold white sans-serif text with a
/// soft-but-strong dark outline + drop shadow (NO solid background box), sitting
/// centered near the bottom with a comfortable margin that keeps them clear of
/// the transport controls. We emulate that here:
///
/// * `fontFamily` is intentionally left unset so the platform default
///   sans-serif is used (Roboto/Helvetica-like). The design token
///   `AppFonts.sans` ('Hanken Grotesk') is NOT bundled in pubspec, so naming it
///   would only fall back to the same default — the weight + shadow treatment is
///   what actually reads as "Netflix", not the specific family.
/// * `backgroundColor: transparent` removes media_kit's default `0xAA000000`
///   box; legibility comes from the shadow stack instead.
/// * The four diagonal 1px black shadows fake a thin outline; the two larger
///   soft shadows add the Netflix drop-shadow glow so text stays readable over
///   bright video.
const _netflixSubtitleStyle = TextStyle(
  color: Color(0xFFFFFFFF),
  fontSize: 34,
  fontWeight: FontWeight.w600,
  height: 1.3,
  letterSpacing: 0.2,
  backgroundColor: Color(0x00000000),
  shadows: [
    // Soft ambient glow for contrast over any frame.
    Shadow(offset: Offset(0, 0), blurRadius: 6, color: Color(0xB3000000)),
    // Faux outline: 1px black offsets on each diagonal.
    Shadow(offset: Offset(1, 1), blurRadius: 2, color: Color(0xE6000000)),
    Shadow(offset: Offset(-1, 1), blurRadius: 2, color: Color(0xE6000000)),
    Shadow(offset: Offset(1, -1), blurRadius: 2, color: Color(0xE6000000)),
    Shadow(offset: Offset(-1, -1), blurRadius: 2, color: Color(0xE6000000)),
    // Grounding drop shadow below the glyphs.
    Shadow(offset: Offset(0, 2), blurRadius: 8, color: Color(0x99000000)),
  ],
);

/// Netflix-like placement: horizontally centered, lifted well above the bottom
/// edge so it clears the player controls when they're visible, with generous
/// side insets so lines wrap comfortably instead of spanning edge-to-edge.
const _netflixSubtitleViewConfiguration = SubtitleViewConfiguration(
  style: _netflixSubtitleStyle,
  textAlign: TextAlign.center,
  padding: EdgeInsets.fromLTRB(48, 0, 48, 56),
);

/// Renders the media_kit GPU-texture video surface for a [PlayerController].
/// E4.2 (player chrome) embeds this and overlays its own transport controls, so
/// this widget deliberately ships **no** built-in controls.
///
/// Accepts the frozen [PlayerController] type (what the provider exposes). When
/// backed by [MediaKitPlayerController] it mounts the real `Video` widget;
/// otherwise (e.g. the Phase-0 mock in tests) it shows a neutral placeholder so
/// chrome layout still works without libmpv.
class VideoView extends StatelessWidget {
  const VideoView({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.fill = Colors.black,
  });

  final PlayerController controller;
  final BoxFit fit;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c is MediaKitPlayerController) {
      return Video(
        controller: c.videoController,
        fit: fit,
        fill: fill,
        // Chrome is provided by E4.2 on top of this surface.
        controls: NoVideoControls,
        // Restyle media_kit's built-in SubtitleView to look Netflix-like.
        subtitleViewConfiguration: _netflixSubtitleViewConfiguration,
      );
    }
    return ColoredBox(color: fill);
  }
}
