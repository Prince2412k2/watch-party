import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'player_controller.dart';

/// media_kit (libmpv) implementation of the frozen [PlayerController] contract
/// (PLAN §3.3 / E4.1). Owns a single [mk.Player] + [mkv.VideoController]; the
/// controller is rendered by `video_view.dart` and driven by the sync engine
/// (E5) and player chrome (E4.2).
///
/// Track model mapping: libmpv exposes pseudo-tracks `auto`/`no` in every list;
/// those are hidden from the exposed [PlayerTracks] (selection is expressed via
/// `null` in the contract). Real tracks are kept in id→track maps so
/// [setAudioTrack]/[setSubtitle] can resolve a `PlayerTrack.id` back to the
/// libmpv track object.
class MediaKitPlayerController implements PlayerController {
  MediaKitPlayerController({bool enableHardwareAcceleration = true})
      : _player = mk.Player(),
        _enableHwAccel = enableHardwareAcceleration {
    _wire();
  }

  final mk.Player _player;
  final bool _enableHwAccel;
  mkv.VideoController? _videoController;

  /// The libmpv player, exposed for advanced callers. Not part of the frozen
  /// contract — additive.
  mk.Player get player => _player;

  /// The GPU-texture video controller, exposed for `video_view.dart` (E4.2
  /// embeds the media_kit `Video` widget with this). Created lazily on first
  /// access — it needs a real render surface, so it is only instantiated when a
  /// widget actually mounts the video (never during headless/audio-only use).
  ///
  /// enableHardwareAcceleration:true → libmpv hwdec=auto-safe (GPU decode with a
  /// safe software fallback), which is the "auto-safe" requirement. Not part of
  /// the frozen contract — additive.
  mkv.VideoController get videoController => _videoController ??= mkv.VideoController(
        _player,
        configuration: mkv.VideoControllerConfiguration(
          enableHardwareAcceleration: _enableHwAccel,
        ),
      );

  final _tracksCtrl = StreamController<PlayerTracks>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  // id → libmpv track, for resolving contract track ids back to selections.
  final Map<String, mk.AudioTrack> _audioById = {};
  final Map<String, mk.SubtitleTrack> _subtitleById = {};

  final List<StreamSubscription<dynamic>> _subs = [];
  String? _lastError;
  bool _disposed = false;

  /// Latest playback error text, or null. Additive (not in the frozen contract);
  /// E4.3 uses it for error recovery UX.
  String? get lastError => _lastError;

  /// Error text stream. Additive.
  Stream<String> get errors => _errorCtrl.stream;

  void _wire() {
    _subs.add(_player.stream.tracks.listen(_onTracks));
    _subs.add(_player.stream.error.listen((e) {
      _lastError = e;
      if (!_errorCtrl.isClosed) _errorCtrl.add(e);
    }));
  }

  void _onTracks(mk.Tracks t) {
    _audioById.clear();
    _subtitleById.clear();
    for (final a in t.audio) {
      if (!_isPseudo(a.id)) _audioById[a.id] = a;
    }
    for (final s in t.subtitle) {
      if (!_isPseudo(s.id)) _subtitleById[s.id] = s;
    }
    if (!_tracksCtrl.isClosed) {
      _tracksCtrl.add(PlayerTracks(
        video: [
          for (final v in t.video)
            if (!_isPseudo(v.id)) _mapVideo(v),
        ],
        audio: [for (final a in _audioById.values) _mapAudio(a)],
        subtitle: [for (final s in _subtitleById.values) _mapSubtitle(s)],
      ));
    }
  }

  static bool _isPseudo(String id) => id == 'auto' || id == 'no';

  static PlayerTrack _mapVideo(mk.VideoTrack v) => PlayerTrack(
        id: v.id,
        type: 'video',
        title: v.title,
        language: v.language,
        codec: v.codec,
        isDefault: v.isDefault ?? false,
      );

  static PlayerTrack _mapAudio(mk.AudioTrack a) => PlayerTrack(
        id: a.id,
        type: 'audio',
        title: a.title,
        language: a.language,
        codec: a.codec,
        isDefault: a.isDefault ?? false,
      );

  static PlayerTrack _mapSubtitle(mk.SubtitleTrack s) => PlayerTrack(
        id: s.id,
        type: 'subtitle',
        title: s.title,
        language: s.language,
        codec: s.codec,
        isDefault: s.isDefault ?? false,
      );

  @override
  Future<void> open(String url,
      {Duration startAt = Duration.zero, bool autoplay = false}) async {
    if (_disposed) return;
    // Open paused so a non-zero startAt lands before the first frame is shown;
    // libmpv queues the seek against the freshly-loaded file.
    await _player.open(mk.Media(url), play: false);
    if (startAt > Duration.zero) {
      await _player.seek(startAt);
    }
    if (autoplay) {
      await _player.play();
    }
  }

  @override
  Future<void> play() => _disposed ? Future.value() : _player.play();

  @override
  Future<void> pause() => _disposed ? Future.value() : _player.pause();

  @override
  Future<void> seek(Duration position) =>
      _disposed ? Future.value() : _player.seek(position);

  @override
  Future<void> setRate(double rate) =>
      _disposed ? Future.value() : _player.setRate(rate);

  @override
  Future<void> setVolume(double volume) =>
      _disposed ? Future.value() : _player.setVolume(volume);

  @override
  Future<void> setAudioTrack(String? trackId) {
    if (_disposed) return Future.value();
    final track =
        trackId == null ? mk.AudioTrack.auto() : _audioById[trackId];
    if (track == null) return Future.value();
    return _player.setAudioTrack(track);
  }

  @override
  Future<void> setSubtitle(String? trackId) {
    if (_disposed) return Future.value();
    // null → disable subtitles (libmpv `no`).
    final track =
        trackId == null ? mk.SubtitleTrack.no() : _subtitleById[trackId];
    if (track == null) return Future.value();
    return _player.setSubtitleTrack(track);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _tracksCtrl.close();
    await _errorCtrl.close();
    await _player.dispose();
  }

  // ── Reactive state (forwarded from media_kit) ─────────────────────────────
  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<PlayerTracks> get tracks => _tracksCtrl.stream;

  // ── Synchronous snapshots (sync engine's tight loop) ──────────────────────
  @override
  Duration get positionNow => _player.state.position;
  @override
  Duration get durationNow => _player.state.duration;
  @override
  bool get isPlayingNow => _player.state.playing;
  @override
  bool get isBufferingNow => _player.state.buffering;
}
