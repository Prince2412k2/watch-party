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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analog/player/auto_hide_controller.dart';
import '../analog/player_core.dart';
import '../state/state.dart';
import '../data/api_client.dart';
import '../ui/ui.dart';
import '../ui/widgets/catch_up_badge.dart';
import '../ui/widgets/floating_camera_tile.dart';
import 'open_title.dart';
import 'player_view.dart';

/// Movies are 16:9, unlike the 4:3 camera tiles the geometry was written for.
const double _playerAspect = 16 / 9;

/// Starting width of the floating tile — wider than a camera, because a movie
/// at camera size is unreadable rather than merely small.
const double _defaultFloatingWidth = 300;

class PlayerHost extends ConsumerStatefulWidget {
  const PlayerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlayerHost> createState() => _PlayerHostState();
}

class _PlayerHostState extends ConsumerState<PlayerHost> {
  /// A GlobalKey, not a ValueKey, and that distinction is the whole file.
  ///
  /// Expanded and floating are genuinely different subtrees — one is a bare
  /// focus scope, the other a Material card with a drag header. A ValueKey only
  /// matches within a parent's child list, so switching modes REBUILT the
  /// player, re-attached the video texture and reloaded the media. A GlobalKey
  /// reparents the existing element instead, which is what keeps playback
  /// running across the transition.
  final GlobalKey _playerKey = GlobalKey(debugLabel: 'app-player');

  /// Chrome auto-hide, moved here from PartyScreen. It has to live with the
  /// player, not with a route, for the same reason the player does.
  late final AnalogAutoHideController _autoHide;
  static const String _kFloatingHold = 'floating';
  bool _pttHolding = false;

