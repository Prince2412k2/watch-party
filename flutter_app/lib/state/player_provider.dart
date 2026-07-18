import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/media_kit_player_controller.dart';
import '../player/player_controller.dart';

/// The active [PlayerController] (PLAN §3.8). E4.1 provides the real
/// media_kit-backed [MediaKitPlayerController]. The controller is disposed when
/// the provider is torn down.
final playerControllerProvider = Provider<PlayerController>((ref) {
  final controller = MediaKitPlayerController();
  controller.prepareVideoOutput();
  ref.onDispose(controller.dispose);
  return controller;
});
