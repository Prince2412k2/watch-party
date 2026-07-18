import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

bool get isDesktopPlatform =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

/// Uses window fullscreen on desktop and landscape, edge-to-edge playback on
/// mobile. The iOS runner advertises both orientations, so rotation remains
/// under the player's control instead of being locked globally.
Future<void> setAppFullscreen(bool enabled) async {
  if (isDesktopPlatform) {
    await windowManager.setFullScreen(enabled);
    return;
  }
  if (!isMobilePlatform) return;

  if (enabled) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
