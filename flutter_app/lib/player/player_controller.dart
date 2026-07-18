import 'dart:async';

/// A selectable audio/subtitle/video track exposed by the player. Intentionally
/// player-agnostic (media_kit maps onto this in E4).
class PlayerTrack {
  const PlayerTrack({
    required this.id,
    required this.type,
    this.title,
    this.language,
    this.codec,
    this.isDefault = false,
    this.jellyfinIndex,
  });

  /// Opaque id understood by the concrete player.
  final String id;

  /// 'video' | 'audio' | 'subtitle'
  final String type;
  final String? title;
  final String? language;
  final String? codec;
  final bool isDefault;
  final int? jellyfinIndex;
}

/// Snapshot of the available track lists, emitted on the [PlayerController.tracks]
/// stream whenever the media's track set changes.
class PlayerTracks {
  const PlayerTracks({
    this.video = const [],
    this.audio = const [],
    this.subtitle = const [],
  });

  final List<PlayerTrack> video;
  final List<PlayerTrack> audio;
  final List<PlayerTrack> subtitle;
}

/// FROZEN CONTRACT (PLAN §3.3). The playback surface the sync engine (E5) drives
/// and the player chrome (E4.2) renders. Deliberately duck-types the subset of
/// HTMLMediaElement the web `useSyncPlay` relied on: position/duration/playing +
/// play/pause/seek/rate. E4.1 implements this on media_kit.
abstract class PlayerController {
  /// Open a media URL (signed native stream-url or a local file path).
  /// [startAt] seeks before playback; [autoplay] begins immediately.
  Future<void> open(String url, {Duration startAt = Duration.zero, bool autoplay = false});

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// 1.0 = normal speed.
  Future<void> setRate(double rate);

  /// 0.0–100.0 (media_kit volume scale).
  Future<void> setVolume(double volume);

  /// Select an audio track by [PlayerTrack.id], or null for auto/none.
  Future<void> setAudioTrack(String? trackId);

  /// Select a subtitle track by [PlayerTrack.id], or null to disable.
  Future<void> setSubtitle(String? trackId);

  /// Release native resources. The controller is unusable afterward.
  Future<void> dispose();

  // ── Reactive state ────────────────────────────────────────────────────
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get buffering;
  Stream<bool> get playing;
  Stream<bool> get completed;
  Stream<PlayerTracks> get tracks;

  // ── Latest synchronous snapshots (for the sync engine's tight loop) ────
  Duration get positionNow;
  Duration get durationNow;
  bool get isPlayingNow;
  bool get isBufferingNow;
}