  /// The title this host has opened, so a rebuild does not re-open it. Party
  /// titles are never recorded here: PartyNotifier owns those opens.
  String? _openedItemId;
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
    // A title can already be set before the first build (a resumed party, a
    // deep link), so react on mount as well as on change.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncOpen(ref.read(nowPlayingProvider)),
    );
  }

  /// Open a SOLO title when one appears. Party media is opened by
  /// [PartyNotifier], behind its own generation-guarded queue — opening it here
  /// too would be the double-open that queue exists to prevent.
  Future<void> _syncOpen(NowPlaying now) async {
    if (!now.isOpen || now.fromParty) {
      _openedItemId = null;
      return;
    }
    if (now.itemId == _openedItemId) return;
    final itemId = now.itemId!;
    _openedItemId = itemId;
    setState(() {
      _ready = false;
      _error = null;
    });

    final result = await openTitleIntoPlayer(
      ref,
      ref.read(playerControllerProvider),
      itemId: itemId,
      mediaSourceId: now.mediaSourceId,
      audioStreamIndex: now.audioStreamIndex,
      subtitleStreamIndex: now.subtitleStreamIndex,
      // Stale the moment something else claims the player, so an open that
      // lands late does not start a title nobody is watching.
      isStale: () =>
          !mounted || ref.read(nowPlayingProvider).itemId != itemId,
    );
    if (!mounted) return;
    setState(() {
      _ready = result.ok;
      _error = result.error;
      _usesCacheProxy = result.usesCacheProxy;
    });
  }

  void _onAutoHide() {
    if (mounted) setState(() {});
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
    _autoHide
      ..removeListener(_onAutoHide)
      ..dispose();
    super.dispose();
  }

  void _retry() {
    _openedItemId = null;
    _syncOpen(ref.read(nowPlayingProvider));
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
      _offset ?? FloatingTileGeometry.cascadeAnchor(0, size, stage),
      size,
      stage,
    );
    return offset & size;
  }

  void _drag(DragUpdateDetails details, Size stage, Size tile) {
    setState(() {
      _offset = FloatingTileGeometry.clamp(
        (_offset ?? Offset.zero) + details.delta,
        tile,
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
      _offset = FloatingTileGeometry.snapToEdges(
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
    final partyNotifier = ref.read(partyProvider.notifier);
    final inParty = party != null && now.fromParty;
    ref.listen<NowPlaying>(nowPlayingProvider, (_, next) {
      _syncOpen(next);
      _syncChromeHold(next);
    });

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
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
                    AnimatedPositioned(
                      // The same snap the camera tiles use: a movie tile and
                      // a person tile should move alike.
                      duration: AppMotion.snap,
                      curve: AppMotion.emphasized,
                      left: rect.left,
                      top: rect.top,
                      width: rect.width,
                      height: rect.height,
                      child: _PlayerFrame(
                        expanded: now.isExpanded,
                        // Only in a room: solo playback has no timeline to be
                        // behind, so the correction loop never runs and the
                        // badge would be permanently dead weight.
                        showCatchUp: inParty,
                        // No close button on the room's film.
                        //
                        // Closing it locally paused the controller and unmounted
                        // the surface — and then the sync engine, which is still
                        // attached and still following the room's schedule,
                        // pressed play again on the next tick. The result was a
                        // film you could hear but not see, with no way to stop
                        // it except leaving the party from outside the player.
                        //
                        // The room's film is the room's. You can push it down to
                        // a tile, and you can leave or end the room from the
                        // popcorn — which now sits above the player, so it is
                        // reachable without going anywhere. What you cannot do
                        // is silently desync yourself from the thing everybody
                        // else is watching.
                        canClose: !inParty,
                        onMinimise: notifier.minimise,
                        onExpand: notifier.expand,
                        onClose: () => notifier.close(),
                        onDrag: (details) =>
                            _drag(details, stage, rect.size),
                        onDragEnd: () => _dragEnd(stage, rect.size),
                        onResize: (details) => _resize(details, stage),
                        // Solo playback reports its own load/failure here,
                        // because the route that used to show them is gone.
                        // Party playback has no such state: the sync engine
                        // reports through the party chrome instead.
                        error: now.fromParty ? null : _error,
                        loading: !now.fromParty && !_ready && _error == null,
                        onRetry: _retry,
                        child: PlayerView(
                          key: _playerKey,
                          controller: ref.watch(playerControllerProvider),
                          itemId: now.itemId,
                          mediaSourceId: now.mediaSourceId,
                          title: now.title,
                          apiClient: ref.watch(apiClientProvider),
                          preferredSubtitleStreamIndex:
                              now.subtitleStreamIndex,
                          // Party media is always routed through the cache
                          // proxy, so the "downloaded" indicator is available
                          // there without the solo path's flag.
                          cachedSpans:
                              (inParty || _usesCacheProxy) && now.itemId != null
                              ? ref
                                    .watch(mediaCacheProxyProvider)
                                    .cachedSpansFor(now.itemId!)
                              : null,
                          onBack: notifier.minimise,
                          // ── party ─────────────────────────────────────────
                          // A guest may watch without driving. Outside a room
                          // you always drive yourself.
                          canControl: !inParty || partyNotifier.canControl,
                          canManagePartyMedia: !inParty || partyNotifier.isHost,
                          partyPlayback: inParty ? partyNotifier.playback : null,
                          subtitlePreferences: inParty
                              ? partyNotifier.subtitlePreferences
                              : null,
                          onSetPlaybackTracks: inParty
                              ? (audio, subtitle) =>
                                    partyNotifier.setPlaybackTracks(
                                      audioStreamIndex: audio,
                                      subtitleStreamIndex: subtitle,
                                    )
                              : null,
                          onSetSubtitlePreferences: inParty
                              ? partyNotifier.setSubtitlePreferences
                              : null,
                          // A driver's scrub is authored to the sync engine so
                          // it reaches the server and every other client; solo
                          // playback just seeks itself.
                          onSeek: inParty
                              ? (pos) =>
                                    ref.read(syncEngineProvider).requestSeek(pos)
                              : null,
                          onPushToTalkStart: inParty ? _pttStart : null,
                          onPushToTalkStop: inParty ? _pttStop : null,
                          chatOpen: ref.watch(chatDrawerOpenProvider),
                          chatToasts: inParty
                              ? [
                                  for (final message in ref.watch(chatProvider))
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
                          onToggleChat: inParty
                              ? () =>
                                    ref
                                            .read(
                                              chatDrawerOpenProvider.notifier,
                                            )
                                            .state =
                                        !ref.read(chatDrawerOpenProvider)
                              : null,
                          // Unified chrome visibility: one clock for the
                          // transport bar and everything floating over it.
                          visible: now.isExpanded ? _autoHide.visible : false,
                          onWake: () =>
                              _autoHide.noteInput(PlayerInputKind.pointer),
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
    this.showCatchUp = false,
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
  final bool showCatchUp;
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
    if (error != null) {
      return Center(
        child: ErrorState(
          title: 'Playback failed',
          message: error is ApiException
              ? (error! as ApiException).message
              : 'Could not open this title. Check your connection and try again.',
          onRetry: onRetry,
        ),
      );
    }
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.text,
          ),
        ),
      );
    }
    return child;
  }

  /// The video with the catch-up badge over it. Top-left, clear of the
  /// transport bar, and NOT tied to the auto-hide chrome: it reports something
  /// happening to your playback right now, so it is a notification rather than
  /// a control, and hiding it three seconds in would defeat the point.
  Widget _stage() {
    if (!showCatchUp) return _body();
    return Stack(
      children: [
        Positioned.fill(child: _body()),
        Positioned(
          top: expanded ? 18 : 8,
          left: expanded ? 18 : 8,
          child: const CatchUpBadge(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      // Escape minimises rather than closing. Back does the same thing through
      // the router's PopScope — both routes to "I am done looking at this"
      // land on the same behaviour, and neither stops playback.
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onMinimise,
        },
        child: Focus(autofocus: true, child: _stage()),
      );
    }

    return Material(
      color: Colors.black,
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: FloatingTileGeometry.headerHeight,
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
          // Tapping the video itself expands: the same gesture every phone
          // video app uses, and cheaper than aiming at a 26px header button.
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onExpand,
                    child: AbsorbPointer(child: _stage()),
                  ),
                ),
                // Bottom-right resize, matching the camera tiles' handle.
                Positioned(
                  right: 0,
                  bottom: 0,
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
              ],
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
