import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../analog/chrome/analog_select.dart';
import '../analog/chrome/chrome.dart';
import 'package:flutter/services.dart';

import '../analog/player/analog_settings_stack.dart';
import '../analog/player/analog_timeline.dart';
import '../analog/player/analog_volume.dart';
import '../analog/player/auto_hide_controller.dart';
import '../analog/player_core.dart';
import '../cache/range_cache_store.dart' show CachedSpan;
import '../data/api_client.dart';
import '../models/playback_info.dart';
import '../models/trickplay_manifest.dart';
import '../ui/analog_tokens.dart';
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
    this.onSeekAuthored,
    this.itemId,
    this.mediaSourceId,
    this.apiClient,
    this.preferredSubtitleStreamIndex,
    this.cachedSpans,
    this.visible,
    this.onWake,
    this.onToggleChat,
    this.onPushToTalkStart,
    this.onPushToTalkStop,
    this.chatOpen = false,
    this.chatToasts = const [],
  });

  final PlayerController controller;
  final bool canControl;
  final String? title;
  final VoidCallback? onBack;

  /// When non-null, chrome visibility is owned by the app-wide player host and
  /// this widget stops running its own idle timer
  /// — it renders at [visible] and forwards activity via [onWake]. Null (solo
  /// playback / detail screen) keeps the built-in idle behaviour intact.
  final bool? visible;
  final VoidCallback? onWake;

  /// Party-only key bindings, independent of playback control: `c` toggles chat,
  /// hold-`T` is push-to-talk. Null in solo playback (the keys do nothing).
  final VoidCallback? onToggleChat;
  final VoidCallback? onPushToTalkStart;
  final VoidCallback? onPushToTalkStop;

  /// Whether the party chat drawer is open. Toasts exist only while it is
  /// closed, and opening it dismisses the ones on screen.
  final bool chatOpen;

  /// The party chat log, oldest first. Entries the chrome has not seen before
  /// are queued as toasts (stamped with the LOCAL clock, so a skewed server
  /// timestamp cannot expire a message the instant it arrives). Empty in solo
  /// playback — there is no chat to notify about.
  final List<ToastMessage> chatToasts;

  /// Cached ("downloaded") byte-range spans for [itemId], as 0..1 fractions
  /// of total length, painted behind the scrubber's play-progress as a
  /// buffered-style indicator. Null for the offline-local-file playback path
  /// (nothing to show — the whole file is already local) and for
  /// tests/mocks that don't wire a cache proxy.
  final ValueListenable<List<CachedSpan>>? cachedSpans;

  final String? itemId;
  final String? mediaSourceId;
  final ApiClient? apiClient;
  final int? preferredSubtitleStreamIndex;

  /// Host owns fullscreen (window-level); chrome just renders the affordance.
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  /// Reports a seek this viewer authored, after it has been applied locally.
  /// A party publishes it to the room from here.
  final ValueChanged<Duration>? onSeekAuthored;

  @override
  State<PlayerChrome> createState() => _PlayerChromeState();
}

