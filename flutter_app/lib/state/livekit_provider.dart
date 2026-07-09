import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../livekit/livekit_room.dart';
import '../models/models.dart';

/// LiveKit A/V room state (PLAN §3.8). Real implementation on top of
/// [LiveKitRoomService] (E6): joins with a backend-issued token, tracks
/// connection state, and exposes participants as the frozen [Participant]
/// model plus render-ready tracks for [CameraGrid].
class LiveKitState {
  const LiveKitState({
    this.connected = false,
    this.connecting = false,
    this.micEnabled = false,
    this.cameraEnabled = false,
    this.hideSelf = false,
    this.participants = const [],
    this.tracks = const [],
    this.error,
  });

  final bool connected;
  final bool connecting;
  final bool micEnabled;
  final bool cameraEnabled;
  final bool hideSelf;

  /// Remote (and self) participants currently in the room, frozen model form
  /// — what E5's party roster / non-A/V UI consumes.
  final List<Participant> participants;

  /// Render-ready per-participant track state — what [CameraGrid] consumes.
  final List<ParticipantTrack> tracks;
  final String? error;

  LiveKitState copyWith({
    bool? connected,
    bool? connecting,
    bool? micEnabled,
    bool? cameraEnabled,
    bool? hideSelf,
    List<Participant>? participants,
    List<ParticipantTrack>? tracks,
    String? error,
  }) =>
      LiveKitState(
        connected: connected ?? this.connected,
        connecting: connecting ?? this.connecting,
        micEnabled: micEnabled ?? this.micEnabled,
        cameraEnabled: cameraEnabled ?? this.cameraEnabled,
        hideSelf: hideSelf ?? this.hideSelf,
        participants: participants ?? this.participants,
        tracks: tracks ?? this.tracks,
        error: error,
      );
}

class LiveKitNotifier extends StateNotifier<LiveKitState> {
  LiveKitNotifier(this._service) : super(const LiveKitState()) {
    _sub = _service.snapshots.listen(_onSnapshot);
  }

  final LiveKitRoomService _service;
  late final StreamSubscription<LiveKitRoomSnapshot> _sub;

  void _onSnapshot(LiveKitRoomSnapshot s) {
    state = state.copyWith(
      connected: s.connected,
      connecting: s.connectionState == lk.ConnectionState.connecting,
      micEnabled: s.micEnabled,
      cameraEnabled: s.cameraEnabled,
      tracks: s.participants,
      participants: s.participants
          .map((t) => Participant(userId: t.identity, name: t.name))
          .toList(),
      error: s.error,
    );
  }

  /// Join the room at [url] with [token] (from
  /// `ApiClient.livekitToken(partyId)`). Safe to call again to rejoin.
  Future<void> connect(String url, String token) async {
    state = state.copyWith(connecting: true, error: null);
    try {
      await _service.connect(url, token);
    } catch (e) {
      state = state.copyWith(connecting: false, error: '$e');
    }
  }

  Future<void> leave() => _service.disconnect();

  Future<void> setMic(bool on) => _service.setMicEnabled(on);
  Future<void> setCamera(bool on) => _service.setCameraEnabled(on);

  void setHideSelf(bool hide) {
    _service.setHideSelf(hide);
    state = state.copyWith(hideSelf: hide);
  }

  Future<List<lk.MediaDevice>> cameraDevices() => _service.cameraDevices();
  Future<List<lk.MediaDevice>> microphoneDevices() =>
      _service.microphoneDevices();
  Future<void> selectCamera(String deviceId) =>
      _service.selectCameraDevice(deviceId);
  Future<void> selectMicrophone(String deviceId) =>
      _service.selectMicrophoneDevice(deviceId);

  void reset() => state = const LiveKitState();

  @override
  void dispose() {
    _sub.cancel();
    _service.dispose();
    super.dispose();
  }
}

/// The underlying room service — one per app lifetime; E5's party screen
/// calls `ref.read(livekitProvider.notifier).connect(url, token)` once it has
/// a token from `ApiClient.livekitToken(partyId)`.
final livekitRoomServiceProvider =
    Provider<LiveKitRoomService>((ref) => LiveKitRoomService());

final livekitProvider = StateNotifierProvider<LiveKitNotifier, LiveKitState>(
  (ref) => LiveKitNotifier(ref.watch(livekitRoomServiceProvider)),
);
