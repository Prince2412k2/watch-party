import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/mock_player_controller.dart';
import '../player/player_controller.dart';

/// The active [PlayerController] (PLAN §3.8). Phase 0 provides a
/// [MockPlayerController]; E4 overrides with the media_kit-backed impl. The
/// controller is disposed when the provider is torn down.
final playerControllerProvider = Provider<PlayerController>((ref) {
  final controller = MockPlayerController();
  ref.onDispose(controller.dispose);
  return controller;
});
