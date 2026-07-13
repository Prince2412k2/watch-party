import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api_client.dart';
import '../models/trickplay_manifest.dart';
import '../ui/ui.dart';
import 'media_kit_player_controller.dart';
import 'player_controller.dart';
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
const Color _kChromeBar = Color(0xD90A0A0B); // transport bar (~85%)
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
  });

  final PlayerController controller;
  final bool canControl;
  final String? title;
  final VoidCallback? onBack;

  /// Fired (in addition to the local seek) whenever the user scrubs or uses a
  /// keyboard seek. In a watch party this is wired to the sync engine's
  /// `requestSeek` so the host's seek is authored to the server and mirrored to
  /// every other client (web + Flutter). Null for solo playback (local only).
  final ValueChanged<Duration>? onSeek;
  final String? itemId;
  final String? mediaSourceId;
  final ApiClient? apiClient;

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
      _volume = c.volumeNow;
      _preMuteVolume = _volume > 0 ? _volume : 100;
      _selectedAudio = c.currentAudioTrackId;
      _selectedSubtitle = c.currentSubtitleTrackId;
      _hwDecoding = c.hardwareDecodingEnabled;
      _subScale = c.subtitleScale;
      _subPos = c.subtitlePosition;
      _subDelay = c.subtitleDelay;
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
            _selectedSubtitle = c.currentSubtitleTrackId;
          }
        });
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
  }

  @override
  void didUpdateWidget(PlayerChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.mediaSourceId != widget.mediaSourceId ||
        oldWidget.apiClient != widget.apiClient) {
      _loadTrickplay();
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
    _wake();
  }

  Future<void> _setSubtitlePosition(int v) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subPos = v);
    await c.setSubtitlePosition(v);
    _wake();
  }

  Future<void> _setSubtitleDelay(double v) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subDelay = v);
    await c.setSubtitleDelay(v);
    _wake();
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
        onScale: _setSubtitleScale,
        onPosition: _setSubtitlePosition,
        onDelay: _setSubtitleDelay,
      ),
    );
    _wake();
  }

  Future<void> _setAudio(String? id) async {
    if (!widget.canControl) return;
    setState(() => _selectedAudio = id);
    await widget.controller.setAudioTrack(id);
    _wake();
  }

  Future<void> _setSubtitle(String? id) async {
    if (!widget.canControl) return;
    setState(() => _selectedSubtitle = id);
    await widget.controller.setSubtitle(id);
    _wake();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _wake();
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
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
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
                visible: _visible,
                alignment: Alignment.topCenter,
                child: _TopBar(title: widget.title, onBack: widget.onBack),
              ),

              // Bottom transport bar.
              _AnimatedEdge(
                visible: _visible,
                alignment: Alignment.bottomCenter,
                child: _TransportBar(
                  canControl: widget.canControl,
                  playing: _playing,
                  position: _dragPosition ?? _position,
                  duration: _duration,
                  volume: _volume,
                  tracks: _tracks,
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
                  previewPosition: _previewPosition,
                  previewFraction: _previewFraction,
                  onHoverPreview: (position, fraction) => setState(() {
                    _previewPosition = position;
                    _previewFraction = fraction;
                  }),
                  onHoverEnd: () => setState(() => _previewPosition = null),
                ),
              ),
            ],
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
    required this.previewPosition,
    required this.previewFraction,
    required this.onHoverPreview,
    required this.onHoverEnd,
  });

  final bool canControl;
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
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      // Flat near-black translucent bar — no gradients per the design system.
      decoration: const BoxDecoration(color: _kChromeBar),
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
                  enabled: canControl,
                  allowNone: false,
                  onChanged: onAudio,
                ),
              if (tracks.subtitle.isNotEmpty)
                _TrackMenu(
                  icon: Icons.subtitles,
                  tooltip: 'Subtitles',
                  tracks: tracks.subtitle,
                  selected: selectedSubtitle,
                  enabled: canControl,
                  allowNone: true,
                  onChanged: onSubtitle,
                ),
              if (onSubtitleSettings != null)
                _ChromeIconButton(
                  icon: Icons.tune,
                  tooltip: 'Subtitle settings',
                  onPressed: canControl ? onSubtitleSettings : null,
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
  });

  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onPreview;
  final ValueChanged<Duration> onCommit;
  final void Function(Duration position, double fraction) onHoverPreview;
  final VoidCallback onHoverEnd;

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
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.line2,
            thumbColor: AppColors.accent,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: enabled
                ? const RoundSliderThumbShape(enabledThumbRadius: 6)
                : const RoundSliderThumbShape(enabledThumbRadius: 0),
          ),
          child: Slider(
            value: value,
            onChanged: (!enabled || totalMs <= 0)
                ? null
                : (v) =>
                      onPreview(Duration(milliseconds: (v * totalMs).round())),
            onChangeEnd: (!enabled || totalMs <= 0)
                ? null
                : (v) =>
                      onCommit(Duration(milliseconds: (v * totalMs).round())),
          ),
        ),
      ),
    );
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

