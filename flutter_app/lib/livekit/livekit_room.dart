// E6 T6.1 — LiveKit A/V room service.
//
// Wraps `livekit_client`'s [lk.Room] with the connect/publish/subscribe
// sequence proven in the de-risk spike (`spike/lib/main.dart`): connect first,
// then enable mic/camera on the local participant, and refresh a flat
// snapshot of tracks off every relevant room event. Callers (the
// `livekitProvider`, in this app) get a stream of [LiveKitRoomSnapshot] plus
// imperative controls; nothing here touches Riverpod or UI.
library;

import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart' as logging;

final _log = logging.Logger('LiveKitRoomService');

/// One tile's worth of state — either the local participant or a remote one.
class ParticipantTrack {
  const ParticipantTrack({
    required this.identity,
    required this.name,
    required this.isLocal,
    this.videoTrack,
    this.audioMuted = true,
    this.videoMuted = true,
    this.isSpeaking = false,
  });

  final String identity;
  final String name;
  final bool isLocal;
  final lk.VideoTrack? videoTrack;

  /// True when the participant has no live mic track (or it's disabled).
  final bool audioMuted;

  /// True when the participant has no live camera track (or it's disabled).
  final bool videoMuted;
  final bool isSpeaking;
}

/// Immutable snapshot of room state, re-emitted on every relevant LiveKit
/// event so listeners can just re-render.
class LiveKitRoomSnapshot {
  const LiveKitRoomSnapshot({
    this.connectionState = lk.ConnectionState.disconnected,
    this.participants = const [],
    this.micEnabled = false,
    this.cameraEnabled = false,
    this.error,
  });

  final lk.ConnectionState connectionState;
  final List<ParticipantTrack> participants;
  final bool micEnabled;
  final bool cameraEnabled;
  final String? error;

  bool get connected => connectionState == lk.ConnectionState.connected;

  LiveKitRoomSnapshot copyWith({
    lk.ConnectionState? connectionState,
    List<ParticipantTrack>? participants,
    bool? micEnabled,
    bool? cameraEnabled,
    String? error,
  }) =>
      LiveKitRoomSnapshot(
        connectionState: connectionState ?? this.connectionState,
        participants: participants ?? this.participants,
        micEnabled: micEnabled ?? this.micEnabled,
        cameraEnabled: cameraEnabled ?? this.cameraEnabled,
        error: error,
      );
}

/// Service wrapping a single `livekit_client` [lk.Room] lifecycle: connect,
/// publish/unpublish camera + mic, device selection, mute toggles, and a
/// snapshot stream for the UI. One instance per party session; call
/// [dispose] on leave.
class LiveKitRoomService {
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  final _controller = StreamController<LiveKitRoomSnapshot>.broadcast();
  LiveKitRoomSnapshot _snapshot = const LiveKitRoomSnapshot();

  /// True while the local participant chooses to hide their own tile from
  /// the grid (does NOT unpublish — camera keeps flowing to remotes).
  bool hideSelf = false;

  Stream<LiveKitRoomSnapshot> get snapshots => _controller.stream;
  LiveKitRoomSnapshot get snapshot => _snapshot;
  lk.Room? get room => _room;

