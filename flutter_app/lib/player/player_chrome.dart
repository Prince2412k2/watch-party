import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cache/range_cache_store.dart' show CachedSpan;
import '../data/api_client.dart';
import '../models/playback_info.dart';
import '../models/subtitle_preferences.dart';
import '../models/trickplay_manifest.dart';
import '../ui/ui.dart';
import 'media_kit_player_controller.dart';
import 'party_track_mapping.dart';
import 'player_controller.dart';
import 'subtitle_cues.dart';
import 'trickplay_preview.dart';

/// The minimal, monochrome transport bar for [PlayerController] (E4.2/E4.3).
/// Sits as an overlay on top of `VideoView` — play/pause, scrubber, time,
/// volume, decode toggle, fullscreen, and audio/subtitle track menus (plus a
/// subtitle appearance panel). Reads state off the controller's streams; writes
/// back through its methods.
///
/// Auto-hides after a short idle period while playing (mouse movement / tap
/// wakes it), matches the web `DesktopControlBar`'s flat, single-row layout
/// and neutral buffering spinner (`app/client/src/components/Player.jsx`).
///
/// [canControl] gates interactivity: a `false` value (E5's no-control guest)
/// renders the same bar read-only — no thumb drag, no button taps — mirroring
/// `canControl` gating in the web player.
/// Near-black translucent scrims for the chrome edges (design system: flat,
/// no gradients/glass). Both are [AppColors.bg] at different opacities.
const Color _kChromeScrim = Color(0xB30A0A0B); // top bar (~70%)
const Color _kBufferingScrim = Color(0x8C0A0A0B); // centered spinner backdrop

class PlayerChrome extends StatefulWidget {
  const PlayerChrome({
    super.key,
    required this.controller,
    this.canControl = true,
    this.title,
    this.onBack,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.idleTimeout = const Duration(seconds: 3),
    this.onSeek,
    this.itemId,
    this.mediaSourceId,
    this.apiClient,
    this.preferredSubtitleStreamIndex,
    this.partyPlayback,
    this.subtitlePreferences,
    this.canManagePartyMedia = true,
    this.onSetPlaybackTracks,
    this.onSetSubtitlePreferences,
    this.cachedSpans,
    this.visible,
    this.onWake,
    this.onToggleChat,
    this.onPushToTalkStart,
    this.onPushToTalkStop,
  });

  final PlayerController controller;
  final bool canControl;
  final String? title;
  final VoidCallback? onBack;

  /// When non-null, chrome visibility is owned by the PARENT (the party screen's
  /// single unified auto-hide) and this widget stops running its own idle timer
  /// — it renders at [visible] and forwards activity via [onWake]. Null (solo
  /// playback / detail screen) keeps the built-in idle behaviour intact.
  final bool? visible;
  final VoidCallback? onWake;

  /// Party-only key bindings, independent of playback control: `c` toggles chat,
  /// hold-`T` is push-to-talk. Null in solo playback (the keys do nothing).
  final VoidCallback? onToggleChat;
  final VoidCallback? onPushToTalkStart;
  final VoidCallback? onPushToTalkStop;

  /// Cached ("downloaded") byte-range spans for [itemId], as 0..1 fractions
  /// of total length, painted behind the scrubber's play-progress as a
  /// buffered-style indicator. Null for the offline-local-file playback path
  /// (nothing to show — the whole file is already local) and for
  /// tests/mocks that don't wire a cache proxy.
  final ValueListenable<List<CachedSpan>>? cachedSpans;

  /// Fired (in addition to the local seek) whenever the user scrubs or uses a
  /// keyboard seek. In a watch party this is wired to the sync engine's
  /// `requestSeek` so the host's seek is authored to the server and mirrored to
  /// every other client (web + Flutter). Null for solo playback (local only).
  final ValueChanged<Duration>? onSeek;
  final String? itemId;
  final String? mediaSourceId;
  final ApiClient? apiClient;
  final int? preferredSubtitleStreamIndex;
  final PlaybackInfo? partyPlayback;
  final SubtitlePreferences? subtitlePreferences;
  final bool canManagePartyMedia;
  final void Function(int? audioStreamIndex, int subtitleStreamIndex)?
  onSetPlaybackTracks;
  final ValueChanged<SubtitlePreferences>? onSetSubtitlePreferences;

  /// Host owns fullscreen (window-level); chrome just renders the affordance.
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  final Duration idleTimeout;

  @override
  State<PlayerChrome> createState() => _PlayerChromeState();
}

class _PlayerChromeState extends State<PlayerChrome> {
  final _focusNode = FocusNode();

  bool _visible = true;
  Timer? _idleTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  PlayerTracks _tracks = const PlayerTracks();
  List<PlayerTrack> _externalSubtitles = const [];
  final Map<String, PlaybackTrack> _externalSubtitleById = {};
  final Map<String, Future<String>> _externalSubtitleContent = {};
  final Map<String, String> _loadedExternalSubtitleTrackIds = {};
  int _subtitleSelectionVersion = 0;
  List<SubtitleCue> _subtitleCues = const [];

  double _volume = 100;

  /// Volume to restore when unmuting (last non-zero level the user chose).
  double _preMuteVolume = 100;
  String? _selectedAudio;
  String? _selectedSubtitle;

  // Decode + subtitle-appearance state — only meaningful for the concrete
  // MediaKitPlayerController (seeded in initState when it's the live player).
  bool _hwDecoding = true;
  double _subScale = 1.0;
  int _subPos = 100;
  double _subDelay = 0.0;
  String _subFont = 'sans-serif';
  String _subColor = '#FFFFFF';
  int _subBackgroundOpacity = 65;
  PlaybackInfo? _playbackInfo;

  Duration? _dragPosition;
  Duration? _previewPosition;
  double _previewFraction = 0;
  TrickplayManifest? _trickplay;

  final _subs = <StreamSubscription<dynamic>>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _position = c.positionNow;
    _duration = c.durationNow;
    _playing = c.isPlayingNow;
    _buffering = c.isBufferingNow;

    // Seed the mixer/track UI from the real player state so the controls match
    // what's actually playing (rather than assuming 100% / 1.0× / no track).
    if (c is MediaKitPlayerController) {
      _error = c.lastError;
      _tracks = c.latestTracks;
      _volume = c.volumeNow;
      _preMuteVolume = _volume > 0 ? _volume : 100;
      _selectedAudio = c.currentAudioTrackId;
      _selectedSubtitle = c.currentSubtitleTrackId;
      _hwDecoding = c.hardwareDecodingEnabled;
      _subScale = c.subtitleScale;
      _subPos = c.subtitlePosition;
      _subDelay = c.subtitleDelay;
      _subFont = c.subtitleFont;
      _subColor = c.subtitleColor;
      _subBackgroundOpacity = c.subtitleBackgroundOpacity;
    }

