import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Transparent watch-party motion used while creating or admitting a room.
class WatchPartyAnimation extends StatelessWidget {
  const WatchPartyAnimation({super.key, this.size = 180});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: Lottie.asset(
          'assets/watch_party.lottie',
          decoder: (bytes) => LottieComposition.decodeZip(
            bytes,
            filePicker: (files) => files.firstWhere(
              (file) =>
                  file.name.startsWith('animations/') &&
                  file.name.endsWith('.json'),
            ),
          ),
          fit: BoxFit.contain,
          repeat: true,
          frameRate: FrameRate.composition,
          renderCache: RenderCache.drawingCommands,
        ),
      ),
    );
  }
}