/// Hardware/software video-decode toggle. Mirrors the audio/subtitle menu
/// idiom: a `PopupMenuButton` fronted by a `_ChromeIconButton`, with a
/// checkmark on the active choice.
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
    return PopupMenuButton<bool>(
      tooltip: 'Decode',
      enabled: enabled,
      initialValue: hardware,
      onSelected: onChanged,
      itemBuilder: (context) => [
        _item(true, 'Hardware'),
        _item(false, 'Software'),
      ],
      child: _ChromeIconButton(
        icon: Icons.memory,
        tooltip: 'Decode',
        onPressed: null,
        forceEnabled: enabled,
      ),
    );
  }

  PopupMenuItem<bool> _item(bool value, String label) => PopupMenuItem<bool>(
    value: value,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value == hardware)
          const Icon(Icons.check, size: 16, color: AppColors.accent),
        if (value == hardware) const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTheme.body),
      ],
    ),
  );
}

/// Compact subtitle-appearance panel: size, vertical position, and timing
/// offset sliders. Written as a Material dialog (the chrome lives under a
/// Scaffold), so plain Material [Slider]s are safe here.
class _SubtitleSettingsDialog extends StatefulWidget {
  const _SubtitleSettingsDialog({
    required this.scale,
    required this.position,
    required this.delay,
    required this.onScale,
    required this.onPosition,
    required this.onDelay,
  });

  final double scale;
  final int position;
  final double delay;
  final ValueChanged<double> onScale;
  final ValueChanged<int> onPosition;
  final ValueChanged<double> onDelay;

  @override
  State<_SubtitleSettingsDialog> createState() =>
      _SubtitleSettingsDialogState();
}

class _SubtitleSettingsDialogState extends State<_SubtitleSettingsDialog> {
  late double _scale = widget.scale;
  late int _position = widget.position;
  late double _delay = widget.delay;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Subtitle settings', style: AppTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              _slider(
                label: 'Size',
                value: _scale,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                display: '${(_scale * 100).round()}%',
                onChanged: (v) {
                  setState(() => _scale = v);
                  widget.onScale(v);
                },
              ),
              _slider(
                // sub-pos: 100 = bottom, lower = higher up. Show a "height"
                // reading so the slider reads left→low, right→high.
                label: 'Position',
                value: _position.toDouble(),
                min: 0,
                max: 150,
                divisions: 150,
                display: '${150 - _position}',
                onChanged: (v) {
                  setState(() => _position = v.round());
                  widget.onPosition(_position);
                },
              ),
              _slider(
                label: 'Delay',
                value: _delay,
                min: -10.0,
                max: 10.0,
                divisions: 200,
                display:
                    '${_delay >= 0 ? '+' : ''}${_delay.toStringAsFixed(1)}s',
                onChanged: (v) {
                  setState(() => _delay = double.parse(v.toStringAsFixed(1)));
                  widget.onDelay(_delay);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done', style: AppTheme.body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTheme.dim),
            Text(display, style: AppTheme.mono.copyWith(color: AppColors.dim)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.line2,
            thumbColor: AppColors.accent,
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

  /// Sentinel for the "Off"/auto entry. Real track ids are used verbatim;
  /// `PopupMenuButton` treats a `null` menu value as a *cancel* (it never fires
  /// `onSelected`), so the disable option cannot use `value: null` directly.
  static const _none = ' none';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      enabled: enabled,
      onSelected: (v) => onChanged(v == _none ? null : v),
      itemBuilder: (context) => [
        if (allowNone)
          PopupMenuItem<String>(
            value: _none,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected == null)
                  const Icon(Icons.check, size: 16, color: AppColors.accent),
                if (selected == null) const SizedBox(width: AppSpacing.xs),
                const Text('Off', style: AppTheme.body),
              ],
            ),
          ),
        for (final t in tracks)
          PopupMenuItem<String>(
            value: t.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.id == selected)
                  const Icon(Icons.check, size: 16, color: AppColors.accent),
                if (t.id == selected) const SizedBox(width: AppSpacing.xs),
                Text(t.title ?? t.language ?? t.id, style: AppTheme.body),
              ],
            ),
          ),
      ],
      child: _ChromeIconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: null,
        forceEnabled: enabled,
      ),
    );
  }
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
