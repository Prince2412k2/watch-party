import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/ui.dart';
import 'media_kit_player_controller.dart';
import 'player_controller.dart';

/// The minimal, monochrome transport bar for [PlayerController] (E4.2/E4.3).
/// Sits as an overlay on top of `VideoView` — play/pause, scrubber, time,
/// volume, playback rate, fullscreen, and audio/subtitle track menus. Reads
/// state off the controller's streams; writes back through its methods.
///
/// Auto-hides after a short idle period while playing (mouse movement / tap
/// wakes it), matches the web `DesktopControlBar`'s flat, single-row layout
/// and neutral buffering spinner (`app/client/src/components/Player.jsx`).
///
/// [canControl] gates interactivity: a `false` value (E5's no-control guest)
/// renders the same bar read-only — no thumb drag, no button taps — mirroring
/// `canControl` gating in the web player.
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
  });

  final PlayerController controller;
  final bool canControl;
  final String? title;
  final VoidCallback? onBack;

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
  double _rate = 1.0;
  String? _selectedAudio;
  String? _selectedSubtitle;

  Duration? _dragPosition;

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

    _subs.add(c.position.listen((p) => setState(() => _position = p)));
    _subs.add(c.duration.listen((d) => setState(() => _duration = d)));
    _subs.add(c.playing.listen((p) {
      setState(() => _playing = p);
      _scheduleIdle();
    }));
    _subs.add(c.buffering.listen((b) => setState(() => _buffering = b)));
    _subs.add(c.completed.listen((v) => setState(() => _completed = v)));
    _subs.add(c.tracks.listen((t) => setState(() => _tracks = t)));

    // media_kit surfaces decode/network errors on an additive `errors` stream
    // (not part of the frozen contract) — drive the E4.3 error overlay off it
    // when the concrete controller supports it.
    if (c is MediaKitPlayerController) {
      _subs.add(c.errors.listen((e) => setState(() => _error = e)));
    }

    _scheduleIdle();
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
        : (_duration > Duration.zero && target > _duration ? _duration : target);
    await widget.controller.seek(clamped);
    _wake();
  }

  Future<void> _seekTo(Duration position) async {
    if (!widget.canControl) return;
    await widget.controller.seek(position);
    _wake();
  }

  Future<void> _setVolume(double v) async {
    setState(() => _volume = v);
    await widget.controller.setVolume(v);
    _wake();
  }

  Future<void> _setRate(double r) async {
    if (!widget.canControl) return;
    setState(() => _rate = r);
    await widget.controller.setRate(r);
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
        _setVolume(_volume > 0 ? 0 : 100);
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
                _ErrorOverlay(message: _error!, onDismiss: () => setState(() => _error = null))
              else if (_buffering && !_completed)
                const _BufferingSpinner(),

              if (_completed && !_buffering)
                const SizedBox.shrink(),

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
                  rate: _rate,
                  tracks: _tracks,
                  selectedAudio: _selectedAudio,
                  selectedSubtitle: _selectedSubtitle,
                  isFullscreen: widget.isFullscreen,
                  onTogglePlay: _togglePlay,
                  onSeekPreview: (p) => setState(() => _dragPosition = p),
                  onSeekCommit: (p) {
                    setState(() => _dragPosition = null);
                    _seekTo(p);
                  },
                  onVolume: _setVolume,
                  onRate: _setRate,
                  onAudio: _setAudio,
                  onSubtitle: _setSubtitle,
                  onToggleFullscreen: widget.onToggleFullscreen,
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
  const _AnimatedEdge({required this.visible, required this.alignment, required this.child});
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            _ChromeIconButton(icon: Icons.arrow_back, tooltip: 'Back', onPressed: onBack),
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
    required this.rate,
    required this.tracks,
    required this.selectedAudio,
    required this.selectedSubtitle,
    required this.isFullscreen,
    required this.onTogglePlay,
    required this.onSeekPreview,
    required this.onSeekCommit,
    required this.onVolume,
    required this.onRate,
    required this.onAudio,
    required this.onSubtitle,
    required this.onToggleFullscreen,
  });

  final bool canControl;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final double rate;
  final PlayerTracks tracks;
  final String? selectedAudio;
  final String? selectedSubtitle;
  final bool isFullscreen;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeekCommit;
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onRate;
  final ValueChanged<String?> onAudio;
  final ValueChanged<String?> onSubtitle;
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
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
          _Scrubber(
            position: position,
            duration: duration,
            enabled: canControl,
            onPreview: onSeekPreview,
            onCommit: onSeekCommit,
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
                style: AppTheme.mono.copyWith(color: AppColors.dim, fontSize: 12),
              ),
              const Spacer(),
              _VolumeControl(volume: volume, onChanged: onVolume),
              _RateMenu(rate: rate, enabled: canControl, onChanged: onRate),
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
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onPreview,
    required this.onCommit,
  });

  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onPreview;
  final ValueChanged<Duration> onCommit;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final value = totalMs > 0
        ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
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
              : (v) => onPreview(Duration(milliseconds: (v * totalMs).round())),
          onChangeEnd: (!enabled || totalMs <= 0)
              ? null
              : (v) => onCommit(Duration(milliseconds: (v * totalMs).round())),
        ),
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.volume, required this.onChanged});
  final double volume;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Volume',
      offset: const Offset(0, -140),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: StatefulBuilder(
            builder: (context, setLocal) => SizedBox(
              height: 120,
              width: 40,
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.line2,
                    thumbColor: AppColors.accent,
                  ),
                  child: Slider(
                    value: volume,
                    min: 0,
                    max: 100,
                    onChanged: (v) {
                      setLocal(() {});
                      onChanged(v);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      child: _ChromeIconButton(
        icon: volume <= 0
            ? Icons.volume_off
            : (volume < 50 ? Icons.volume_down : Icons.volume_up),
        tooltip: 'Volume',
        onPressed: null,
        forceEnabled: true,
      ),
    );
  }
}