  void _emit(LiveKitRoomSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Connect to [url] with [token], mirroring the spike's proven sequence:
  /// register listeners, connect, then best-effort enable mic + camera.
  /// Errors enabling a device are recorded in [LiveKitRoomSnapshot.error]
  /// but do not fail the connect.
  Future<void> connect(
    String url,
    String token, {
    bool enableMic = true,
    bool enableCamera = true,
  }) async {
    await disconnect();

    final room = lk.Room();
    _room = room;
    _emit(_snapshot.copyWith(connectionState: lk.ConnectionState.connecting));

    final listener = room.createListener();
    _listener = listener;
    listener
      ..on<lk.RoomConnectedEvent>((_) {
        _log.info('RoomConnectedEvent');
        _refresh();
      })
      ..on<lk.RoomDisconnectedEvent>((e) {
        _log.info('RoomDisconnectedEvent reason=${e.reason}');
        _emit(_snapshot.copyWith(
          connectionState: lk.ConnectionState.disconnected,
        ));
      })
      ..on<lk.RoomReconnectingEvent>((_) => _refresh())
      ..on<lk.RoomReconnectedEvent>((_) => _refresh())
      ..on<lk.LocalTrackPublishedEvent>((_) => _refresh())
      ..on<lk.LocalTrackUnpublishedEvent>((_) => _refresh())
      ..on<lk.TrackSubscribedEvent>((_) => _refresh())
      ..on<lk.TrackUnsubscribedEvent>((_) => _refresh())
      ..on<lk.TrackMutedEvent>((_) => _refresh())
      ..on<lk.TrackUnmutedEvent>((_) => _refresh())
      ..on<lk.ParticipantConnectedEvent>((_) => _refresh())
      ..on<lk.ParticipantDisconnectedEvent>((_) => _refresh())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _refresh());

    try {
      await room.connect(url, token);
      _log.info('connect() returned, state=${room.connectionState}');
    } catch (e, st) {
      _log.severe('connect() failed: $e', e, st);
      _emit(_snapshot.copyWith(
        connectionState: lk.ConnectionState.disconnected,
        error: 'connect failed: $e',
      ));
      rethrow;
    }

    if (enableMic) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(true);
      } catch (e) {
        _log.warning('mic enable failed: $e');
        _emit(_snapshot.copyWith(error: 'mic enable failed: $e'));
      }
    }
    if (enableCamera) {
      try {
        await room.localParticipant?.setCameraEnabled(true);
      } catch (e) {
        _log.warning('camera enable failed: $e');
        _emit(_snapshot.copyWith(error: 'camera enable failed: $e'));
      }
    }
    _refresh();
  }

  /// Toggle the local microphone.
  Future<void> setMicEnabled(bool enabled) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    await lp.setMicrophoneEnabled(enabled);
    _refresh();
  }

  /// Toggle the local camera.
  Future<void> setCameraEnabled(bool enabled) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    await lp.setCameraEnabled(enabled);
    _refresh();
  }

  /// Hide the local tile from the grid without unpublishing (so remotes keep
  /// seeing/hearing you — this only affects local UI).
  void setHideSelf(bool hide) {
    hideSelf = hide;
    _refresh();
  }

  /// Enumerate available camera devices.
  Future<List<lk.MediaDevice>> cameraDevices() =>
      lk.Hardware.instance.videoInputs();

  /// Enumerate available microphone devices.
  Future<List<lk.MediaDevice>> microphoneDevices() =>
      lk.Hardware.instance.audioInputs();

  /// Switch the active camera device by deviceId.
  Future<void> selectCameraDevice(String deviceId) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    for (final pub in lp.videoTrackPublications) {
      final track = pub.track;
      if (track is lk.LocalVideoTrack) {
        await track.switchCamera(deviceId);
      }
    }
    _refresh();
  }

  /// Switch the active microphone device by deviceId.
  Future<void> selectMicrophoneDevice(String deviceId) async {
    final devices = await microphoneDevices();
    final match = devices.where((d) => d.deviceId == deviceId);
    if (match.isEmpty) return;
    await lk.Hardware.instance.selectAudioInput(match.first);
    _refresh();
  }

  void _refresh() {
    final room = _room;
    if (room == null) return;

    final activeSpeakerIds =
        room.activeSpeakers.map((p) => p.identity).toSet();
    final tracks = <ParticipantTrack>[];

    final lp = room.localParticipant;
    if (lp != null) {
      tracks.add(_toParticipantTrack(
        identity: lp.identity,
        name: lp.name.isNotEmpty ? lp.name : lp.identity,
        isLocal: true,
        videoPubs: lp.videoTrackPublications,
        audioPubs: lp.audioTrackPublications,
        isSpeaking: activeSpeakerIds.contains(lp.identity),
      ));
    }
    for (final p in room.remoteParticipants.values) {
      tracks.add(_toParticipantTrack(
        identity: p.identity,
        name: p.name.isNotEmpty ? p.name : p.identity,
        isLocal: false,
        videoPubs: p.videoTrackPublications,
        audioPubs: p.audioTrackPublications,
        isSpeaking: activeSpeakerIds.contains(p.identity),
      ));
    }

    _emit(_snapshot.copyWith(
      connectionState: room.connectionState,
      participants: tracks,
      micEnabled: room.localParticipant?.isMicrophoneEnabled() ?? false,
      cameraEnabled: room.localParticipant?.isCameraEnabled() ?? false,
    ));
  }

  ParticipantTrack _toParticipantTrack({
    required String identity,
    required String name,
    required bool isLocal,
    required List<lk.TrackPublication> videoPubs,
    required List<lk.TrackPublication> audioPubs,
    required bool isSpeaking,
  }) {
    lk.VideoTrack? videoTrack;
    var videoMuted = true;
    for (final pub in videoPubs) {
      final t = pub.track;
      if (t is lk.VideoTrack && !pub.muted) {
        videoTrack = t;
        videoMuted = false;
        break;
      }
    }
    var audioMuted = true;
    for (final pub in audioPubs) {
      if (!pub.muted) {
        audioMuted = false;
        break;
      }
    }
    return ParticipantTrack(
      identity: identity,
      name: name,
      isLocal: isLocal,
      videoTrack: videoTrack,
      audioMuted: audioMuted,
      videoMuted: videoMuted,
      isSpeaking: isSpeaking,
    );
  }

  /// Leave the room (if connected) without disposing the service — safe to
  /// call [connect] again afterward.
  Future<void> disconnect() async {
    final room = _room;
    _room = null;
    _listener?.dispose();
    _listener = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {
        // best-effort
      }
    }
  }

  /// Tear down for good — disconnect and close the snapshot stream.
  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
