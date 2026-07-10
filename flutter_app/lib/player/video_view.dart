import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'media_kit_player_controller.dart';
import 'player_controller.dart';

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
      );
    }
    return ColoredBox(color: fill);
  }
}