class _RateMenu extends StatelessWidget {
  const _RateMenu({required this.rate, required this.enabled, required this.onChanged});
  final double rate;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      enabled: enabled,
      initialValue: rate,
      onSelected: onChanged,
      itemBuilder: (context) => _PlayerChromeStateAccessor.rates
          .map((r) => PopupMenuItem<double>(
                value: r,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (r == rate) const Icon(Icons.check, size: 16, color: AppColors.accent),
                    if (r == rate) const SizedBox(width: AppSpacing.xs),
                    Text('${r}x', style: AppTheme.body),
                  ],
                ),
              ))
          .toList(),
      child: _ChromeIconButton(
        icon: Icons.speed,
        tooltip: 'Playback speed',
        onPressed: null,
        forceEnabled: enabled,
        label: rate == 1.0 ? null : '${rate}x',
      ),
    );
  }
}

/// Small holder so [_RateMenu] can reach the canonical rate list without
/// threading it through another constructor param.
abstract final class _PlayerChromeStateAccessor {
  static const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
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
    return PopupMenuButton<String?>(
      tooltip: tooltip,
      enabled: enabled,
      onSelected: onChanged,
      itemBuilder: (context) => [
        if (allowNone)
          PopupMenuItem<String?>(
            value: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected == null) const Icon(Icons.check, size: 16, color: AppColors.accent),
                if (selected == null) const SizedBox(width: AppSpacing.xs),
                const Text('Off', style: AppTheme.body),
              ],
            ),
          ),
        for (final t in tracks)
          PopupMenuItem<String?>(
            value: t.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.id == selected) const Icon(Icons.check, size: 16, color: AppColors.accent),
                if (t.id == selected) const SizedBox(width: AppSpacing.xs),
                Text(t.title ?? t.language ?? t.id, style: AppTheme.body),
              ],
            ),
          ),
      ],
      child: _ChromeIconButton(icon: icon, tooltip: tooltip, onPressed: null, forceEnabled: enabled),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.forceEnabled = false,
    this.label,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool forceEnabled;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null || forceEnabled;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: label == null
            ? Icon(icon, size: 20)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 2),
                  Text(label!, style: AppTheme.caption),
                ],
              ),
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
      color: const Color(0x8C000000),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
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