class _PlayerChromeState extends State<PlayerChrome>
    with WidgetsBindingObserver {
  final _focusNode = FocusNode();

  /// The single auto-hide clock, driven by `analog/player_core.dart`. Only
  /// armed on the solo path — the party screen owns an identical controller and
  /// passes the resolved flag down through [PlayerChrome.visible].
  late final AnalogAutoHideController _autoHide;

  ToastQueueState _toasts = const ToastQueueState();
  final Set<String> _seenToastIds = {};
  final Map<String, Timer> _toastTimers = {};
  int _toastStampMs = 0;

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

  /// Playback speed. Purely local: it is a per-viewer comfort setting, and a
  /// party's shared timeline owns the rate everyone actually watches at, so
  /// this is only offered when nobody else is being dragged along.
  double _rate = 1;
  String? _selectedAudio;
  String? _selectedSubtitle;

  /// Anchors for [showAnalogSelect]. Held here rather than built inline
  /// because a [GlobalKey] recreated on every rebuild anchors nothing, and
  /// the settings-stack rows are gone by the time their picker opens — so the
  /// picker hangs off the gear that is still on screen.
  final _subtitleAnchor = GlobalKey(debugLabel: 'subtitleControl');
  final _settingsAnchor = GlobalKey(debugLabel: 'settingsStack');

  /// The scrubber. Menus opened from the transport row sit above it rather
  /// than over it — the controls are BELOW the timeline, so hanging a menu off
  /// a control put it straight on top of the bar you were about to drag.
  final _timelineAnchor = GlobalKey(debugLabel: 'timeline');

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
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onGlobalFocusChange);
    _autoHide = AnalogAutoHideController(
      playing: widget.controller.isPlayingNow,
    )..addListener(_onAutoHide);
    _bindController(widget.controller);
    _syncToasts(seed: true);
    _loadTrickplay();
    _loadExternalSubtitles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyCanonicalTracks();
    });
  }

  /// Seed every mirrored field from [c]'s real state and subscribe to its
  /// streams. Assignments only, no `setState` — callers own the rebuild
  /// (`initState` runs before the first build; [didUpdateWidget] wraps it).
  void _bindController(PlayerController c) {
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
        _autoHide.setPlaying(p);
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
  }

  void _unbindController() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void didUpdateWidget(PlayerChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // A replaced controller left this chrome subscribed to the OLD player: the
      // transport bar kept mirroring a position/duration/track set nobody was
      // watching, every control wrote to the new player, and none of the new
      // player's own state was ever read. Drop the old streams and re-seed.
      _unbindController();
      // Anything still resolving against the previous player (an external
      // subtitle fetch) must not land on the new one.
      _subtitleSelectionVersion++;
      setState(() {
        _subtitleCues = const [];
        _selectedSubtitle = null;
        // These native track ids were injected into the OLD player; the new one
        // has no such tracks, so keeping them would hide real subtitle entries.
        _loadedExternalSubtitleTrackIds.clear();
        _bindController(widget.controller);
      });
      _autoHide.setPlaying(widget.controller.isPlayingNow);
      unawaited(_applyCanonicalTracks());
    }
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.mediaSourceId != widget.mediaSourceId ||
        oldWidget.apiClient != widget.apiClient) {
      _loadTrickplay();
      _loadExternalSubtitles();
    }
    if (oldWidget.chatOpen != widget.chatOpen) {
      // Opening chat dismisses what is on screen and does not resurrect it on
      // close; the drawer shows the messages in full.
      _toasts = setChatOpen(_toasts, widget.chatOpen);
      _armToastTimers();
    }
    if (!identical(oldWidget.chatToasts, widget.chatToasts)) _syncToasts();
  }

  // ── chat toasts ───────────────────────────────────────────────────────────

  /// Queue every message this chrome has not seen before. Ids are remembered
  /// separately from the queue so a toast that already expired (or arrived
  /// while chat was open) is never re-queued when the log rebuilds.
  ///
  /// [seed] marks the log as already-seen without queueing any of it: joining a
  /// party mid-session must not fire the whole backlog at the viewer.
  void _syncToasts({bool seed = false}) {
    var next = setChatOpen(_toasts, widget.chatOpen);
    for (final message in widget.chatToasts) {
      if (!_seenToastIds.add(message.id)) continue;
      if (seed) continue;
      next = pushToast(
        next,
        ToastMessage(
          id: message.id,
          userId: message.userId,
          sender: message.sender,
          preview: message.preview,
          // Stamps are a strictly increasing sequence, not epoch time: the four
          // seconds are measured by the toast's OWN Timer below, and using wall
          // time here would only introduce clock skew against the server
          // timestamp and make the rule undrivable from a test clock.
          receivedAtMs: _toastStampMs++,
        ),
      );
    }
    if (identical(next, _toasts)) return;
    setState(() => _toasts = next);
    _armToastTimers();
  }

  /// "Each toast remains for four seconds unless chat is opened first" — so
  /// each one gets its own timer rather than a shared poll. When it fires, the
  /// shared [expireToasts] is handed that toast's deadline, which drops it and
  /// anything older still lingering.
  void _armToastTimers() {
    final live = {for (final toast in _toasts.queue) toast.id};
    _toastTimers.removeWhere((id, timer) {
      if (live.contains(id)) return false;
      timer.cancel();
      return true;
    });
    for (final toast in _toasts.queue) {
      if (_toastTimers.containsKey(toast.id)) continue;
      _toastTimers[toast.id] = Timer(AnalogTiming.toastLifetimeMs, () {
        _toastTimers.remove(toast.id);
        if (!mounted) return;
        final next = expireToasts(
          _toasts,
          toast.receivedAtMs + AnalogTiming.toastLifetimeMs.inMilliseconds,
        );
        if (identical(next, _toasts)) return;
        setState(() => _toasts = next);
        _armToastTimers();
      });
    }
  }

  void _cancelToastTimers() {
    for (final timer in _toastTimers.values) {
      timer.cancel();
    }
    _toastTimers.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // "Message content must not remain visible on a locked or backgrounded
    // device." Anything queued is dropped rather than held for the return.
    if (state == AppLifecycleState.resumed) return;
    if (_toasts.queue.isEmpty) return;
    _cancelToastTimers();
    setState(() => _toasts = ToastQueueState(chatOpen: _toasts.chatOpen));
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

  /// Identity for de-duplication: title and language, NOT codec.
  ///
  /// Codec used to be part of this, and it is exactly the field that disagrees
  /// across the two descriptions of one subtitle. Jellyfin describes an
  /// external track one way; once selected, mpv loads it and reports the same
  /// subtitle back through the player's own track list with a different (often
  /// absent) codec. The two signatures then differed, nothing filtered either
  /// out, and the picker grew a second "English" the moment you chose the
  /// first — which is what made re-opening the menu show the entry twice.
  ///
  /// [_loadedExternalSubtitleTrackIds] is meant to catch this by native id, but
  /// only records one when `currentSubtitleTrackId` is already populated, and
  /// mpv updates its track list asynchronously after the add. So the id map is
  /// the fast path and this is the one that has to hold.
  ///
  /// The cost is that two tracks with the same title AND language in different
  /// formats collapse into one entry. That is rare, and a picker showing one of
  /// them is a much smaller problem than a picker that grows an entry every
  /// time it is used.
  static String _subtitleTrackSignature(PlayerTrack track) => [
    track.title,
    track.language,
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
      _playbackInfo = info;
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
        final preferred = widget.preferredSubtitleStreamIndex;
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
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    _cancelToastTimers();
    _autoHide
      ..removeListener(_onAutoHide)
      ..dispose();
    _unbindController();
    _focusNode.dispose();
    super.dispose();
  }

  /// Re-anchor the keymap when focus is left nowhere useful — the widget that
  /// held it was disposed (an overlay closing), or focus fell back to a bare
  /// scope. Without this the player keeps rendering but answers no keys, and the
  /// platform beeps at every one. Deliberately narrow: a live focus on any real
  /// widget, including another button or a text field, is left alone.
  void _onGlobalFocusChange() {
    final pf = FocusManager.instance.primaryFocus;
    final stranded = pf == null || pf.context == null || pf is FocusScopeNode;
    if (stranded) _reclaimKeyboard();
  }

  void _onAutoHide() {
    if (mounted) setState(() {});
  }

  /// Relevant input: reveal the chrome and restart the three second clock.
  ///
  /// Both auto-hide owners run the SAME `analog/player_core.dart` machine — the
  /// party screen holds one [AnalogAutoHideController] for the whole immersive
  /// stage and passes its flag down as [PlayerChrome.visible]; solo playback
  /// uses the one this state owns. When the parent owns it, activity is
  /// forwarded so its timer re-arms.
  void _wake([PlayerInputKind kind = PlayerInputKind.pointer]) {
    if (widget.visible != null) {
      widget.onWake?.call();
      return;
    }
    _autoHide.noteInput(kind);
  }

  /// Pin the chrome open for the length of an interaction (a scrub, an open
  /// settings stack). Without it the surface you are using vanishes under the
  /// cursor after three seconds.
  void _hold(String reason) {
    if (widget.visible != null) {
      widget.onWake?.call();
      return;
    }
    _autoHide.hold(reason);
  }

  void _release(String reason) {
    if (widget.visible != null) {
      widget.onWake?.call();
      return;
    }
    _autoHide.release(reason);
  }

  void _setHold(String reason, bool held) =>
      held ? _hold(reason) : _release(reason);

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
    widget.onSeekAuthored?.call(clamped);
    _wake();
  }

  Future<void> _seekTo(Duration position) async {
    if (!widget.canControl) return;
    await widget.controller.seek(position);
    widget.onSeekAuthored?.call(position);
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

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    await widget.controller.setRate(rate);
    _wake();
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

  /// mpv's `sub-pos` and the shared preference run in OPPOSITE directions:
  /// sub-pos 100 is the bottom of the frame, and the preference counts upward
  /// from the bottom because that is how the setting reads to a person. One
  /// conversion, in one place, rather than the arithmetic appearing at each
  /// call site and eventually disagreeing with itself.
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

  Future<void> _setSubtitleFont(String font) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subFont = font);
    await c.setSubtitleFont(font);
    _wake();
  }

  Future<void> _setSubtitleColor(String color) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subColor = color.toUpperCase());
    await c.setSubtitleColor(_subColor);
  }

  Future<void> _setSubtitleBackgroundOpacity(int percent) async {
    final c = widget.controller;
    if (c is! MediaKitPlayerController) return;
    setState(() => _subBackgroundOpacity = percent);
    await c.setSubtitleBackgroundOpacity(percent);
  }

  Future<void> _applyCanonicalTracks() async {
    final playback = _playbackInfo;
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
      await _setAudio(audioId);
    }
    if (playback.selectedSubtitleIndex != null) {
      await _setSubtitle(subtitleId);
    }
  }

  /// Opens a compact panel with sliders for subtitle size, vertical position,
  /// and timing offset. Only wired when the live MediaKitPlayerController is in
  /// use. Kept in a Material dialog (the chrome lives under a Scaffold), so the
  /// sliders are ordinary Material [Slider]s.
  Future<void> _openSubtitleSettings() async {
    if (widget.controller is! MediaKitPlayerController) return;
    _hold('subtitleSettings'); // keep the chrome awake while the dialog is open
    await showDialog<void>(
      // Plain `context`: the chrome sits inside its own Navigator now, so a
      // dialog opened from here lands above the player rather than behind it.
      // (The comment above used to say the chrome lives under a Scaffold; that
      // stopped being true when the player moved above the router.)
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _SubtitleSettingsDialog(
        scale: _subScale,
        position: _subPos,
        delay: _subDelay,
        font: _subFont,
        color: _subColor,
        backgroundOpacity: _subBackgroundOpacity,
        enabled: true,
        onScale: _setSubtitleScale,
        onPosition: _setSubtitlePosition,
        onDelay: _setSubtitleDelay,
        onFont: _setSubtitleFont,
        onColor: _setSubtitleColor,
        onBackgroundOpacity: _setSubtitleBackgroundOpacity,
      ),
    );
    _release('subtitleSettings');
  }

  Future<void> _setAudio(String? id) async {
    setState(() => _selectedAudio = id);
    await widget.controller.setAudioTrack(id);
    _wake();
  }

  Future<void> _setSubtitle(String? id) async {
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

  /// Take keyboard focus back unless the user is typing (party chat lives
  /// outside this subtree and must keep its keystrokes).
  void _reclaimKeyboard() {
    if (!mounted || !_focusNode.canRequestFocus || _focusNode.hasPrimaryFocus) {
      return;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        focused.findAncestorStateOfType<EditableTextState>() != null) {
      return;
    }
    _focusNode.requestFocus();
  }

  /// Whether keyboard focus is inside a text field, and whether that field has a
  /// live selection. Flutter has no global selection registry outside a
  /// [SelectableRegion], so a selection is only observable where the platform
  /// copy command is actually meaningful: an editable.
  (bool editable, bool hasSelection) get _editableFocus {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return (false, false);
    final editor = focused.findAncestorStateOfType<EditableTextState>();
    if (editor == null) return (false, false);
    final selection = editor.textEditingValue.selection;
    return (true, selection.isValid && !selection.isCollapsed);
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

    // Every binding below is a BARE key. Holding Ctrl/Cmd turns the same
    // keystroke into a platform or application command — Ctrl+C copy, Ctrl+T
    // new tab/window, Ctrl+F find — and the player used to match on the logical
    // key alone and return `handled`, swallowing all of them. The one
    // deliberate exceptions are Ctrl/Cmd+C for chat and Ctrl/Cmd+F for
    // fullscreen.
    final ctrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        widget.onToggleChat != null) {
      final (editable, hasSelection) = _editableFocus;
      final accelerator = shouldToggleChat(
        ChatShortcutContext(
          ctrlOrMeta: ctrlOrMeta,
          key: 'c',
          editable: editable,
          hasSelection: hasSelection,
        ),
      );
      if (accelerator || (!ctrlOrMeta && !editable)) {
        _wake(PlayerInputKind.key);
        widget.onToggleChat!();
        return KeyEventResult.handled;
      }
      // Ctrl+C with a selection, or any C typed into a field: leave it to the
      // platform so copy still copies.
      return KeyEventResult.ignored;
    }

    if (ctrlOrMeta && event.logicalKey == LogicalKeyboardKey.keyF) {
      widget.onToggleFullscreen?.call();
      return KeyEventResult.handled;
    }

    if (ctrlOrMeta) return KeyEventResult.ignored;
    _wake(PlayerInputKind.key);

    // Chat + push-to-talk are A/V-layer bindings available to guests too, so
    // they run before the canControl transport gate. Key-repeat arrives as a
    // KeyRepeatEvent (not KeyDownEvent), so hold-T fires start exactly once.
    if (event.logicalKey == LogicalKeyboardKey.keyT &&
        widget.onPushToTalkStart != null) {
      widget.onPushToTalkStart!();
      return KeyEventResult.handled;
    }

    // Volume, mute and fullscreen are personal, per-viewer settings: their
    // BUTTONS have always been ungated (a no-control guest can still turn the
    // sound down), but their keys used to sit behind `canControl`, so the same
    // guest's ↑/↓/M/F did nothing. The buttons are right — the keys move out.
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _setVolume(math.min(100, _volume + kAnalogVolumeKeyStep));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _setVolume(math.max(0, _volume - kAnalogVolumeKeyStep));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        widget.onToggleFullscreen?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        _toggleMute();
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
    }
    return KeyEventResult.ignored;
  }

  /// Speeds offered by the settings stack. Deliberately short: a rate picker
  /// with eleven rows is a rate picker nobody scrolls to the end of.
  static const List<double> _rates = [0.5, 0.75, 1, 1.25, 1.5, 2];

  static String _rateLabel(double rate) =>
      rate == rate.roundToDouble() ? '${rate.toInt()}×' : '$rate×';

  /// Language / audio track, as its own picker off the settings stack.
  Future<void> _openAudioPicker() async {
    _hold('audioPicker');
    await showAnalogSelect<String?>(
      context: context,
      anchor: _settingsAnchor,
      liftAbove: _timelineAnchor,
      selected: _selectedAudio,
      groups: [
        AnalogChoiceGroup<String?>(
          icon: Icons.audiotrack,
          choices: [
            for (final (index, track) in _tracks.audio.indexed)
              AnalogChoice<String?>(
                value: track.id,
                label: _trackName(track, index),
                detail: _trackDetail(track),
              ),
          ],
        ),
      ],
      onSelected: _setAudio,
    );
    _release('audioPicker');
  }

  Future<void> _openSpeedPicker() async {
    _hold('speedPicker');
    await showAnalogSelect<double>(
      context: context,
      anchor: _settingsAnchor,
      liftAbove: _timelineAnchor,
      selected: _rate,
      width: 200,
      groups: [
        AnalogChoiceGroup<double>(
          icon: Icons.speed,
          choices: [
            for (final rate in _rates)
              AnalogChoice<double>(
                value: rate,
                label: rate == 1 ? 'Normal' : _rateLabel(rate),
                detail: rate == 1 ? '1×' : null,
              ),
          ],
        ),
      ],
      onSelected: _setRate,
    );
    _release('speedPicker');
  }

  /// The settings stack's contents, top to bottom in the order the reference
  /// names them: subtitle settings, language/audio track, speed, then whatever
  /// the concrete engine adds.
  ///
  /// Each row opens its own picker through [showAnalogSelect] — the kit's
  /// dropdown — so the player carries no menu implementation of its own. The
  /// direct subtitle control stays OUTSIDE this stack: Off and a track swap
  /// must not cost two taps.
  ///
  /// Subtitle styling and the decoder are libmpv-only and simply absent on a
  /// mock/spy controller; speed rides the frozen [PlayerController] contract
  /// and is always offered.
  List<AnalogSettingsEntry> _settingsEntries() {
    final mediaKit = widget.controller is MediaKitPlayerController;
    return [
      if (mediaKit)
        AnalogSettingsEntry(
          icon: Icons.tune,
          label: 'Subtitle settings',
          onTap: _openSubtitleSettings,
        ),
      if (_tracks.audio.isNotEmpty)
        AnalogSettingsEntry(
          icon: Icons.audiotrack,
          label: 'Audio track',
          detail: _audioTrackDetail,
          // A guest may read which track the party is on but not change it.
          enabled: true,
          onTap: _openAudioPicker,
        ),
      AnalogSettingsEntry(
        icon: Icons.speed,
        label: 'Speed',
        detail: _rate == 1 ? 'Normal' : _rateLabel(_rate),
        enabled: widget.canControl,
        onTap: _openSpeedPicker,
      ),
      if (mediaKit)
        AnalogSettingsEntry(
          icon: Icons.memory,
          label: 'Video decoder',
          detail: _hwDecoding ? 'Hardware' : 'Software',
          // Same gate the decode menu carried: a guest sees which decoder is in
          // use but cannot switch it.
          enabled: widget.canControl,
          onTap: () => _setHardwareDecoding(!_hwDecoding),
        ),
    ];
  }

  String? get _audioTrackDetail {
    for (final (index, track) in _tracks.audio.indexed) {
      if (track.id == _selectedAudio) return _trackName(track, index);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final activeCues = activeSubtitleCues(
      _subtitleCues,
      _position,
      delay: Duration(milliseconds: (_subDelay * 1000).round()),
    );
    // Parent-owned visibility (party) wins; otherwise this chrome's own
    // controller — both are the same player_core state machine.
    final visible = widget.visible ?? _autoHide.visible;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: visible ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) => _wake(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            _wake(PlayerInputKind.tap);
            // Re-anchor the keymap. autofocus only fires once, at mount: after
            // focus moves to an overlay (the settings menu) or the window loses
            // and regains it, primary focus can land outside this subtree and
            // every keystroke becomes unhandled — the shortcuts silently stop
            // working and macOS rings the alert bell at each one. Clicking the
            // stage is the natural "give me the player back" gesture.
            _reclaimKeyboard();
          },
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
                  canManageTracks: true,
                  playing: _playing,
                  position: _dragPosition ?? _position,
                  duration: _duration,
                  subtitleTracks: _visibleSubtitleTracks,
                  subtitleAnchor: _subtitleAnchor,
                  settingsAnchor: _settingsAnchor,
                  timelineAnchor: _timelineAnchor,
                  selectedSubtitle: _selectedSubtitle,
                  isFullscreen: widget.isFullscreen,
                  // Decode + subtitle-styling are additive libmpv features:
                  // only surface them when the live MediaKitPlayerController is
                  // in use (mock/spy controllers get the base bar). They are the
                  // settings stack's contents; an empty list hides the gear.
                  settings: _settingsEntries(),
                  onSettingsOpenChanged: (open) =>
                      _setHold('settingsStack', open),
                  onAddSubtitle: widget.controller is MediaKitPlayerController
                      ? _addSubtitleFile
                      : null,
                  onTogglePlay: _togglePlay,
                  onSeekPreview: (p) => setState(() => _dragPosition = p),
                  onSeekCommit: (p) {
                    setState(() => _dragPosition = null);
                    _seekTo(p);
                  },
                  onScrubbingChanged: (scrubbing) =>
                      _setHold('scrub', scrubbing),
                  onSubtitleMenuChanged: (open) =>
                      _setHold('subtitleMenu', open),
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

              // Volume: a VERTICAL hairline on the right edge, centred on the
              // stage, with mute directly beneath it so the two audio controls
              // read as one group. Fades with the rest of the chrome.
              _AnimatedEdge(
                visible: visible,
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: AnalogSpace.mdPx),
                  child: AnalogVolume(
                    volume: _volume,
                    trackKey: const Key('volumeSlider'),
                    trackLength: 132,
                    showMuteButton: true,
                    onChanged: _setVolume,
                    onToggleMute: _toggleMute,
                    onAdjustingChanged: (adjusting) =>
                        _setHold('volume', adjusting),
                  ),
                ),
              ),

              // Chat notices are NOT drawn here any more. They were, at the top
              // left, and this widget is the party screen's Stack index 0 —
              // underneath the floating camera tiles. A message arriving while
              // someone's tile happened to sit there appeared BEHIND their
              // face, which is the one place a notice cannot be seen.
              //
              // There is one notification path now: the app-wide rail
              // (ChatNotifications -> AnalogToastHost), mounted above the
              // router, so nothing the player or the party draws can cover it.
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
    if (onBack == null && title == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      // Inset to put the back button exactly where every other surface puts it
      // — see [BackButtonPlacement]. Leaving the player on its own bar padding
      // meant the one control you reach for on the way out of a film moved as
      // you entered it.
      padding: EdgeInsets.only(
        left: BackButtonPlacement.left,
        top: BackButtonPlacement.top,
        right: AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      // Flat near-black translucent bar — no gradients per the design system.
      decoration: const BoxDecoration(color: _kChromeScrim),
      child: Row(
        children: [
          if (onBack != null) GlassBackButton(onTap: onBack!),
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
          if (title == null) const Spacer(),
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
    required this.subtitleTracks,
    required this.subtitleAnchor,
    required this.settingsAnchor,
    required this.timelineAnchor,
    required this.selectedSubtitle,
    required this.isFullscreen,
    required this.settings,
    required this.onSettingsOpenChanged,
    required this.onAddSubtitle,
    required this.onTogglePlay,
    required this.onSeekPreview,
    required this.onSeekCommit,
    required this.onScrubbingChanged,
    required this.onSubtitleMenuChanged,
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

  /// Only the subtitle set. Audio-track selection moved into the settings
  /// stack, where the reference groups it under language/audio.
  final List<PlayerTrack> subtitleTracks;
  final GlobalKey subtitleAnchor;
  final GlobalKey settingsAnchor;

  /// The scrubber, so menus can open clear of it.
  final GlobalKey timelineAnchor;
  final String? selectedSubtitle;

  final bool isFullscreen;

  /// Rows of the upward settings stack. Empty hides the gear entirely.
  final List<AnalogSettingsEntry> settings;
  final ValueChanged<bool> onSettingsOpenChanged;

  /// Picks a local subtitle file to side-load. Null on non-media_kit
  /// controllers; when non-null the subtitle menu is always shown (so the user
  /// can load a file even when the media carries no subtitle tracks).
  final VoidCallback? onAddSubtitle;

  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeekCommit;
  final ValueChanged<bool> onScrubbingChanged;

  /// Raised while the subtitle picker is on screen so the chrome is held open —
  /// without it the menu vanishes under the cursor after three seconds.
  final ValueChanged<bool> onSubtitleMenuChanged;
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
            key: timelineAnchor,
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              children: [
                _Timeline(
                  key: const Key('playbackScrubber'),
                  position: position,
                  duration: duration,
                  enabled: canControl,
                  onPreview: onSeekPreview,
                  onCommit: onSeekCommit,
                  onScrubbingChanged: onScrubbingChanged,
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
                // Hover/drag time label. Only stands in when there is no
                // trickplay card — with no manifest, hovering the bar used to
                // show nothing at all.
                if (previewPosition != null &&
                    (trickplay == null || apiClient == null))
                  Positioned(
                    bottom: 24,
                    left: (previewFraction * constraints.maxWidth - 28).clamp(
                      0.0,
                      math.max(0.0, constraints.maxWidth - 56),
                    ),
                    child: IgnorePointer(
                      child: _HoverTimeLabel(label: _fmt(previewPosition!)),
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
              // Lower-right cluster: subtitle, settings, fullscreen. Mute is
              // NOT here — it rides under the right-edge volume hairline, with
              // the control it belongs to.
              if (onAddSubtitle != null || subtitleTracks.isNotEmpty)
                _SubtitleControl(
                  key: subtitleAnchor,
                  liftAbove: timelineAnchor,
                  tracks: subtitleTracks,
                  selected: selectedSubtitle,
                  enabled: canManageTracks,
                  onChanged: onSubtitle,
                  onAddFile: onAddSubtitle,
                  onMenuChanged: onSubtitleMenuChanged,
                ),
              if (settings.isNotEmpty)
                AnalogSettingsStack(
                  key: settingsAnchor,
                  liftAbove: timelineAnchor,
                  entries: settings,
                  onOpenChanged: onSettingsOpenChanged,
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

/// Adapts the analog [AnalogTimeline] to the transport bar's inputs: cached
/// spans arrive as a [ValueListenable] of byte fractions from the media cache
/// proxy, and are mapped straight onto normalised timeline ranges.
///
/// Replaces the Material [Slider] + custom track shape this used to be. The
/// slider could not render disjoint ranges (its only extra layer was one flat
/// run of `drawRect`s), and its thumb radius collapsed to 0 when disabled, so a
/// read-only guest saw a bar with no position marker at all.
class _Timeline extends StatelessWidget {
  const _Timeline({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onPreview,
    required this.onCommit,
    required this.onScrubbingChanged,
    required this.onHoverPreview,
    required this.onHoverEnd,
    this.cachedSpans,
  });

  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onPreview;
  final ValueChanged<Duration> onCommit;
  final ValueChanged<bool> onScrubbingChanged;
  final void Function(Duration position, double fraction) onHoverPreview;
  final VoidCallback onHoverEnd;

  /// Cached ("downloaded") spans, already on disk. Byte fractions, which only
  /// approximate time for variable-bitrate media — see the caveat on
  /// [CachedSpan]. Null/empty renders that layer empty.
  final ValueListenable<List<CachedSpan>>? cachedSpans;

  AnalogTimeline _timeline(List<CachedSpan> spans) => AnalogTimeline(
    position: position,
    duration: duration,
    enabled: enabled,
    onPreview: onPreview,
    onCommit: onCommit,
    onScrubbingChanged: onScrubbingChanged,
    onHoverPreview: onHoverPreview,
    onHoverEnd: onHoverEnd,
    cached: [for (final span in spans) TimelineRange(span.start, span.end)],
  );

  @override
  Widget build(BuildContext context) {
    final listenable = cachedSpans;
    if (listenable == null) return _timeline(const []);
    return ValueListenableBuilder<List<CachedSpan>>(
      valueListenable: listenable,
      builder: (context, spans, _) => _timeline(spans),
    );
  }
}

/// The scrub-time readout that follows the pointer along the bar. Stands in for
/// the trickplay card when the title has no manifest.
class _HoverTimeLabel extends StatelessWidget {
  const _HoverTimeLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AnalogSpace.smPx,
        vertical: AnalogSpace.xsPx,
      ),
      decoration: BoxDecoration(
        color: AnalogColor.backdropScrim,
        borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
        border: Border.all(color: AnalogColor.line),
      ),
      child: Text(
        label,
        style: AppTheme.mono.copyWith(color: AnalogColor.ink, fontSize: 11),
      ),
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
              // The last DropdownButton in the app. It carried Material's own
              // menu — a different surface, radius and open animation from
              // every other picker here, inside a sheet that is otherwise all
              // kit chrome.
              _FontField(
                key: const Key('subtitleFont'),
                value: _font,
                enabled: widget.enabled,
                onChanged: (font) {
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
              // Height above the bottom, continuously.
              //
              // This was three detents — Top, Middle, Bottom — snapping to
              // 10/50/100, which is not a position control so much as a choice
              // of three places to be. Subtitles need to clear a hardcoded
              // burned-in caption, a chat drawer, a black bar; none of those is
              // a third of the way up.
              //
              // The axis reads upward from the bottom because that is the
              // default and the thing being adjusted is how far to LIFT them
              // off it. 20 divisions gives 5% steps: fine enough to clear an
              // obstacle, coarse enough to land on a round number and to be
              // driven from a keyboard.
              _slider(
                palette: wp,
                label: 'Height',
                value: (100 - _position).toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: _position >= 100
                    ? 'Bottom'
                    : (_position <= 0 ? 'Top' : '${100 - _position}%'),
                onChanged: !widget.enabled
                    ? null
                    : (v) {
                        final position = 100 - v.round();
                        setState(() => _position = position);
                        widget.onPosition(position);
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
                  AnalogButton(
                    tone: AnalogButtonTone.ghost,
                    dense: true,
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
                    label: 'Reset',
                  ),
                  AnalogButton(
                    tone: AnalogButtonTone.ghost,
                    dense: true,
                    onPressed: () => Navigator.of(context).pop(),
                    label: 'Done',
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

/// The direct subtitle control: Off, the track list, and a side-load action,
/// one tap from the transport row. It is shown even when the media carries no
/// subtitle tracks, so a local file can still be loaded.
///
/// The picker is [showAnalogSelect] — the kit's dropdown, the same one the
/// detail page and the settings stack use. This used to be a third, private
/// menu implementation living in this file (`_AnchoredPlayerMenu` and its
/// rows), which is two more than the app needs.
/// The subtitle-font picker, on the kit's dropdown.
///
/// A field showing the current value that opens [showAnalogSelect], rather
/// than a DropdownButton carrying Material's menu. Three fixed options, so the
/// list is inline — there is nothing to derive it from.
class _FontField extends StatefulWidget {
  const _FontField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  /// Value → label. The values are CSS font-family keywords and are what the
  /// player actually applies, so they are not free to be prettified.
  static const _options = <(String, String)>[
    ('sans-serif', 'Sans serif'),
    ('serif', 'Serif'),
    ('monospace', 'Monospace'),
  ];

  @override
  State<_FontField> createState() => _FontFieldState();
}

class _FontFieldState extends State<_FontField> {
  final GlobalKey _anchor = GlobalKey();

  String get _label {
    for (final (v, label) in _FontField._options) {
      if (v == widget.value) return label;
    }
    return widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: !widget.enabled
            ? null
            : () => showAnalogSelect<String>(
                context: context,
                anchor: _anchor,
                selected: widget.value,
                groups: [
                  AnalogChoiceGroup(
                    icon: Icons.text_fields,
                    choices: [
                      for (final (v, label) in _FontField._options)
                        AnalogChoice(value: v, label: label),
                    ],
                  ),
                ],
                onSelected: widget.onChanged,
              ),
        child: Container(
          key: _anchor,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: wp.surface2,
            borderRadius: BorderRadius.circular(AnalogRadius.cardPx),
            border: Border.all(color: wp.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.enabled ? wp.text : wp.dim,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: wp.dim),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleControl extends StatelessWidget {
  const _SubtitleControl({
    super.key,
    required this.liftAbove,
    required this.tracks,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.onAddFile,
    required this.onMenuChanged,
  });

  /// The scrubber, which the picker opens clear of.
  final GlobalKey liftAbove;

  final List<PlayerTrack> tracks;
  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  /// Picks a local subtitle file to side-load, or null if unsupported.
  final VoidCallback? onAddFile;

  /// Pins the chrome open for as long as the picker is up.
  final ValueChanged<bool> onMenuChanged;

  Future<void> _open(BuildContext context, GlobalKey anchor) async {
    onMenuChanged(true);
    await showAnalogSelect<String?>(
      context: context,
      anchor: anchor,
      liftAbove: liftAbove,
      selected: selected,
      groups: [
        AnalogChoiceGroup<String?>(
          icon: Icons.subtitles,
          choices: [
            const AnalogChoice<String?>(value: null, label: 'Off'),
            for (final (index, track) in tracks.indexed)
              AnalogChoice<String?>(
                value: track.id,
                label: _trackName(track, index),
                detail: _trackDetail(track),
              ),
          ],
        ),
      ],
      // Side-loading sits UNDER the list as a glyph, matching the detail
      // page's track dropdown.
      footerIcon: onAddFile == null ? null : Icons.upload_file_outlined,
      footerTooltip: 'Load subtitle file',
      onFooter: onAddFile,
      onSelected: onChanged,
    );
    onMenuChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    // `key` is the anchor the picker hangs off, so it has to name a render
    // object that is still mounted when the menu opens — this button.
    final anchor = key as GlobalKey;
    return _ChromeIconButton(
      icon: Icons.subtitles,
      tooltip: 'Subtitles',
      forceEnabled: enabled,
      onPressed: enabled ? () => _open(context, anchor) : null,
    );
  }
}

/// ISO-639 to something a viewer recognises. Both the two- and three-letter
/// codes are here because the demuxer hands over whichever the container used.
const Map<String, String> _languageNames = {
  'en': 'English',
  'eng': 'English',
  'es': 'Spanish',
  'spa': 'Spanish',
  'fr': 'French',
  'fra': 'French',
  'fre': 'French',
  'de': 'German',
  'deu': 'German',
  'ger': 'German',
  'it': 'Italian',
  'ita': 'Italian',
  'pt': 'Portuguese',
  'por': 'Portuguese',
  'ja': 'Japanese',
  'jpn': 'Japanese',
  'ko': 'Korean',
  'kor': 'Korean',
  'zh': 'Chinese',
  'zho': 'Chinese',
  'chi': 'Chinese',
  'th': 'Thai',
  'tha': 'Thai',
  'hi': 'Hindi',
  'hin': 'Hindi',
  'ar': 'Arabic',
  'ara': 'Arabic',
  'ru': 'Russian',
  'rus': 'Russian',
  'nl': 'Dutch',
  'nld': 'Dutch',
  'dut': 'Dutch',
  'pl': 'Polish',
  'pol': 'Polish',
  'sv': 'Swedish',
  'swe': 'Swedish',
  'da': 'Danish',
  'dan': 'Danish',
  'no': 'Norwegian',
  'nor': 'Norwegian',
  'fi': 'Finnish',
  'fin': 'Finnish',
  'tr': 'Turkish',
  'tur': 'Turkish',
  'he': 'Hebrew',
  'heb': 'Hebrew',
  'id': 'Indonesian',
  'ind': 'Indonesian',
  'vi': 'Vietnamese',
  'vie': 'Vietnamese',
  'cs': 'Czech',
  'ces': 'Czech',
  'cze': 'Czech',
  'el': 'Greek',
  'ell': 'Greek',
  'gre': 'Greek',
  'uk': 'Ukrainian',
  'ukr': 'Ukrainian',
  'ro': 'Romanian',
  'ron': 'Romanian',
  'rum': 'Romanian',
  'hu': 'Hungarian',
  'hun': 'Hungarian',
};

String? _languageName(String? raw) {
  final code = raw?.trim().toLowerCase();
  if (code == null || code.isEmpty) return null;
  // Strip a region suffix — "pt-BR" and "pt_BR" both key off "pt".
  final base = code.split(RegExp('[-_]')).first;
  return _languageNames[code] ?? _languageNames[base];
}

/// What the format means to someone choosing a track, not what libmpv calls it.
///
/// The picker used to print the codec verbatim, so a perfectly ordinary
/// Blu-ray subtitle announced itself as HDMV_PGS_SUBTITLE. Unknown codecs
/// return null and the row simply doesn't mention a format — a string nobody
/// can act on is worse than no string.
///
/// Audio tracks come through here too. Their format is worth keeping (picking
/// between DTS and stereo AAC is a real choice), it just gets spelled the way
/// a sleeve would spell it.
String? _formatName(String? raw) {
  final codec = raw?.trim().toLowerCase();
  if (codec == null || codec.isEmpty) return null;

  // Subtitles. Image-based ones are the whole reason this function exists:
  // they can't be restyled or scaled, which is the one thing worth knowing.
  if (codec.contains('pgs') ||
      codec.contains('dvdsub') ||
      codec.contains('dvd_sub') ||
      codec.contains('dvb') ||
      codec.contains('vobsub')) {
    return 'Image';
  }
  if (codec.contains('subrip') || codec.contains('srt')) return 'SRT';
  if (codec.contains('ass') || codec.contains('ssa')) return 'Styled';
  if (codec.contains('vtt')) return 'VTT';
  if (codec.contains('mov_text')) return 'Text';

  // Audio. Order matters: eac3 contains ac3, truehd contains hd.
  if (codec.contains('truehd')) return 'TrueHD';
  if (codec.contains('eac3') || codec.contains('e-ac-3')) {
    return 'Dolby Digital+';
  }
  if (codec.contains('ac3')) return 'Dolby Digital';
  if (codec.contains('dts')) return 'DTS';
  if (codec.contains('aac')) return 'AAC';
  if (codec.contains('opus')) return 'Opus';
  if (codec.contains('flac')) return 'FLAC';
  if (codec.contains('vorbis')) return 'Vorbis';
  if (codec.contains('mp3')) return 'MP3';
  if (codec.contains('pcm')) return 'PCM';
  return null;
}

/// The row's headline: what the file called the track, else its language, else
/// its position in the list. Never a raw track id.
String _trackName(PlayerTrack track, int index) {
  final title = track.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return _languageName(track.language) ??
      track.language?.trim().nullIfEmpty ??
      'Track ${index + 1}';
}

/// The quiet second line. Only carries what the headline didn't already say.
String? _trackDetail(PlayerTrack track) {
  final title = track.title?.trim().toLowerCase();
  final language = _languageName(track.language);
  final format = _formatName(track.codec);
  final details = <String>[
    // Skip the language when the title already names it.
    if (language != null &&
        (title == null ||
            title.isEmpty ||
            !title.contains(language.toLowerCase())))
      language,
    ?format,
    if (track.isDefault) 'Default',
  ];
  return details.isEmpty ? null : details.join(' · ');
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// Normalise picked subtitle bytes to UTF-8 text for side-loading: pass valid
/// UTF-8 through, otherwise re-decode as Latin-1, and strip any stray U+FFFD so
/// one bad glyph doesn't corrupt rendering.
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
