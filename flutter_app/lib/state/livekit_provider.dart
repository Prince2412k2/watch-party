import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

/// LiveKit A/V room state (PLAN §3.8). Phase 0 models a minimal, transport-free
/// snapshot; E6 wires livekit_client (join, publish camera/mic, subscribe
/// remote tracks, device selection).
class LiveKitState {
  const LiveKitState({
    this.connected = false,
    this.micEnabled = false,
    this.cameraEnabled = false,
    this.participants = const [],
    this.error,
  });

  final bool connected;
  final bool micEnabled;
  final bool cameraEnabled;

  /// Remote (and self) participants currently in the room.
  final List<Participant> participants;
  final String? error;

  LiveKitState copyWith({
    bool? connected,
    bool? micEnabled,
    bool? cameraEnabled,
    List<Participant>? participants,
    String? error,
  }) =>
      LiveKitState(
        connected: connected ?? this.connected,
        micEnabled: micEnabled ?? this.micEnabled,
        cameraEnabled: cameraEnabled ?? this.cameraEnabled,
        participants: participants ?? this.participants,
        error: error,
      );
}

class LiveKitNotifier extends StateNotifier<LiveKitState> {
  LiveKitNotifier() : super(const LiveKitState());

  void set(LiveKitState next) => state = next;
  void setMic(bool on) => state = state.copyWith(micEnabled: on);
  void setCamera(bool on) => state = state.copyWith(cameraEnabled: on);
  void reset() => state = const LiveKitState();
}

final livekitProvider =
    StateNotifierProvider<LiveKitNotifier, LiveKitState>((ref) => LiveKitNotifier());
