// The app's ONE player, mounted above the router.
//
// Every other approach to picture-in-picture in a Flutter app ends up with two
// player widgets — a big one on the watch screen and a small one somewhere else
// — and then spends its life trying to hand state between them. That is what
// this file exists to avoid. There is a single [PlayerView] element here, and
// "expanded" versus "floating" is a rect it animates between. Because the
// element identity never changes, the video texture is never re-attached: no
// reload, no position loss, no audio gap.
//
// Mounted in `app.dart`'s `MaterialApp.builder`, which wraps the Navigator —
// the same place `AnalogToastHost` and `ChatNotifications` already live, and for
// the same reason. A route cannot own something that has to outlive routing.

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analog/player/auto_hide_controller.dart';
import '../analog/player_core.dart';
import '../party/party_controls.dart';
import '../state/state.dart';
import '../data/api_client.dart';
import '../ui/ui.dart';
import '../ui/widgets/floating_camera_tile.dart';
import 'open_title.dart';
import 'player_view.dart';

/// Movies are 16:9, unlike the 4:3 camera tiles the geometry was written for.
const double _playerAspect = 16 / 9;

/// Starting width of the floating tile — wider than a camera, because a movie
/// at camera size is unreadable rather than merely small.
const double _defaultFloatingWidth = 300;

class PlayerHost extends ConsumerStatefulWidget {
  const PlayerHost({super.key});

  @override
  ConsumerState<PlayerHost> createState() => _PlayerHostState();
}

