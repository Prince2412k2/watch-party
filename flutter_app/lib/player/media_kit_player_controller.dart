import 'dart:async';
import 'dart:io';

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
  // Hardware rendering avoids copying every decoded frame through a software
  // texture. WP_HWACCEL=0 retains the fallback for Linux/Mesa configurations
  // where media_kit's isolated EGL context is unstable.
  //
  // Hardware *decoding* is a SEPARATE concern and stays ON regardless (see
  // [videoController]'s `hwdec`): the GPU decodes, frames are copied back to
  // system memory. Without this, pure-software decode can't keep realtime and
  // playback runs in slow-motion.
  // Direct-play streams the source file at its native bitrate (no transcode,
  // no adaptive-bitrate ladder — see docs/native/PLAN.md §4.3), so the only
  // lever against a variable remote connection is how much libmpv reads
  // ahead. media_kit's default `bufferSize` (32MiB, ~a few seconds at 4K
  // bitrates) drains fast on a WAN link with real jitter; 128MiB gives a
  // brief bandwidth dip enough runway to not surface as a visible stall.
  static const int _bufferSize = 128 * 1024 * 1024;

  MediaKitPlayerController({bool? enableHardwareAcceleration})
    : _player = mk.Player(
        configuration: const mk.PlayerConfiguration(
          bufferSize: _bufferSize,
          libass: true,
        ),
      ),
      _enableHwAccel =
          enableHardwareAcceleration ??
          (Platform.environment['WP_HWACCEL'] != '0') {
    _wire();
    unawaited(_applyReadAheadProperties());
  }

  // `bufferSize` above only sizes media_kit's in-memory network buffer; it
  // does not tell libmpv's demuxer how far ahead of playback position to
  // prefetch. Left at mpv's defaults, the demuxer stops reading ahead well
  // short of a full movie, so a long direct-play stalls partway through even
  // though the network buffer itself never filled up. These four properties
  // (set once, via the same raw-property path as [_setMpvProperty]) push that
  // prefetch distance out to cover a whole movie's remote fetch instead:
  // `cache`/`cache-secs` turn on and size mpv's own stream cache,
  // `demuxer-max-bytes`/`demuxer-max-back-bytes` raise the forward/backward
  // demuxer cache ceilings so the readahead has somewhere to land.
  Future<void> _applyReadAheadProperties() async {
    await _setMpvProperty('cache', 'yes');
    await _setMpvProperty('cache-secs', '300');
    await _setMpvProperty('demuxer-readahead-secs', '300');
    await _setMpvProperty('demuxer-max-bytes', '512MiB');
    await _setMpvProperty('demuxer-max-back-bytes', '128MiB');
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
  /// `hwdec: 'auto-safe'` forces GPU decode using only methods that copy frames
  /// back to system memory — so it works with the opt-in software-rendering
  /// fallback and keeps playback at realtime instead of slow-motion.
  /// (media_kit's default `hwdec` is `'auto'`, which can pick a GPU-surface
  /// method that doesn't copy back and effectively falls back to slow software
  /// decode under a software VO.) When HW rendering is enabled, `'auto'` lets
  /// libmpv keep frames on the GPU. Not part of the frozen contract — additive.
  mkv.VideoController get videoController =>
      _videoController ??= mkv.VideoController(
        _player,
        configuration: mkv.VideoControllerConfiguration(
          enableHardwareAcceleration: _enableHwAccel,
          hwdec: _enableHwAccel ? 'auto' : 'auto-safe',
        ),
      );

  final _tracksCtrl = StreamController<PlayerTracks>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  // id → libmpv track, for resolving contract track ids back to selections.
  final Map<String, mk.AudioTrack> _audioById = {};
  final Map<String, mk.SubtitleTrack> _subtitleById = {};
  PlayerTracks _latestTracks = const PlayerTracks();

  final List<StreamSubscription<dynamic>> _subs = [];
  String? _lastError;
  bool _disposed = false;

  /// Latest playback error text, or null. Additive (not in the frozen contract);
  /// E4.3 uses it for error recovery UX.
  String? get lastError => _lastError;

  /// Error text stream. Additive.
  Stream<String> get errors => _errorCtrl.stream;

  /// Most recent track list, including events emitted before the chrome mounts.
  PlayerTracks get latestTracks => _latestTracks;

  // ── Current selection / mixer snapshots (additive) ────────────────────────
  // The frozen contract expresses track *availability* via [tracks] and lets
  // callers *set* a selection, but never surfaces what libmpv currently has
  // selected. The chrome needs that to render an accurate checkmark, so it is
  // exposed here (read off `player.state.track`). Pseudo picks (`auto`/`no`)
  // map to null, matching how the contract represents "auto/none".

  /// Currently-selected audio track id, or null when libmpv's pick is the
  /// pseudo `auto` track (no explicit selection). Additive.
  String? get currentAudioTrackId {
    final id = _player.state.track.audio.id;
    return _isPseudo(id) ? null : id;
  }

  /// Currently-selected subtitle track id, or null when subtitles are off
  /// (libmpv `no`) or unset (`auto`). Additive.
  String? get currentSubtitleTrackId {
    final id = _player.state.track.subtitle.id;
    return _isPseudo(id) ? null : id;
  }

  /// Current output volume on media_kit's 0–100 scale. Additive — lets the
  /// chrome initialise its slider to the real level instead of assuming 100.
  double get volumeNow => _player.state.volume;

  /// Current playback rate (1.0 = normal). Additive.
  double get rateNow => _player.state.rate;

  // ── Hardware/software decode toggle (additive) ────────────────────────────
  // libmpv's `hwdec` property is runtime-settable, so the chrome can flip
  // between GPU and CPU decode without reopening the file. We mirror the
  // construction-time rationale (see [videoController]): the "on" value is
  // `auto-safe` — GPU decode via copy-back methods that stay compatible with
  // the software-rendering fallback and keep playback realtime. "off" is `no`
  // (pure software decode). Tracked in a field so the UI can render a
  // checkmark; seeded from [_enableHwAccel].
  late bool _hwdecEnabled = _enableHwAccel;

  /// Whether hardware (GPU) video decoding is currently enabled. Additive.
  bool get hardwareDecodingEnabled => _hwdecEnabled;

  /// Toggle hardware vs software video decoding at runtime via libmpv's
  /// `hwdec` property. Additive (not in the frozen contract).
  Future<void> setHardwareDecoding(bool enabled) async {
    if (_disposed) return;
    _hwdecEnabled = enabled;
    await _setMpvProperty('hwdec', enabled ? 'auto-safe' : 'no');
  }

  /// Set a raw libmpv property. media_kit only exposes arbitrary-property
  /// access on the native platform player (`NativePlayer.setProperty`), reached
  /// via `player.platform`; the abstract [mk.Player] surface has no generic
  /// setter. No-op if the platform player isn't the native one.
  Future<void> _setMpvProperty(String property, String value) async {
    final platform = _player.platform;
    if (platform is mk.NativePlayer) {
      await platform.setProperty(property, value);
    }
  }

  // ── Subtitle appearance (additive) ────────────────────────────────────────
  // Backed by libmpv properties: `sub-scale` (size), `sub-pos` (0–150, 100 =
  // bottom), `sub-delay` (seconds, may be negative). Tracked in fields so the
  // settings panel can reflect current values.
  double _subScale = 1.0;
  int _subPos = 100;
  double _subDelay = 0.0;
  String _subFont = 'sans-serif';

  /// Current subtitle scale (1.0 = default). Additive.
  double get subtitleScale => _subScale;

  /// Current subtitle vertical position (0–150; 100 = bottom). Additive.
  int get subtitlePosition => _subPos;

  /// Current subtitle timing offset in seconds (may be negative). Additive.
  double get subtitleDelay => _subDelay;

  String get subtitleFont => _subFont;

  /// Set subtitle scale via libmpv `sub-scale`. Additive.
  Future<void> setSubtitleScale(double scale) async {
    if (_disposed) return;
    _subScale = scale;
    await _setMpvProperty('sub-scale', scale.toString());
  }

  /// Set subtitle vertical position via libmpv `sub-pos` (0–150). Additive.
  Future<void> setSubtitlePosition(int pos) async {
    if (_disposed) return;
    _subPos = pos;
    await _setMpvProperty('sub-pos', pos.toString());
  }

  /// Set subtitle timing offset in seconds via libmpv `sub-delay`. Additive.
  Future<void> setSubtitleDelay(double seconds) async {
    if (_disposed) return;
    _subDelay = seconds;
    await _setMpvProperty('sub-delay', seconds.toString());
  }

  Future<void> setSubtitleFont(String font) async {
    if (_disposed) return;
    _subFont = font;
    await _setMpvProperty('sub-font', font);
  }

  /// Load an external subtitle from raw text (SRT / WebVTT / ASS) and select
  /// it. This is how subtitles reach the player without transcoding: the video
  /// is direct-played untouched, and libmpv side-loads the subtitle and times
  /// it against playback by the subtitle's own timestamps — so it follows the
  /// video (including seeks) automatically. The added track shows up on the
  /// next [tracks] emission, so the chrome's subtitle menu can re-select it.
  /// Additive (not in the frozen contract).
  Future<void> addExternalSubtitle(
    String data, {
    String? title,
    String? language,
  }) async {
    if (_disposed) return;
    await _player.setSubtitleTrack(
      mk.SubtitleTrack.data(data, title: title, language: language),
    );
  }

  void _wire() {
    _subs.add(_player.stream.tracks.listen(_onTracks));
    _subs.add(
      _player.stream.error.listen((e) {
        _lastError = e;
        if (!_errorCtrl.isClosed) _errorCtrl.add(e);
      }),
    );
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
    _latestTracks = PlayerTracks(
      video: [
        for (final v in t.video)
          if (!_isPseudo(v.id)) _mapVideo(v),
      ],
      audio: [for (final a in _audioById.values) _mapAudio(a)],
      subtitle: [for (final s in _subtitleById.values) _mapSubtitle(s)],
    );
    if (!_tracksCtrl.isClosed) _tracksCtrl.add(_latestTracks);
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
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    bool autoplay = false,
  }) async {
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
    final track = trackId == null ? mk.AudioTrack.auto() : _audioById[trackId];
    if (track == null) return Future.value();
    return _player.setAudioTrack(track);
  }

  @override
  Future<void> setSubtitle(String? trackId) {
    if (_disposed) return Future.value();
    // null → disable subtitles (libmpv `no`).
    final track = trackId == null
        ? mk.SubtitleTrack.no()
        : _subtitleById[trackId];
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