    _subs.add(c.position.listen((p) => setState(() => _position = p)));
    _subs.add(c.duration.listen((d) => setState(() => _duration = d)));
    _subs.add(
      c.playing.listen((p) {
        setState(() => _playing = p);
        _scheduleIdle();
      }),
    );
    _subs.add(c.buffering.listen((b) => setState(() => _buffering = b)));
    _subs.add(c.completed.listen((v) => setState(() => _completed = v)));
    _subs.add(
      c.tracks.listen((t) {
        setState(() {
          _tracks = t;
          // Re-read the real selection each time the track set changes (a fresh
          // file resets libmpv's default audio/subtitle pick).
          if (c is MediaKitPlayerController) {
            _selectedAudio = c.currentAudioTrackId;
            if (!_externalSubtitleById.containsKey(_selectedSubtitle)) {
              _selectedSubtitle = c.currentSubtitleTrackId;
            }
          }
        });
        _applyCanonicalTracks();
      }),
    );

    // media_kit surfaces decode/network errors on an additive `errors` stream
    // (not part of the frozen contract) — drive the E4.3 error overlay off it
    // when the concrete controller supports it.
    if (c is MediaKitPlayerController) {
      _subs.add(c.errors.listen((e) => setState(() => _error = e)));
    }

    _scheduleIdle();
    _loadTrickplay();
    _loadExternalSubtitles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyCanonicalSubtitlePreferences();
      _applyCanonicalTracks();
    });
  }

  @override
  void didUpdateWidget(PlayerChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      setState(() {
        _subtitleCues = const [];
        _selectedSubtitle = null;
      });
    }
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.mediaSourceId != widget.mediaSourceId ||
        oldWidget.apiClient != widget.apiClient) {
      _loadTrickplay();
      _loadExternalSubtitles();
    }
    if (oldWidget.partyPlayback != widget.partyPlayback) {
      _playbackInfo = widget.partyPlayback;
      _applyCanonicalTracks();
    }
    if (oldWidget.subtitlePreferences != widget.subtitlePreferences) {
      _applyCanonicalSubtitlePreferences();
    }
  }

  Future<void> _loadTrickplay() async {
    final itemId = widget.itemId;
    final mediaSourceId = widget.mediaSourceId;
    final apiClient = widget.apiClient;
    if (mounted) setState(() => _trickplay = null);
    if (itemId == null || apiClient == null) {
      if (mounted) setState(() => _trickplay = null);
      return;
    }
    try {
      final manifest = await apiClient.trickplay(
        itemId,
        mediaSourceId: mediaSourceId,
      );
      if (mounted &&
          widget.itemId == itemId &&
          widget.mediaSourceId == mediaSourceId &&
          widget.apiClient == apiClient) {
        setState(() => _trickplay = manifest);
      }
    } catch (_) {
      if (mounted && widget.itemId == itemId) {
        setState(() => _trickplay = null);
      }
    }
  }

  static String _externalSubtitleId(int index) => 'jellyfin-external:$index';

  List<PlayerTrack> get _visibleSubtitleTracks {
    final externalSignatures = _externalSubtitles
        .map(_subtitleTrackSignature)
        .toSet();
    final seen = <String>{};
    return [
      for (final track in _tracks.subtitle)
        if (!_loadedExternalSubtitleTrackIds.containsValue(track.id) &&
            !externalSignatures.contains(_subtitleTrackSignature(track)) &&
            seen.add(_subtitleTrackSignature(track)))
          track,
      for (final track in _externalSubtitles)
        if (seen.add(_subtitleTrackSignature(track))) track,
    ];
  }

  static String _subtitleTrackSignature(PlayerTrack track) => [
    track.title,
    track.language,
    track.codec,
  ].map((value) => value?.trim().toLowerCase() ?? '').join('|');

  Future<String> _contentForExternal(PlaybackTrack track) {
    final itemId = widget.itemId;
    final api = widget.apiClient;
    if (itemId == null || api == null) {
      return Future<String>.error(StateError('Subtitle source unavailable'));
    }
    final key = '$itemId:${widget.mediaSourceId ?? ''}:${track.index}';
    return _externalSubtitleContent.putIfAbsent(
      key,
      () => api.subtitleContent(
        itemId,
        track.index,
        mediaSourceId: widget.mediaSourceId,
      ),
    );
  }

  Future<void> _loadExternalSubtitles() async {
    final itemId = widget.itemId;
    final mediaSourceId = widget.mediaSourceId;
    final api = widget.apiClient;
    _subtitleSelectionVersion++;
    _externalSubtitleById.clear();
    _externalSubtitleContent.clear();
    _loadedExternalSubtitleTrackIds.clear();
    if (mounted) {
      setState(() {
        _externalSubtitles = const [];
        _subtitleCues = const [];
        if (_selectedSubtitle?.startsWith('jellyfin-external:') ?? false) {
          _selectedSubtitle = null;
        }
      });
    }
    if (itemId == null || api == null) {
      return;
    }
    try {
      final info = await api.playbackInfo(itemId, mediaSourceId: mediaSourceId);
      if (!mounted ||
          widget.itemId != itemId ||
          widget.mediaSourceId != mediaSourceId ||
          widget.apiClient != api) {
        return;
      }
      final external = info.subtitleStreams.where((track) => track.isExternal);
      _playbackInfo = widget.partyPlayback ?? info;
      _externalSubtitleById.clear();
      for (final track in external) {
        _externalSubtitleById[_externalSubtitleId(track.index)] = track;
        unawaited(_contentForExternal(track).catchError((_) => ''));
      }
      setState(() {
        _externalSubtitles = [
          for (final track in external)
            PlayerTrack(
              id: _externalSubtitleId(track.index),
              type: 'subtitle',
              title: track.displayTitle ?? track.title,
              language: track.language,
              codec: track.codec,
              isDefault: track.isDefault,
              jellyfinIndex: track.index,
            ),
        ];
      });
      if (_selectedSubtitle == null) {
        final preferred =
            widget.partyPlayback?.selectedSubtitleIndex ??
            widget.preferredSubtitleStreamIndex;
        PlaybackTrack? requested;
        if (preferred != null) {
          for (final track in external) {
            if (track.index == preferred) {
              requested = track;
              break;
            }
          }
        }
        final defaults = external.where((track) => track.isDefault);
        final initial = requested ?? (defaults.isEmpty ? null : defaults.first);
        if (initial != null) {
          await _setSubtitle(_externalSubtitleId(initial.index));
        }
      }
      await _applyCanonicalTracks();
    } catch (e) {
      if (mounted && widget.itemId == itemId) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleIdle() {
    // Parent-owned visibility (party path): the single unified timer lives in
    // the party screen, so don't run a second one here.
    if (widget.visible != null) return;
    _idleTimer?.cancel();
    if (!_playing) {
      // Stay visible while paused/buffering — nothing to hide from.
      setState(() => _visible = true);
      return;
    }
    _idleTimer = Timer(widget.idleTimeout, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _wake() {
    // Parent-owned visibility: forward the activity so the single timer re-arms.
    if (widget.visible != null) {
      widget.onWake?.call();
      return;
    }
    setState(() => _visible = true);
    _scheduleIdle();
  }

  Future<void> _togglePlay() async {
    if (!widget.canControl) return;
    if (_playing) {
      await widget.controller.pause();
    } else {
      await widget.controller.play();
    }
    _wake();
  }

  Future<void> _seekBy(Duration delta) async {
    if (!widget.canControl) return;
    final target = _position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration
              ? _duration
              : target);
    await widget.controller.seek(clamped);
    widget.onSeek?.call(clamped);
    _wake();
  }

  Future<void> _seekTo(Duration position) async {
    if (!widget.canControl) return;
    await widget.controller.seek(position);
    widget.onSeek?.call(position);
    _wake();
  }

  Future<void> _setVolume(double v) async {
    setState(() {
      _volume = v;
      // Remember the last audible level so a later mute can restore it.
      if (v > 0) _preMuteVolume = v;
    });
    await widget.controller.setVolume(v);
    _wake();
  }

  /// Toggle mute, restoring the pre-mute level on unmute (not a hard jump to
  /// 100). Volume is a personal, per-viewer setting, so it stays available even
  /// when [PlayerChrome.canControl] is false.
  Future<void> _toggleMute() async {
    if (_volume > 0) {
      _preMuteVolume = _volume;
      await _setVolume(0);
    } else {
      await _setVolume(_preMuteVolume > 0 ? _preMuteVolume : 100);
    }
  }

  Future<void> _setHardwareDecoding(bool enabled) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _hwDecoding = enabled);
    await c.setHardwareDecoding(enabled);
    _wake();
  }

  Future<void> _setSubtitleScale(double v) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subScale = v);
    await c.setSubtitleScale(v);
    _emitSubtitlePreferences(fontScalePercent: (v * 100).round());
    _wake();
  }

  Future<void> _setSubtitlePosition(int v) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subPos = v);
    await c.setSubtitlePosition(v);
    _emitSubtitlePreferences(
      verticalPosition: v <= 25 ? 'top' : (v <= 75 ? 'middle' : 'bottom'),
    );
    _wake();
  }

  Future<void> _setSubtitleDelay(double v) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subDelay = v);
    await c.setSubtitleDelay(v);
    _emitSubtitlePreferences(delayMs: (v * 1000).round());
    _wake();
  }

  Future<void> _setSubtitleFont(String font) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subFont = font);
    await c.setSubtitleFont(font);
    _emitSubtitlePreferences(
      fontFamily: font == 'monospace'
          ? 'mono'
          : (font == 'serif' ? 'serif' : 'sans'),
    );
    _wake();
  }

  Future<void> _setSubtitleColor(String color) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subColor = color.toUpperCase());
    await c.setSubtitleColor(_subColor);
    _emitSubtitlePreferences(textColor: _subColor);
  }

  Future<void> _setSubtitleBackgroundOpacity(int percent) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subBackgroundOpacity = percent);
    await c.setSubtitleBackgroundOpacity(percent);
    _emitSubtitlePreferences(backgroundOpacityPercent: percent);
  }

  void _emitSubtitlePreferences({
    int? delayMs,
    int? fontScalePercent,
    String? verticalPosition,
    String? fontFamily,
    String? textColor,
    int? backgroundOpacityPercent,
  }) {
    final callback = widget.onSetSubtitlePreferences;
    if (callback == null || !widget.canManagePartyMedia) return;
    final local = SubtitlePreferences(
      delayMs: (_subDelay * 1000).round(),
      fontScalePercent: (_subScale * 100).round(),
      verticalPosition: _subPos <= 25
          ? 'top'
          : (_subPos <= 75 ? 'middle' : 'bottom'),
      fontFamily: _subFont == 'monospace'
          ? 'mono'
          : (_subFont == 'serif' ? 'serif' : 'sans'),
      textColor: _subColor,
      backgroundOpacityPercent: _subBackgroundOpacity,
    );
    callback(
      local.copyWith(
        delayMs: delayMs,
        fontScalePercent: fontScalePercent,
        verticalPosition: verticalPosition,
        fontFamily: fontFamily,
        textColor: textColor,
        backgroundOpacityPercent: backgroundOpacityPercent,
      ),
    );
  }

  Future<void> _applyCanonicalSubtitlePreferences() async {
    final preferences = widget.subtitlePreferences;
    if (preferences == null) return;
    final position = switch (preferences.verticalPosition) {
      'top' => 10,
      'middle' => 50,
      _ => 100,
    };
    final font = switch (preferences.fontFamily) {
      'serif' => 'serif',
      'mono' => 'monospace',
      _ => 'sans-serif',
    };
    if (mounted) {
      setState(() {
        _subScale = preferences.fontScalePercent / 100;
        _subPos = position;
        _subDelay = preferences.delayMs / 1000;
        _subFont = font;
        _subColor = preferences.textColor;
        _subBackgroundOpacity = preferences.backgroundOpacityPercent;
      });
    }
    final c = widget.controller;
    if (c is MediaKitPlayerController) {
      await c.setSubtitleScale(_subScale);
      await c.setSubtitlePosition(_subPos);
      await c.setSubtitleDelay(_subDelay);
      await c.setSubtitleFont(_subFont);
      await c.setSubtitleColor(_subColor);
      await c.setSubtitleBackgroundOpacity(_subBackgroundOpacity);
    }
  }

  Future<void> _applyCanonicalTracks() async {
    final playback = widget.partyPlayback ?? _playbackInfo;
    if (playback == null) return;
    final audioId = playerTrackIdForJellyfinIndex(
      jellyfinIndex: playback.selectedAudioIndex,
      type: 'audio',
      playerTracks: _tracks.audio,
      playback: playback,
    );
    final subtitleId = playerTrackIdForJellyfinIndex(
      jellyfinIndex: playback.selectedSubtitleIndex,
      type: 'subtitle',
      playerTracks: _visibleSubtitleTracks,
      playback: playback,
    );
    if (playback.selectedAudioIndex != null && audioId != null) {
      await _setAudio(audioId, authored: false);
    }
    if (playback.selectedSubtitleIndex != null) {
      await _setSubtitle(subtitleId, authored: false);
    }
  }

  /// Opens a compact panel with sliders for subtitle size, vertical position,
  /// and timing offset. Only wired when the live MediaKitPlayerController is in
  /// use. Kept in a Material dialog (the chrome lives under a Scaffold), so the
  /// sliders are ordinary Material [Slider]s.
  Future<void> _openSubtitleSettings() async {
    if (widget.controller is! MediaKitPlayerController) return;
    _idleTimer?.cancel(); // keep the chrome awake while the dialog is open
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _SubtitleSettingsDialog(
        scale: _subScale,
        position: _subPos,
        delay: _subDelay,
        font: _subFont,
        color: _subColor,
        backgroundOpacity: _subBackgroundOpacity,
        enabled: widget.canManagePartyMedia,
        onScale: _setSubtitleScale,
        onPosition: _setSubtitlePosition,
        onDelay: _setSubtitleDelay,
        onFont: _setSubtitleFont,
        onColor: _setSubtitleColor,
        onBackgroundOpacity: _setSubtitleBackgroundOpacity,
      ),
    );
    _wake();
  }

  Future<void> _setAudio(String? id, {bool authored = true}) async {
    setState(() => _selectedAudio = id);
    await widget.controller.setAudioTrack(id);
    if (authored && widget.onSetPlaybackTracks != null) {
      final playback = widget.partyPlayback ?? _playbackInfo;
      if (playback != null) {
        widget.onSetPlaybackTracks!(
          jellyfinIndexForPlayerTrack(
            playerTrackId: id,
            type: 'audio',
            playerTracks: _tracks.audio,
            playback: playback,
          ),
          playback.selectedSubtitleIndex ?? -1,
        );
      }
    }
    _wake();
  }

  Future<void> _setSubtitle(String? id, {bool authored = true}) async {
    final previous = _selectedSubtitle;
    final version = ++_subtitleSelectionVersion;
    final external = id == null ? null : _externalSubtitleById[id];
    final c = widget.controller;
    if (external != null) {
      final itemId = widget.itemId;
      final mediaSourceId = widget.mediaSourceId;
      final api = widget.apiClient;
      if (itemId == null || api == null) return;
      if (mounted) setState(() => _selectedSubtitle = id);
      try {
        final content = await _contentForExternal(external);
        if (!mounted ||
            version != _subtitleSelectionVersion ||
            widget.itemId != itemId ||
            widget.mediaSourceId != mediaSourceId ||
            widget.apiClient != api ||
            widget.controller != c) {
          return;
        }
        final cues = parseSubtitleCues(content);
        if (cues.isEmpty) throw const FormatException('No valid subtitle cues');
        setState(() {
          _subtitleCues = cues;
          _selectedSubtitle = id;
        });
        if (c is MediaKitPlayerController) {
          try {
            final loadedTrackId = _loadedExternalSubtitleTrackIds[id];
            if (loadedTrackId != null) {
              await c.setSubtitle(loadedTrackId);
            } else {
              await c.addExternalSubtitle(
                content,
                title: external.displayTitle ?? external.title,
                language: external.language,
              );
              final nativeId = c.currentSubtitleTrackId;
              if (nativeId != null) {
                _loadedExternalSubtitleTrackIds[id!] = nativeId;
              }
            }
          } catch (_) {
            // The Flutter overlay remains the rendering fallback.
          }
        }
      } catch (e) {
        if (mounted && version == _subtitleSelectionVersion) {
          setState(() {
            _selectedSubtitle = previous;
            _subtitleCues = const [];
            _error = '$e';
          });
        }
        return;
      }
    } else {
      if (mounted) setState(() => _subtitleCues = const []);
      await widget.controller.setSubtitle(id);
    }
    if (mounted && version == _subtitleSelectionVersion) {
      setState(() => _selectedSubtitle = id);
    }
    if (authored && widget.onSetPlaybackTracks != null) {
      final playback = widget.partyPlayback ?? _playbackInfo;
      if (playback != null) {
        widget.onSetPlaybackTracks!(
          playback.selectedAudioIndex,
          jellyfinIndexForPlayerTrack(
                playerTrackId: id,
                type: 'subtitle',
                playerTracks: _visibleSubtitleTracks,
                playback: playback,
              ) ??
              -1,
        );
      }
    }
    _wake();
  }

  /// Pick a local subtitle file and side-load it into the player. The video is
  /// direct-played untouched (no transcode); libmpv renders the subtitle and
  /// times it to playback by its own timestamps, so it follows the video. The
  /// added track surfaces on the next [PlayerTracks] emission, which updates
  /// the subtitle menu. Only meaningful for the concrete MediaKit controller.
  Future<void> _addSubtitleFile() async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null) return;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      await c.addExternalSubtitle(_subtitleToUtf8(bytes), title: file.name);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load subtitle: $e');
      return;
    }
    _wake();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Push-to-talk releases on key up — independent of playback-control rights.
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyT &&
          widget.onPushToTalkStop != null) {
        widget.onPushToTalkStop!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _wake();
    // Chat + push-to-talk are A/V-layer bindings available to guests too, so
    // they run before the canControl transport gate. Key-repeat arrives as a
    // KeyRepeatEvent (not KeyDownEvent), so hold-T fires start exactly once.
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        widget.onToggleChat != null) {
      widget.onToggleChat!();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyT &&
        widget.onPushToTalkStart != null) {
      widget.onPushToTalkStart!();
      return KeyEventResult.handled;
    }
    if (!widget.canControl) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        _togglePlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _seekBy(const Duration(seconds: 5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _seekBy(const Duration(seconds: -5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        _seekBy(const Duration(seconds: 10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyJ:
        _seekBy(const Duration(seconds: -10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _setVolume(math.min(100, _volume + 10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _setVolume(math.max(0, _volume - 10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        widget.onToggleFullscreen?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        _toggleMute();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final activeCues = activeSubtitleCues(
      _subtitleCues,
      _position,
      delay: Duration(milliseconds: (_subDelay * 1000).round()),
    );
    // Parent-owned visibility (party) wins; otherwise the internal idle state.
    final visible = widget.visible ?? _visible;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: visible ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) => _wake(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _wake,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Center buffering spinner / error state (E4.3).
              if (_error != null)
                _ErrorOverlay(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                )
              else if (_buffering && !_completed)
                const _BufferingSpinner(),

              if (_completed && !_buffering) const SizedBox.shrink(),

              // Top bar: back + title.
              _AnimatedEdge(
                visible: visible,
                alignment: Alignment.topCenter,
                child: _TopBar(title: widget.title, onBack: widget.onBack),
              ),

              // Bottom transport bar.
              _AnimatedEdge(
                visible: visible,
                alignment: Alignment.bottomCenter,
                child: _TransportBar(
                  canControl: widget.canControl,
                  canManageTracks: widget.canManagePartyMedia,
                  playing: _playing,
                  position: _dragPosition ?? _position,
                  duration: _duration,
                  volume: _volume,
                  tracks: PlayerTracks(
                    video: _tracks.video,
                    audio: _tracks.audio,
                    subtitle: _visibleSubtitleTracks,
                  ),
                  selectedAudio: _selectedAudio,
                  selectedSubtitle: _selectedSubtitle,
                  isFullscreen: widget.isFullscreen,
                  // Decode + subtitle-settings are additive libmpv features:
                  // only surface them when the live MediaKitPlayerController is
                  // in use (mock/spy controllers get the base bar).
                  hardwareDecoding: _hwDecoding,
                  onDecode: widget.controller is MediaKitPlayerController
                      ? _setHardwareDecoding
                      : null,
                  onSubtitleSettings:
                      widget.controller is MediaKitPlayerController
                      ? _openSubtitleSettings
                      : null,
                  onAddSubtitle: widget.controller is MediaKitPlayerController
                      ? _addSubtitleFile
                      : null,
                  onTogglePlay: _togglePlay,
                  onSeekPreview: (p) => setState(() => _dragPosition = p),
                  onSeekCommit: (p) {
                    setState(() => _dragPosition = null);
                    _seekTo(p);
                  },
                  onVolume: _setVolume,
                  onToggleMute: _toggleMute,
                  onAudio: _setAudio,
                  onSubtitle: _setSubtitle,
                  onToggleFullscreen: widget.onToggleFullscreen,
                  trickplay: _trickplay,
                  apiClient: widget.apiClient,
                  cachedSpans: widget.cachedSpans,
                  previewPosition: _previewPosition,
                  previewFraction: _previewFraction,
                  onHoverPreview: (position, fraction) => setState(() {
                    _previewPosition = position;
                    _previewFraction = fraction;
                  }),
                  onHoverEnd: () => setState(() => _previewPosition = null),
                ),
              ),

              if (activeCues.isNotEmpty)
                _SubtitleOverlay(
                  text: activeCues.map((cue) => cue.text).join('\n'),
                  scale: _subScale,
                  position: _subPos,
                  font: _subFont,
                  color: _subColor,
                  backgroundOpacity: _subBackgroundOpacity,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleOverlay extends StatelessWidget {
  const _SubtitleOverlay({
    required this.text,
    required this.scale,
    required this.position,
    required this.font,
    required this.color,
    required this.backgroundOpacity,
  });

  final String text;
  final double scale;
  final int position;
  final String font;
  final String color;
  final int backgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final (family, fallbacks) = switch (font) {
      'serif' => ('Times New Roman', const ['DejaVu Serif', 'serif']),
      'monospace' => ('Courier New', const ['DejaVu Sans Mono', 'monospace']),
      _ => (AppFonts.sans, const ['Arial', 'DejaVu Sans', 'sans-serif']),
    };
    return IgnorePointer(
      child: Align(
        alignment: Alignment(0, (position.clamp(0, 100) / 50) - 1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Text(
            text,
            key: const Key('externalSubtitleOverlay'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(
                int.parse(color.substring(1), radix: 16) | 0xFF000000,
              ),
              backgroundColor: Color.fromRGBO(
                0,
                0,
                0,
                backgroundOpacity.clamp(0, 100) / 100,
              ),
              fontSize: 22 * scale,
              fontFamily: family,
              fontFamilyFallback: fallbacks,
              height: 1.25,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 4),
                Shadow(color: Colors.black, offset: Offset(1, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedEdge extends StatelessWidget {
  const _AnimatedEdge({
    required this.visible,
    required this.alignment,
    required this.child,
  });
  final bool visible;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.title, this.onBack});
  final String? title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (onBack == null && title == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      // Flat near-black translucent bar — no gradients per the design system.
      decoration: const BoxDecoration(color: _kChromeScrim),
      child: Row(
        children: [
          if (onBack != null)
            _ChromeIconButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onPressed: onBack,
            ),
          if (title != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.titleMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.canControl,
    required this.canManageTracks,
    required this.playing,
    required this.position,
    required this.duration,
    required this.volume,
    required this.tracks,
    required this.selectedAudio,
    required this.selectedSubtitle,
    required this.isFullscreen,
    required this.hardwareDecoding,
    required this.onDecode,
    required this.onSubtitleSettings,
    required this.onAddSubtitle,
    required this.onTogglePlay,
    required this.onSeekPreview,
    required this.onSeekCommit,
    required this.onVolume,
    required this.onToggleMute,
    required this.onAudio,
    required this.onSubtitle,
    required this.onToggleFullscreen,
    required this.trickplay,
    required this.apiClient,
    this.cachedSpans,
    required this.previewPosition,
    required this.previewFraction,
    required this.onHoverPreview,
    required this.onHoverEnd,
  });

  final bool canControl;
  final bool canManageTracks;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final PlayerTracks tracks;
  final String? selectedAudio;
  final String? selectedSubtitle;
  final bool isFullscreen;

  /// Whether hardware decode is active. Only rendered when [onDecode] != null.
  final bool hardwareDecoding;

  /// Toggle hardware/software decode. Null hides the decode menu (non-media_kit
  /// controller).
  final ValueChanged<bool>? onDecode;

  /// Opens the subtitle appearance panel. Null hides the gear (non-media_kit).
  final VoidCallback? onSubtitleSettings;

  /// Picks a local subtitle file to side-load. Null on non-media_kit
  /// controllers; when non-null the subtitle menu is always shown (so the user
  /// can load a file even when the media carries no subtitle tracks).
  final VoidCallback? onAddSubtitle;

  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeekCommit;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;
  final ValueChanged<String?> onAudio;
  final ValueChanged<String?> onSubtitle;
  final VoidCallback? onToggleFullscreen;
  final TrickplayManifest? trickplay;
  final ApiClient? apiClient;
  final ValueListenable<List<CachedSpan>>? cachedSpans;
  final Duration? previewPosition;
  final double previewFraction;
  final void Function(Duration position, double fraction) onHoverPreview;
  final VoidCallback onHoverEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxl,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      // The one allowed legibility exception: a bottom-up black-alpha scrim
      // behind the transport row (mirrors the redesigned web control bar's
      // `linear-gradient(0deg, rgba(0,0,0,.8), transparent)`).
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              children: [
                _Scrubber(
                  key: const Key('playbackScrubber'),
                  position: position,
                  duration: duration,
                  enabled: canControl,
                  onPreview: onSeekPreview,
                  onCommit: onSeekCommit,
                  onHoverPreview: onHoverPreview,
                  onHoverEnd: onHoverEnd,
                  cachedSpans: cachedSpans,
                ),
                if (previewPosition != null &&
                    trickplay != null &&
                    apiClient != null)
                  Positioned(
                    bottom: 28,
                    left: (previewFraction * constraints.maxWidth - 90).clamp(
                      0.0,
                      math.max(0.0, constraints.maxWidth - 180),
                    ),
                    child: IgnorePointer(
                      child: TrickplayPreview(
                        manifest: trickplay!,
                        frame: trickplay!.frameAt(previewPosition!),
                        apiClient: apiClient!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              _ChromeIconButton(
                icon: playing ? Icons.pause : Icons.play_arrow,
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: canControl ? onTogglePlay : null,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${_fmt(position)} / ${_fmt(duration)}',
                style: AppTheme.mono.copyWith(
                  color: AppColors.dim,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              _VolumeControl(
                volume: volume,
                onChanged: onVolume,
                onToggleMute: onToggleMute,
              ),
              if (onDecode != null)
                _DecodeMenu(
                  hardware: hardwareDecoding,
                  enabled: canControl,
                  onChanged: onDecode!,
                ),
              if (tracks.audio.isNotEmpty)
                _TrackMenu(
                  icon: Icons.audiotrack,
                  tooltip: 'Audio track',
                  tracks: tracks.audio,
                  selected: selectedAudio,
                  enabled: canManageTracks,
                  allowNone: false,
                  onChanged: onAudio,
                ),
              if (onAddSubtitle != null || tracks.subtitle.isNotEmpty)
                _SubtitleControl(
                  tracks: tracks.subtitle,
                  selected: selectedSubtitle,
                  enabled: canManageTracks,
                  onChanged: onSubtitle,
                  onAddFile: onAddSubtitle,
                ),
              if (onSubtitleSettings != null)
                _ChromeIconButton(
                  icon: Icons.tune,
                  tooltip: 'Subtitle settings',
                  onPressed: onSubtitleSettings,
                ),
              if (onToggleFullscreen != null)
                _ChromeIconButton(
                  icon: isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  tooltip: isFullscreen ? 'Exit full screen' : 'Full screen',
                  onPressed: onToggleFullscreen,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    if (d.isNegative || d == Duration.zero) return '0:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onPreview,
    required this.onCommit,
    required this.onHoverPreview,
    required this.onHoverEnd,
    this.cachedSpans,
  });

  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onPreview;
  final ValueChanged<Duration> onCommit;
  final void Function(Duration position, double fraction) onHoverPreview;
  final VoidCallback onHoverEnd;

  /// Cached ("downloaded") spans to paint behind the play-progress track, as
  /// an indicator of what's already on disk. Null/empty renders nothing.
  final ValueListenable<List<CachedSpan>>? cachedSpans;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final value = totalMs > 0
        ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    return MouseRegion(
      onHover: (event) {
        if (totalMs <= 0) return;
        final box = context.findRenderObject()! as RenderBox;
        final fraction = (event.localPosition.dx / box.size.width).clamp(
          0.0,
          1.0,
        );
        onHoverPreview(
          Duration(milliseconds: (fraction * totalMs).round()),
          fraction,
        );
      },
      onExit: (_) => onHoverEnd(),
      child: SizedBox(
        height: 24,
        child: cachedSpans == null
            ? _buildSlider(value, totalMs, const [])
            : ValueListenableBuilder<List<CachedSpan>>(
                valueListenable: cachedSpans!,
                builder: (context, spans, _) =>
                    _buildSlider(value, totalMs, spans),
              ),
      ),
    );
  }

  Widget _buildSlider(double value, int totalMs, List<CachedSpan> spans) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.line2,
        thumbColor: AppColors.accent,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: enabled
            ? const RoundSliderThumbShape(enabledThumbRadius: 6)
            : const RoundSliderThumbShape(enabledThumbRadius: 0),
        // Paint the cached ("downloaded") spans inside the slider's own track
        // rect so the gray bar lines up exactly with the accent play-progress
        // and thumb — no inset guesswork / horizontal offset.
        trackShape: _CachedRangesTrackShape(spans),
      ),
      child: Slider(
        value: value,
        onChanged: (!enabled || totalMs <= 0)
            ? null
            : (v) => onPreview(Duration(milliseconds: (v * totalMs).round())),
        onChangeEnd: (!enabled || totalMs <= 0)
            ? null
            : (v) => onCommit(Duration(milliseconds: (v * totalMs).round())),
      ),
    );
  }
}

/// A slider track that also paints [CachedSpan]s (downloaded byte ranges) in
/// the SAME track rect the active track + thumb use, so the "downloaded"
/// overlay lines up exactly with the play-progress highlight. Draw order:
/// inactive base -> cached spans -> active (played) portion.
class _CachedRangesTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const _CachedRangesTrackShape(this.cachedSpans);

  final List<CachedSpan> cachedSpans;

  static const Color _cachedColor = Colors.white54;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    final canvas = context.canvas;
    final radius = Radius.circular(rect.height / 2);

    // Inactive base (whole track).
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = sliderTheme.inactiveTrackColor ?? AppColors.line2,
    );

    // Cached ("downloaded") spans, in the same track coordinate space.
    final cachedPaint = Paint()..color = _cachedColor;
    for (final span in cachedSpans) {
      final s = span.start.clamp(0.0, 1.0);
      final e = span.end.clamp(0.0, 1.0);
      if (e <= s) continue;
      final l = rect.left + s * rect.width;
      final r = rect.left + e * rect.width;
      canvas.drawRect(Rect.fromLTRB(l, rect.top, r, rect.bottom), cachedPaint);
    }

    // Active (played) portion: left edge -> thumb center.
    if (thumbCenter.dx > rect.left) {
      final activeRect = Rect.fromLTRB(
        rect.left,
        rect.top,
        thumbCenter.dx.clamp(rect.left, rect.right),
        rect.bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()..color = sliderTheme.activeTrackColor ?? AppColors.accent,
      );
    }
  }
}

/// Inline mute-toggle icon + always-visible volume slider. Kept inline (rather
/// than in a popover behind a disabled button) so the control is obviously live
/// and directly wired to `setVolume`. Volume is a personal setting, so it stays
/// enabled regardless of `canControl`.
class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.volume,
    required this.onChanged,
    required this.onToggleMute,
  });

  final double volume;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final muted = volume <= 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChromeIconButton(
          icon: muted
              ? Icons.volume_off
              : (volume < 50 ? Icons.volume_down : Icons.volume_up),
          tooltip: muted ? 'Unmute' : 'Mute',
          onPressed: onToggleMute,
        ),
        SizedBox(
          width: 76,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.line2,
              thumbColor: AppColors.accent,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              key: const Key('volumeSlider'),
              value: volume.clamp(0, 100),
              min: 0,
              max: 100,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Hardware/software video-decode toggle using the same anchored panel as the
/// audio and subtitle selectors.
class _DecodeMenu extends StatelessWidget {
  const _DecodeMenu({
    required this.hardware,
    required this.enabled,
    required this.onChanged,
  });
  final bool hardware;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _AnchoredPlayerMenu(
      icon: Icons.memory,
      tooltip: 'Decode',
      enabled: enabled,
      menuBuilder: (close) => [
        const _PlayerMenuHeader('VIDEO DECODER'),
        _PlayerMenuItem(
          label: 'Hardware',
          detail: 'GPU accelerated',
          selected: hardware,
          onTap: () {
            close();
            onChanged(true);
          },
        ),
        _PlayerMenuItem(
          label: 'Software',
          detail: 'CPU fallback',
          selected: !hardware,
          onTap: () {
            close();
            onChanged(false);
          },
        ),
      ],
    );
  }
}

/// Compact subtitle-appearance panel: size, vertical position, and timing
/// offset sliders. Written as a Material dialog (the chrome lives under a
/// Scaffold), so plain Material [Slider]s are safe here.
class _SubtitleSettingsDialog extends StatefulWidget {
  const _SubtitleSettingsDialog({
    required this.scale,
    required this.position,
    required this.delay,
    required this.font,
    required this.color,
    required this.backgroundOpacity,
    required this.enabled,
    required this.onScale,
    required this.onPosition,
    required this.onDelay,
    required this.onFont,
    required this.onColor,
    required this.onBackgroundOpacity,
  });

  final double scale;
  final int position;
  final double delay;
  final String font;
  final String color;
  final int backgroundOpacity;
  final bool enabled;
  final ValueChanged<double> onScale;
  final ValueChanged<int> onPosition;
  final ValueChanged<double> onDelay;
  final ValueChanged<String> onFont;
  final ValueChanged<String> onColor;
  final ValueChanged<int> onBackgroundOpacity;

  @override
  State<_SubtitleSettingsDialog> createState() =>
      _SubtitleSettingsDialogState();
}

class _SubtitleSettingsDialogState extends State<_SubtitleSettingsDialog> {
  late double _scale = widget.scale;
  late int _position = widget.position;
  late double _delay = widget.delay;
  late String _font = widget.font;
  late String _color = widget.color;
  late int _backgroundOpacity = widget.backgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final titleStyle = TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: wp.text,
    );
    final bodyStyle = TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: 13,
      color: wp.text,
    );
    final dimStyle = bodyStyle.copyWith(color: wp.dim);
    return Dialog(
      backgroundColor: wp.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: BorderSide(color: wp.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Subtitle settings', style: titleStyle),
              const SizedBox(height: AppSpacing.md),
              Text('Font', style: dimStyle),
              DropdownButton<String>(
                key: const Key('subtitleFont'),
                value: _font,
                isExpanded: true,
                dropdownColor: wp.surface,
                style: bodyStyle,
                items: const [
                  DropdownMenuItem(
                    value: 'sans-serif',
                    child: Text('Sans serif'),
                  ),
                  DropdownMenuItem(value: 'serif', child: Text('Serif')),
                  DropdownMenuItem(
                    value: 'monospace',
                    child: Text('Monospace'),
                  ),
                ],
                onChanged: !widget.enabled
                    ? null
                    : (font) {
                        if (font == null) return;
                        setState(() => _font = font);
                        widget.onFont(font);
                      },
              ),
              Text('Text color', style: dimStyle),
              TextFormField(
                key: const Key('subtitleTextColor'),
                initialValue: _color,
                enabled: widget.enabled,
                decoration: const InputDecoration(hintText: '#RRGGBB'),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#0-9A-Fa-f]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                onChanged: (color) {
                  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) return;
                  setState(() => _color = color.toUpperCase());
                  widget.onColor(_color);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _slider(
                palette: wp,
                label: 'Size',
                value: _scale,
                min: 0.6,
                max: 2.0,
                divisions: 14,
                display: '${(_scale * 100).round()}%',
                onChanged: !widget.enabled
                    ? null
                    : (v) {
                        setState(() => _scale = v);
                        widget.onScale(v);
                      },
              ),
              _slider(
                palette: wp,
                label: 'Position',
                value: _position.toDouble(),
                min: 10,
                max: 100,
                divisions: 2,
                display: _position <= 25
                    ? 'Top'
                    : (_position <= 75 ? 'Middle' : 'Bottom'),
                onChanged: !widget.enabled
                    ? null
                    : (v) {
                        final position = v < 33 ? 10 : (v < 78 ? 50 : 100);
                        setState(() => _position = position);
                        widget.onPosition(_position);
                      },
              ),
              _slider(
                palette: wp,
                label: 'Delay',
                value: _delay,
                min: -10.0,
                max: 10.0,
                divisions: 80,
                display:
                    '${_delay >= 0 ? '+' : ''}${_delay.toStringAsFixed(1)}s',
                onChanged: !widget.enabled
                    ? null
                    : (v) {
                        setState(
                          () => _delay = double.parse(v.toStringAsFixed(2)),
                        );
                        widget.onDelay(_delay);
                      },
              ),
              _slider(
                palette: wp,
                label: 'Background',
                value: _backgroundOpacity.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: '$_backgroundOpacity%',
                onChanged: !widget.enabled
                    ? null
                    : (v) {
                        setState(() => _backgroundOpacity = v.round());
                        widget.onBackgroundOpacity(_backgroundOpacity);
                      },
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: !widget.enabled
                        ? null
                        : () {
                            setState(() {
                              _font = 'sans-serif';
                              _scale = 1;
                              _position = 100;
                              _delay = 0;
                              _color = '#FFFFFF';
                              _backgroundOpacity = 65;
                            });
                            widget.onFont(_font);
                            widget.onScale(_scale);
                            widget.onPosition(_position);
                            widget.onDelay(_delay);
                            widget.onColor(_color);
                            widget.onBackgroundOpacity(_backgroundOpacity);
                          },
                    child: Text('Reset', style: bodyStyle),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Done', style: bodyStyle),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider({
    required WpPalette palette,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 13,
                color: palette.dim,
              ),
            ),
            Text(
              display,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: palette.dim,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: palette.text,
            inactiveTrackColor: palette.line2,
            thumbColor: palette.text,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _TrackMenu extends StatelessWidget {
  const _TrackMenu({
    required this.icon,
    required this.tooltip,
    required this.tracks,
    required this.selected,
    required this.enabled,
    required this.allowNone,
    required this.onChanged,
  });

  final IconData icon;
  final String tooltip;
  final List<PlayerTrack> tracks;
  final String? selected;
  final bool enabled;
  final bool allowNone;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _AnchoredPlayerMenu(
      icon: icon,
      tooltip: tooltip,
      enabled: enabled,
      menuBuilder: (close) => [
        _PlayerMenuHeader(tooltip.toUpperCase()),
        if (allowNone)
          _PlayerMenuItem(
            label: 'Off',
            selected: selected == null,
            onTap: () {
              close();
              onChanged(null);
            },
          ),
        for (final t in tracks)
          _PlayerMenuItem(
            label: _trackName(t),
            detail: _trackDetail(t),
            selected: t.id == selected,
            onTap: () {
              close();
              onChanged(t.id);
            },
          ),
      ],
    );
  }
}

/// Subtitle control for the transport bar. Unlike the generic [_TrackMenu] it
/// is shown even when the media carries no subtitle tracks — so the user can
/// side-load a local file — and its popup offers a "Load subtitle file…"
/// action above the Off + track list.
class _SubtitleControl extends StatelessWidget {
  const _SubtitleControl({
    required this.tracks,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.onAddFile,
  });

  final List<PlayerTrack> tracks;
  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  /// Picks a local subtitle file to side-load, or null if unsupported.
  final VoidCallback? onAddFile;

  @override
  Widget build(BuildContext context) {
    return _AnchoredPlayerMenu(
      icon: Icons.subtitles,
      tooltip: 'Subtitles',
      enabled: enabled,
      menuBuilder: (close) => [
        const _PlayerMenuHeader('SUBTITLES'),
        if (onAddFile != null)
          _PlayerMenuItem(
            icon: Icons.upload_file_outlined,
            label: 'Load subtitle file',
            detail: 'SRT, VTT, ASS or SSA',
            onTap: () {
              close();
              onAddFile?.call();
            },
          ),
        if (onAddFile != null) const _PlayerMenuDivider(),
        _PlayerMenuItem(
          label: 'Off',
          selected: selected == null,
          onTap: () {
            close();
            onChanged(null);
          },
        ),
        for (final t in tracks)
          _PlayerMenuItem(
            label: _trackName(t),
            detail: _trackDetail(t),
            selected: t.id == selected,
            onTap: () {
              close();
              onChanged(t.id);
            },
          ),
      ],
    );
  }
}

String _trackName(PlayerTrack track) {
  final title = track.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final language = track.language?.trim().toLowerCase();
  return const {
        'eng': 'English',
        'spa': 'Spanish',
        'fra': 'French',
        'fre': 'French',
        'deu': 'German',
        'ger': 'German',
        'ita': 'Italian',
        'por': 'Portuguese',
        'jpn': 'Japanese',
        'kor': 'Korean',
        'zho': 'Chinese',
        'chi': 'Chinese',
        'tha': 'Thai',
      }[language] ??
      track.language ??
      track.id;
}

String? _trackDetail(PlayerTrack track) {
  final details = <String>[
    if (track.title != null &&
        track.language != null &&
        !track.title!.toLowerCase().contains(track.language!.toLowerCase()))
      track.language!.toUpperCase(),
    if (track.codec?.trim().isNotEmpty ?? false) track.codec!.toUpperCase(),
    if (track.isDefault) 'DEFAULT',
  ];
  return details.isEmpty ? null : details.join(' · ');
}

/// Places a compact player menu above its transport button. Using an overlay
/// follower avoids Flutter's default popup behavior, which centers the selected
/// row over the button and obscures neighboring controls.
class _AnchoredPlayerMenu extends StatefulWidget {
  const _AnchoredPlayerMenu({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.menuBuilder,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final List<Widget> Function(VoidCallback close) menuBuilder;

  @override
  State<_AnchoredPlayerMenu> createState() => _AnchoredPlayerMenuState();
}

class _AnchoredPlayerMenuState extends State<_AnchoredPlayerMenu> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (_entry != null) {
      _close();
      return;
    }
    final availableHeight = math.max(
      160.0,
      MediaQuery.sizeOf(context).height - 150,
    );
    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -10),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 310,
                constraints: BoxConstraints(
                  maxHeight: math.min(420, availableHeight),
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFA151619),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x7A000000),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.menuBuilder(_close),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    setState(() {});
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: _ChromeIconButton(
        icon: widget.icon,
        tooltip: widget.tooltip,
        onPressed: widget.enabled ? _toggle : null,
        forceEnabled: widget.enabled,
      ),
    );
  }
}

class _PlayerMenuHeader extends StatelessWidget {
  const _PlayerMenuHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 7),
      child: Text(
        label,
        style: AppTheme.mono.copyWith(
          color: AppColors.faint,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _PlayerMenuDivider extends StatelessWidget {
  const _PlayerMenuDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 6),
    child: Divider(height: 1, color: AppColors.line),
  );
}

class _PlayerMenuItem extends StatelessWidget {
  const _PlayerMenuItem({
    required this.label,
    required this.onTap,
    this.detail,
    this.icon,
    this.selected = false,
  });

  final String label;
  final String? detail;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      child: Material(
        color: selected ? const Color(0x14FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          hoverColor: const Color(0x12FFFFFF),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Icon(
                    selected ? Icons.check : icon,
                    size: 16,
                    color: selected ? AppColors.accent : AppColors.dim,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.mono.copyWith(
                            color: AppColors.faint,
                            fontSize: 9.5,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Normalise picked subtitle bytes to UTF-8 text for side-loading (mirrors the
/// upload path in subtitle_manager_dialog): pass valid UTF-8 through, otherwise
/// re-decode as Latin-1, and strip any stray U+FFFD so one bad glyph doesn't
/// corrupt rendering.
String _subtitleToUtf8(List<int> raw) {
  String text;
  try {
    text = utf8.decode(raw);
  } on FormatException {
    text = latin1.decode(raw, allowInvalid: true);
  }
  return text.replaceAll('\u{FFFD}', '');
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.forceEnabled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool forceEnabled;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null || forceEnabled;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: enabled ? AppColors.dim : AppColors.faint,
        splashRadius: 20,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
    );
  }
}

class _BufferingSpinner extends StatelessWidget {
  const _BufferingSpinner();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBufferingScrim,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.text,
              ),
            ),
            SizedBox(height: AppSpacing.md),
            Text('Buffering…', style: AppTheme.dim),
          ],
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: ErrorState(
        title: 'Playback error',
        message: message,
        onRetry: onDismiss,
        retryLabel: 'Dismiss',
      ),
    );
  }
}