class _PlayerHostState extends ConsumerState<PlayerHost>
    with WindowListener, WidgetsBindingObserver {
  /// Chrome auto-hide, moved here from PartyScreen. It has to live with the
  /// player, not with a route, for the same reason the player does.
  late final AnalogAutoHideController _autoHide;
  static const String _kFloatingHold = 'floating';
  bool _pttHolding = false;

  /// OS-level window fullscreen for the film. Carried over from the deleted
  /// party route, which owned it — dropping it here is why the fullscreen
  /// button vanished: the transport bar only draws it when a handler exists.
  bool _isFullscreen = false;
  StreamSubscription<bool>? _playingSubscription;

  Future<void> _toggleFullscreen() async {
    final next = !await windowManager.isFullScreen();
    await windowManager.setFullScreen(next);
    if (mounted && _isFullscreen != next) setState(() => _isFullscreen = next);
  }

  Future<void> _exitFullscreen() async {
    if (!_isFullscreen) return;
    await windowManager.setFullScreen(false);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullscreen = false);
  }

  /// The Watch Party menu, on right-click or long-press over the picture.
  ///
  /// Also lost with the route. It is the only way to reach transfer-host,
  /// remove-someone and the sync modes from the film itself; the popcorn tray
  /// button is the other door, not a replacement for this one.
  bool _menuOpen = false;

  Future<void> _openPartyMenu() async {
    if (_menuOpen) return;
    _menuOpen = true;
    await showDialog<void>(
      // The chrome's own Navigator, directly above. This briefly went through
      // rootNavigatorKey and silently did NOTHING whenever the key had no
      // context — a right-click that opened no menu and reported no error.
      context: context,
      barrierColor: const Color(0xB8000000),
      builder: (_) => const HostControlsDialog(),
    );
    if (mounted) _menuOpen = false;
  }

  int _openedRevision = -1;
  bool _ready = false;
  Object? _error;
  bool _usesCacheProxy = false;

  @override
  void initState() {
    super.initState();
    _autoHide = AnalogAutoHideController()..addListener(_onAutoHide);
    // A floating tile has no chrome to hide, and an auto-hide clock ticking
    // behind one is a timer that never settles.
    _autoHide.hold(_kFloatingHold);
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      windowManager.addListener(this);
    }
    // A title can already be set before the first build (a resumed party, a
    // deep link), so react on mount as well as on change.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncOpen(ref.read(nowPlayingProvider)),
    );
  }

  Future<void> _syncOpen(NowPlaying now) async {
    if (!now.isOpen) {
      unawaited(_exitFullscreen());
      return;
    }
    if (now.revision == _openedRevision) return;
    final itemId = now.itemId!;
    final revision = now.revision;
    _openedRevision = revision;
    setState(() {
      _ready = false;
      _error = null;
    });

    final controller = ref.read(playerControllerProvider);
    _playingSubscription ??= controller.playing.listen(_autoHide.setPlaying);
    _autoHide.setPlaying(controller.isPlayingNow);
    final result = await ref
        .read(playbackOperationsProvider)
        .replace(
          (isSuperseded) => openTitleIntoPlayer(
            ref,
            controller,
            itemId: itemId,
            mediaSourceId: now.mediaSourceId,
            audioStreamIndex: now.audioStreamIndex,
            subtitleStreamIndex: now.subtitleStreamIndex,
            isStale: () =>
                isSuperseded() ||
                !mounted ||
                ref.read(nowPlayingProvider).revision != revision,
          ),
        );
    if (!mounted ||
        result == null ||
        ref.read(nowPlayingProvider).revision != revision) {
      return;
    }
    setState(() {
      _ready = result.ok;
      _error = result.error;
      _usesCacheProxy = result.usesCacheProxy;
    });
  }

  void _onAutoHide() {
    if (!mounted) return;
    setState(() {});
    // Published from the listener, never from build — writing a provider during
    // a build throws. Everything else mounted at the root reads this to fade
    // out with the player's own chrome instead of sitting over it.
    ref.read(playerChromeVisibleProvider.notifier).state = _autoHide.visible;
  }

  void _syncChromeHold(NowPlaying now) {
    if (now.isExpanded) {
      _autoHide.release(_kFloatingHold);
    } else {
      _autoHide.hold(_kFloatingHold);
    }
  }

  // Push-to-talk (hold T): momentarily opens the mic, returning to muted on
  // release. No-op if the user has manually unmuted; the hold guard suppresses
  // key-repeat. Wired through livekit only — never authors playback commands.
  void _pttStart() {
    if (_pttHolding) return;
    if (ref.read(livekitProvider).micEnabled) return;
    _pttHolding = true;
    ref.read(livekitProvider.notifier).setMic(true);
  }

  void _pttStop() {
    if (!_pttHolding) return;
    _pttHolding = false;
    ref.read(livekitProvider.notifier).setMic(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playingSubscription?.cancel();
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      windowManager.removeListener(this);
    }
    _autoHide
      ..removeListener(_onAutoHide)
      ..dispose();
    // Never leave the OS window stuck in fullscreen after the film goes away.
    if (_isFullscreen) unawaited(_exitFullscreen());
    super.dispose();
  }

  void _retry() {
    _openedRevision = -1;
    _syncOpen(ref.read(nowPlayingProvider));
  }

  @override
  Future<bool> didPopRoute() async {
    if (!ref.read(nowPlayingProvider).isExpanded) return false;
    await _exitFullscreen();
    ref.read(nowPlayingProvider.notifier).minimise();
    return true;
  }

  /// Top-left of the floating tile, in stage coordinates. Null until the first
  /// layout, which is when a cascade anchor can actually be computed.
  Offset? _offset;
  double _width = _defaultFloatingWidth;

  Size _stageOf(BoxConstraints constraints) =>
      Size(constraints.maxWidth, constraints.maxHeight);

  Rect _floatingRect(Size stage) {
    final width = FloatingTileGeometry.clampWidth(
      _width,
      stage,
      aspect: _playerAspect,
    );
    final size = FloatingTileGeometry.tileSize(
      width,
      collapsed: false,
      aspect: _playerAspect,
    );
    final offset = FloatingTileGeometry.clamp(
      _offset ??
          Offset(
            stage.width - size.width - FloatingTileGeometry.margin,
            FloatingTileGeometry.margin,
          ),
      size,
      stage,
    );
    return offset & size;
  }

  void _drag(DragUpdateDetails details, Size stage, Rect rect) {
    setState(() {
      _offset = FloatingTileGeometry.clamp(
        (_offset ?? rect.topLeft) + details.delta,
        rect.size,
        stage,
      );
    });
  }

  void _resize(DragUpdateDetails details, Size stage) {
    setState(() {
      _width = FloatingTileGeometry.clampWidth(
        _width + details.delta.dx,
        stage,
        aspect: _playerAspect,
      );
    });
  }

  void _dragEnd(Size stage, Size tile) {
    setState(() {
      _offset = FloatingTileGeometry.snapToNearestCorner(
        FloatingTileGeometry.clamp(_offset ?? Offset.zero, tile, stage),
        tile,
        stage,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowPlayingProvider);
    final notifier = ref.read(nowPlayingProvider.notifier);
    // Party context, when there is one. The player is the same player either
    // way — a room only changes who may drive it and where seeks are authored.
    final party = ref.watch(partyProvider);
    ref.listen<NowPlaying>(nowPlayingProvider, (_, next) {
      _syncOpen(next);
      _syncChromeHold(next);
    });

    return Stack(
      children: [
        if (now.isOpen)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stage = _stageOf(constraints);
                final rect = now.isExpanded
                    ? Offset.zero & stage
                    : _floatingRect(stage);

                return Stack(
                  children: [
                    // A scrim only while expanded, so the app underneath is not
                    // showing through a full-bleed video. The floating tile
                    // deliberately has none: you are meant to keep using the
                    // app around it.
                    if (now.isExpanded)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(color: Colors.black),
                        ),
                      ),
                    // Right-click / long-press over the picture opens the
                    // Watch Party menu, exactly as it did on the route. Shift
                    // is left alone so any native context menu survives.
                    // Wrapped OUTSIDE the frame so the whole picture answers,
                    // not just the chrome.
                    AnimatedPositioned(
                      duration: AppMotion.snap,
                      curve: AppMotion.emphasized,
                      left: rect.left,
                      top: rect.top,
                      width: rect.width,
                      height: rect.height,
                      child: _PartyMenuGesture(
                        enabled: party != null,
                        onOpen: _openPartyMenu,
                        child: _PlayerFrame(
                          expanded: now.isExpanded,
                          // Only in a room: solo playback has no timeline to be
                          // behind, so the correction loop never runs and the
                          // badge would be permanently dead weight.
                          canClose: true,
                          onMinimise: () {
                            unawaited(_exitFullscreen());
                            notifier.minimise();
                          },
                          onExpand: notifier.expand,
                          onClose: () {
                            unawaited(_exitFullscreen());
                            unawaited(notifier.close());
                          },
                          onDrag: (details) => _drag(details, stage, rect),
                          onDragEnd: () => _dragEnd(stage, rect.size),
                          onResize: (details) => _resize(details, stage),
                          // Playback reports its own load/failure here because
                          // the route that used to show them is gone.
                          error: _error,
                          loading: !_ready && _error == null,
                          onRetry: _retry,
                          child: PlayerView(
                            controller: ref.watch(playerControllerProvider),
                            itemId: now.itemId,
                            mediaSourceId: now.mediaSourceId,
                            title: now.title,
                            apiClient: ref.watch(apiClientProvider),
                            preferredSubtitleStreamIndex:
                                now.subtitleStreamIndex,
                            cachedSpans: _usesCacheProxy && now.itemId != null
                                ? ref
                                      .watch(mediaCacheProxyProvider)
                                      .cachedSpansFor(now.itemId!)
                                : null,
                            onBack: notifier.minimise,
                            onToggleFullscreen: _toggleFullscreen,
                            isFullscreen: _isFullscreen,
                            canControl: true,
                            onPushToTalkStart: party != null ? _pttStart : null,
                            onPushToTalkStop: party != null ? _pttStop : null,
                            chatOpen: ref.watch(chatDrawerOpenProvider),
                            chatToasts: party != null
                                ? [
                                    for (final message in ref.watch(
                                      chatProvider,
                                    ))
                                      ToastMessage(
                                        id:
                                            '${message.userId}:${message.timestamp}:'
                                            '${message.text.hashCode}',
                                        sender: message.name,
                                        preview: message.text,
                                        // Restamped by the chrome on its own
                                        // clock; the server timestamp only feeds
                                        // the id.
                                        receivedAtMs: message.timestamp,
                                      ),
                                  ]
                                : const [],
                            onToggleChat: party != null
                                ? () =>
                                      ref
                                          .read(chatDrawerOpenProvider.notifier)
                                          .state = !ref.read(
                                        chatDrawerOpenProvider,
                                      )
                                : null,
                            // Unified chrome visibility: one clock for the
                            // transport bar and everything floating over it.
                            visible: now.isExpanded ? _autoHide.visible : false,
                            onWake: () =>
                                _autoHide.noteInput(PlayerInputKind.pointer),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The chrome around the video: escape-to-minimise while expanded, and a drag
/// header plus expand/close buttons while floating.
class _PlayerFrame extends StatelessWidget {
  const _PlayerFrame({
    required this.expanded,
    this.canClose = true,
    this.error,
    this.loading = false,
    required this.onRetry,
    required this.onMinimise,
    required this.onExpand,
    required this.onClose,
    required this.onDrag,
    required this.onDragEnd,
    required this.onResize,
    required this.child,
  });

  final bool expanded;
  final bool canClose;
  final Object? error;
  final bool loading;
  final VoidCallback onRetry;
  final VoidCallback onMinimise;
  final VoidCallback onExpand;
  final VoidCallback onClose;
  final ValueChanged<DragUpdateDetails> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<DragUpdateDetails> onResize;
  final Widget child;

  /// The video, or the reason there isn't one. Kept in ONE place so the
  /// expanded and floating branches below cannot disagree about it.
  Widget _body() {
    final errorMessage = error is ApiException
        ? (error! as ApiException).message
        : 'Could not open this title. Check your connection and try again.';
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (error != null)
          Center(
            child: expanded
                ? ErrorState(
                    title: 'Playback failed',
                    message: errorMessage,
                    onRetry: onRetry,
                  )
                : Tooltip(
                    message: errorMessage,
                    child: TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry playback'),
                    ),
                  ),
          )
        else if (loading)
          const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.text,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      elevation: expanded ? 0 : 12,
      borderRadius: BorderRadius.circular(expanded ? 0 : 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: expanded ? 0 : FloatingTileGeometry.headerHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: onDrag,
              onPanEnd: (_) => onDragEnd(),
              child: Row(
                children: [
                  const Spacer(),
                  _FrameButton(
                    icon: Icons.open_in_full,
                    tooltip: 'Back to full screen',
                    onPressed: onExpand,
                  ),
                  if (canClose)
                    _FrameButton(
                      icon: Icons.close,
                      tooltip: 'Stop watching',
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: expanded
                  ? {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          onMinimise,
                    }
                  : const {},
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: expanded ? null : onExpand,
                      onPanUpdate: expanded ? null : onDrag,
                      onPanEnd: expanded ? null : (_) => onDragEnd(),
                      child: AbsorbPointer(
                        absorbing: !expanded,
                        child: _body(),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: expanded,
                      child: AnimatedOpacity(
                        opacity: expanded ? 0 : 1,
                        duration: AppMotion.hover,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeUpLeftDownRight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: onResize,
                            child: const SizedBox(
                              width: 18,
                              height: 18,
                              child: Icon(
                                Icons.drag_handle,
                                size: 11,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameButton extends StatelessWidget {
  const _FrameButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(
        width: FloatingTileGeometry.headerHeight,
        height: FloatingTileGeometry.headerHeight,
        child: Icon(icon, size: 14, color: Colors.white70),
      ),
    ),
  );
}

/// Right-click / long-press over the picture opens the Watch Party menu.
///
/// Only while a room exists — outside one there is no menu to open, and a
/// right-click that swallows itself and does nothing is worse than one that
/// falls through.
class _PartyMenuGesture extends StatelessWidget {
  const _PartyMenuGesture({
    required this.enabled,
    required this.onOpen,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Listener(
      onPointerDown: (event) {
        if (event.buttons != kSecondaryButton) return;
        // Shift+right-click is left alone so any native context menu survives.
        if (HardwareKeyboard.instance.isShiftPressed) return;
        onOpen();
      },
      child: GestureDetector(
        // Trackpad / touch fallback for the same menu.
        behavior: HitTestBehavior.deferToChild,
        onLongPress: onOpen,
        child: child,
      ),
    );
  }
}
