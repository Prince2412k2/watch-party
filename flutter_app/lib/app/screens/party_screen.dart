import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:window_manager/window_manager.dart';

import '../../analog/chrome/chrome.dart';
import '../../analog/player/auto_hide_controller.dart';
import '../../analog/player_core.dart';
import '../../models/models.dart';
import '../../player/player_view.dart';
import '../../state/state.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/floating_camera_tile.dart';

/// The watch-party screen — an IMMERSIVE, full-bleed layout mirroring the web
/// app (`pages/Party.tsx`). The movie fills the window; camera tiles float over
/// it as draggable PiP windows (or dock into a left column); chat is a
/// right-side slide-over; the room-essential A/V toggles live in a flat,
/// boxless top-right cluster; a top-left red Back MINIMIZES to the shell (it
/// never ends/leaves — the party stays alive behind the popcorn); and the
/// Watch Party menu (roster, transfer/kick, collaborative, sync-mode, share,
/// back-to-lobby, end) opens on right-click (or a long-press fallback) — no
/// persistent desktop party pill over the player.
///
/// Creation and join-by-code live in the shell popcorn ([PopcornControl]); this
/// route is entered with a party id, so its pre-join surface is only the
/// connecting / sonar waiting-room / "party not found" states.
class PartyScreen extends ConsumerStatefulWidget {
  const PartyScreen({super.key, this.partyId});
  final String? partyId;

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen> {
  bool _busy = false;
  bool _waiting = false;
  String? _error;
  bool _autoJoinAttempted = false;

  @override
  void initState() {
    super.initState();
    final id = widget.partyId;
    if (id == null || id.isEmpty) return;
    // Being on this route IS the un-minimized state: clear the latch so the
    // shell resumes auto-opening this party after the next lobby round trip.
    // Deferred a frame — Riverpod refuses provider writes from a life-cycle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(partyMinimizedProvider.notifier).restore();
    });
    // Already in this party (created/joined via the popcorn widget, or minimized
    // then re-opened) — render the live session WITHOUT re-emitting party:join,
    // so the socket / LiveKit / sync engine are never torn down and re-set up.
    if (ref.read(partyProvider)?.id == id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _join(id));
  }

  Future<void> _join(String partyId) async {
    if (_autoJoinAttempted) return;
    _autoJoinAttempted = true;
    setState(() {
      _busy = true;
      _error = null;
      _waiting = false;
    });
    try {
      final status = await ref.read(partyProvider.notifier).join(partyId);
      if (!mounted) return;
      setState(() => _waiting = status == 'waiting');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaving the waiting room cancels the pending request (tears down the
  /// socket) and returns to the shell.
  Future<void> _leaveWaiting() async {
    await ref.read(partyProvider.notifier).leave();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(partyProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: party == null
          ? SafeArea(
              child: _PartyEntry(
                waiting: _waiting,
                busy: _busy,
                error: _error,
                onLeave: _leaveWaiting,
                onBackHome: () => context.go('/home'),
              ),
            )
          // The immersive stage is intentionally NOT wrapped in SafeArea — it is
          // full-bleed like the web's fixed stage; individual overlays inset
          // themselves off the edges.
          : const _ImmersiveParty(),
    );
  }
}

/// Pre-join entry: "party not found" on a join error, the sonar waiting-room
/// while awaiting host approval, otherwise a quiet connecting spinner. Mirrors
/// the web `Party.tsx` state machine (joinError → `Lobby` waiting → connecting).
class _PartyEntry extends StatelessWidget {
  const _PartyEntry({
    required this.waiting,
    required this.busy,
    required this.error,
    required this.onLeave,
    required this.onBackHome,
  });

  final bool waiting;
  final bool busy;
  final String? error;
  final VoidCallback onLeave;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return _PartyNotFound(message: error!, onBack: onBackHome);
    }
    if (waiting) return _WaitingRoom(onLeave: onLeave);
    return const _Connecting();
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();

  @override
  Widget build(BuildContext context) {
    return const Center(
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
          SizedBox(height: AppSpacing.lg),
          Text(
            'Connecting…',
            style: TextStyle(color: AppColors.dim, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _PartyNotFound extends StatelessWidget {
  const _PartyNotFound({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Reveal(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off, color: AppColors.faint, size: 40),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Party not found',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.dim,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Back',
                  variant: AppButtonVariant.secondary,
                  onPressed: onBack,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Approval-pending guest stage: no room metadata or explanatory chrome, only
/// the branded motion and an explicit way to cancel the pending join.
class _WaitingRoom extends StatelessWidget {
  const _WaitingRoom({required this.onLeave});
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Center(
          child: WatchPartyAnimation(
            key: Key('guestWaitingAnimation'),
            size: 300,
          ),
        ),
        Positioned(
          top: 12,
          left: 12 + desktopLeadingControlInset,
          child: IconButton(
            key: const Key('leaveWaitingPartyButton'),
            tooltip: 'Leave watch party',
            onPressed: onLeave,
            style: IconButton.styleFrom(
              fixedSize: const Size(44, 44),
              foregroundColor: AppColors.text,
              backgroundColor: const Color(0x9917181B),
              side: const BorderSide(color: AppColors.line2),
            ),
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
        ),
      ],
    );
  }
}

/// The immersive in-party stage. A full-bleed [Stack] whose layers mirror the
/// web's z-order (`watchLayers.ts`):
///   0  the stage — [PlayerView] when watching, a lobby card otherwise (shrinks
///      via an animated left margin when the cameras dock — the player is never
///      re-keyed/remounted across the switch)
///   1  cameras — floating PiP tiles ([FloatingCameraLayer]) or a docked column
///   2  auto-hiding chrome — top-left Back + top-right A/V cluster
///   3  host-only join requests (a notification: always visible)
///   4  LiveKit error banner (always visible)
///   5  chat side rail
/// The Watch Party menu opens above everything via right-click / long-press.
class _ImmersiveParty extends ConsumerStatefulWidget {
  const _ImmersiveParty();

  @override
  ConsumerState<_ImmersiveParty> createState() => _ImmersivePartyState();
}

class _ImmersivePartyState extends ConsumerState<_ImmersiveParty> {
  bool _chatOpen = false;
  bool _isFullscreen = false;

  /// Camera layout: false = floating PiP tiles, true = docked left column.
  bool _dock = false;

  /// Whether the camera tiles are docked into the left column rather than
  /// floating over the picture.
  ///
  /// Opening chat SUPPRESSES the dock. Chat used to force it, on the reasoning
  /// that floating tiles anchored to the stage's right edge would end up under
  /// the drawer — but forcing a left column at the same moment a right drawer
  /// slides in rearranges the entire screen around a message, which is exactly
  /// the distraction the drawer is meant to avoid. The tiles keep clear of the
  /// drawer by insetting their layer instead (see [_kChatWidth]), which moves
  /// nothing but them.
  ///
  /// The explicit toggle is remembered across a chat session: dock, open chat,
  /// close it, and the cameras are docked again.
  bool _camerasDocked(bool watching) => watching && _dock && !_chatOpen;

  /// The chat drawer's width. It overlays the stage rather than narrowing it,
  /// so this is only ever an inset for things that must stay clear of it.
  static const double _kChatWidth = 360;

  /// Single-open guard for the right-click / long-press Watch Party menu.
  bool _menuOpen = false;

  /// Push-to-talk hold guard (mirrors `usePushToTalk`): distinguishes a
  /// PTT-driven unmute from a manual one and guards key-repeat.
  bool _pttHolding = false;

  /// The party's SINGLE chrome auto-hide clock, covering the player, the shared
  /// browser and the top-right A/V cluster together. Same
  /// `analog/player_core.dart` machine the solo player runs — the two used to
  /// be separate hand-written timers.
  late final AnalogAutoHideController _autoHide;

  @override
  void initState() {
    super.initState();
    _autoHide = AnalogAutoHideController()
      ..addListener(_onAutoHide)
      // The lobby has nothing to un-clutter, so the chrome is pinned there
      // until the party reaches an immersive stage.
      ..hold(_kLobbyHold);
  }

  void _onAutoHide() {
    if (mounted) setState(() {});
  }

  /// Chat pins the chrome open while it is on screen (`!_chatOpen` used to be
  /// checked inside the timer callback), and the non-immersive stages pin it
  /// permanently.
  static const String _kChatHold = 'chat';
  static const String _kLobbyHold = 'lobby';

  @override
  void dispose() {
    _autoHide
      ..removeListener(_onAutoHide)
      ..dispose();
    // Don't leave the OS window stuck in fullscreen after navigating away. This
    // is purely a window-chrome toggle — it never touches party/LiveKit state.
    if (_isFullscreen) {
      unawaited(windowManager.setFullScreen(false));
    }
    // Never leave the mic stuck open if PTT was mid-hold when the screen tore
    // down (mirrors usePushToTalk's unmount cleanup).
    if (_pttHolding) {
      unawaited(ref.read(livekitProvider.notifier).setMic(false));
    }
    super.dispose();
  }

  /// Toggles OS-level window fullscreen for the movie. The LiveKit room/camera
  /// tiles and the party socket are entirely unaffected — this only asks
  /// `window_manager` to resize the window and flips local UI state.
  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _isFullscreen = next);
  }

  /// Wake the chrome and re-arm the SINGLE idle hide.
  ///
  /// [immersive] is true for the player and the shared browser — the two stages
  /// where chrome sits over content someone is looking at. The lobby keeps it
  /// up, now as a named hold rather than a timer that is simply never armed.
  void _poke({required bool immersive, PlayerInputKind? kind}) {
    if (immersive) {
      _autoHide.release(_kLobbyHold);
    } else {
      _autoHide.hold(_kLobbyHold);
    }
    _autoHide.noteInput(kind ?? PlayerInputKind.pointer);
  }

  void _setChatOpen(bool open) {
    setState(() => _chatOpen = open);
    if (open) {
      _autoHide.hold(_kChatHold);
    } else {
      _autoHide.release(_kChatHold);
    }
  }

  // Push-to-talk (hold T): momentarily opens the mic, returning to muted on
  // release. No-op if the user has manually unmuted; the hold guard suppresses
  // key-repeat. Wired through livekit only — never authors playback commands.
  void _pttStart() {
    if (_pttHolding) return;
    if (ref.read(livekitProvider).micEnabled) {
      return; // manually unmuted → no-op
    }
    _pttHolding = true;
    ref.read(livekitProvider.notifier).setMic(true);
  }

  void _pttStop() {
    if (!_pttHolding) return;
    _pttHolding = false;
    ref.read(livekitProvider.notifier).setMic(false);
  }

  Future<void> _openWatchPartyMenu() async {
    if (_menuOpen) return;
    _menuOpen = true;
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xB8000000),
      builder: (_) => const _HostControlsDialog(),
    );
    if (mounted) _menuOpen = false;
  }

  // Right-click opens the Watch Party menu; Shift+right-click is left alone so
  // any native context menu survives (mirrors the web contextmenu bypass — on
  // desktop Flutter there's no native menu to preserve, so this just no-ops).
  void _handleSecondary() {
    if (HardwareKeyboard.instance.isShiftPressed) return;
    _openWatchPartyMenu();
  }

  // Back MINIMIZES to the shell — it never leaves/ends the party, so the
  // socket / LiveKit / sync engine stay alive, playback keeps tracking the
  // shared schedule, and the popcorn shows the live room (with "Return to the
  // party"). End (host) lives in the Watch Party menu; leave lives in the
  // popcorn — Stop Movie (backToLobby) and Stop Stream (end) stay distinct.
  //
  // It used to do the opposite of what it says: a host's Back emitted
  // `party:backToLobby` (stopping the movie for the WHOLE room) and a guest's
  // Back left the party outright, tearing down its own socket. Neither is
  // recoverable, and both were presented as a plain back arrow.
  void _minimize() {
    final party = ref.read(partyProvider);
    // Latch the minimize so [AppShell]'s auto-open does not immediately send us
    // back here; re-entering `/party/:id` clears it again.
    if (party != null) {
      ref.read(partyMinimizedProvider.notifier).minimize(party.id);
    }
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(partyProvider)!;
    final controller = ref.watch(playerControllerProvider);
    final canControl = ref.read(partyProvider.notifier).canControl;
    final notifier = ref.read(partyProvider.notifier);
    final watching = party.stage == 'watching';
    // A party has exactly one current activity, and the shared browser is a
    // third one alongside the lobby and Jellyfin playback. It is a live stream:
    // no timeline, no sync engine, nothing to seek.
    final browsing = party.stage == 'browser';

    // ONE unified auto-hide flag: chrome + transport bar fade together. "Stays
    // shown while chat is open / in the lobby" is now a pair of HOLDS on the
    // shared controller rather than extra terms in this expression, so the rule
    // lives in player_core alongside the player's. The lobby hold is released
    // by the first _poke on an immersive stage, exactly as the old timer was
    // only armed by the first _poke there.
    final chromeShown = _autoHide.visible;

    final stage = browsing
        ? _SharedBrowserStage(
            onToggleFullscreen: _toggleFullscreen,
            isFullscreen: _isFullscreen,
          )
        : watching
        ? PlayerView(
            controller: controller,
            itemId: party.mediaItemId,
            mediaSourceId: party.mediaSourceId,
            apiClient: ref.watch(apiClientProvider),
            canControl: canControl,
            partyPlayback: notifier.playback,
            subtitlePreferences: notifier.subtitlePreferences,
            canManagePartyMedia: notifier.isHost,
            onSetPlaybackTracks: (audio, subtitle) =>
                notifier.setPlaybackTracks(
                  audioStreamIndex: audio,
                  subtitleStreamIndex: subtitle,
                ),
            onSetSubtitlePreferences: notifier.setSubtitlePreferences,
            // No title/onBack: the party player has no top bar (web parity) —
            // leave is the top-left Back and host controls are the right-click
            // menu.
            onToggleFullscreen: _toggleFullscreen,
            isFullscreen: _isFullscreen,
            // Author the host's scrubs to the sync engine → server → every
            // other client (web + Flutter).
            onSeek: (pos) => ref.read(syncEngineProvider).requestSeek(pos),
            // Party playback is always routed through MediaCacheProxy, so the
            // "downloaded" indicator is available here.
            cachedSpans: party.mediaItemId == null
                ? null
                : ref
                      .watch(mediaCacheProxyProvider)
                      .cachedSpansFor(party.mediaItemId!),
            // Unified chrome visibility + activity wake (single 3s timer lives
            // here) and the party key bindings (c = chat, hold-T = PTT).
            visible: chromeShown,
            onWake: () => _poke(immersive: true),
            onToggleChat: () => _setChatOpen(!_chatOpen),
            onPushToTalkStart: _pttStart,
            onPushToTalkStop: _pttStop,
            // Chat notifications over the player. The chrome owns the queue,
            // the three-deep stack and the four second lifetime (player_core);
            // this only supplies the log and whether the drawer is open.
            chatOpen: _chatOpen,
            chatToasts: [
              for (final message in ref.watch(chatProvider))
                ToastMessage(
                  id:
                      '${message.userId}:${message.timestamp}:'
                      '${message.text.hashCode}',
                  sender: message.name,
                  preview: message.text,
                  // Restamped by the chrome on its own clock; the server
                  // timestamp only feeds the id.
                  receivedAtMs: message.timestamp,
                ),
            ],
          )
        : _LobbyStage(party: party);

    return MouseRegion(
      onHover: (_) => _poke(immersive: watching || browsing),
      child: Listener(
        onPointerDown: (event) {
          _poke(immersive: watching || browsing);
          if (event.buttons == kSecondaryButton) _handleSecondary();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          // Trackpad / touch fallback for the right-click Watch Party menu.
          onLongPress: _openWatchPartyMenu,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 0 — the stage. Shrinks (animated left margin) when cameras dock,
              // WITHOUT re-keying/remounting PlayerView or its media_kit
              // VideoView — only the surrounding box narrows. Chat does NOT
              // appear here: it is an overlay, so the picture keeps its size
              // and its aspect when the drawer opens.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: _camerasDocked(watching) ? 210.0 : 0.0,
                top: 0,
                right: 0,
                bottom: 0,
                child: stage,
              ),

              // 1 — cameras: floating PiP layer, or the docked left column.
              // Exactly one child so the stage above keeps a stable Stack slot.
              //
              // The floating layer is the one thing the drawer does move: its
              // right edge insets by the drawer's width so a tile can neither
              // hide under chat nor straddle its border.
              if (_camerasDocked(watching))
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 210,
                  child: _CameraDock(),
                )
              else
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: _chatOpen ? _kChatWidth : 0.0,
                  child: const FloatingCameraLayer(),
                ),

              // 2 — auto-hiding chrome: top-left Back + top-right A/V cluster.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !chromeShown,
                  child: AnimatedOpacity(
                    opacity: chromeShown ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _WatchChrome(
                      watching: watching,
                      dock: _camerasDocked(watching),
                      chatOpen: _chatOpen,
                      onBack: _minimize,
                      onToggleChat: () => _setChatOpen(!_chatOpen),
                      onToggleLayout: () => setState(() => _dock = !_dock),
                    ),
                  ),
                ),
              ),

              // 2b — the device rail, on the left edge of the STAGE so it can
              // centre against the full height. Fades and stops taking input
              // with the rest of the chrome.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !chromeShown,
                  child: AnimatedOpacity(
                    opacity: chromeShown ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Center(
                      child: _DeviceRail(
                        watching: watching,
                        dock: _camerasDocked(watching),
                        onToggleLayout: () => setState(() => _dock = !_dock),
                      ),
                    ),
                  ),
                ),
              ),

              // 3 — host-only join requests (a notification: never faded).
              const Positioned(top: 64, right: 12, child: _JoinRequestsLayer()),

              // 4 — LiveKit error banner (always visible).
              const Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: _LiveKitErrorBanner(),
              ),

              // 5 — the chat drawer: a glass overlay ON the picture. It takes
              // no layout from anything else, so opening it never resizes the
              // video.
              _ChatSlideOver(
                open: _chatOpen,
                width: _kChatWidth,
                onClose: () => _setChatOpen(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The auto-hiding player chrome that sits over the video: a top-left red Back
/// (minimize) and the top-right room-essential A/V cluster (chat, mic, cam,
/// hide-self, and — while watching — the float/dock camera-layout toggle). Flat,
/// boxless, monochrome icon buttons (`Player.tsx` `IconBtn` / `TopBar`); NO
/// host-controls or leave pill here (that's the right-click menu / popcorn).
class _WatchChrome extends ConsumerWidget {
  const _WatchChrome({
    required this.watching,
    required this.dock,
    required this.chatOpen,
    required this.onBack,
    required this.onToggleChat,
    required this.onToggleLayout,
  });

  final bool watching;
  final bool dock;
  final bool chatOpen;
  final VoidCallback onBack;
  final VoidCallback onToggleChat;
  final VoidCallback onToggleLayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No LiveKit state here any more — the device controls that needed it live
    // in [_DeviceRail] now, which watches the provider itself. This strip is
    // navigation and chat, and watching livekitProvider from here would rebuild
    // the whole thing on every mic/camera change for nothing.
    return SafeArea(
      child: Padding(
        // macOS puts the traffic lights in the top-left of the content area, so
        // this row clears them by dropping BELOW the caption strip rather than
        // insetting into it — insetting left pushed Back into the middle of the
        // window, next to the lights instead of out of their way. Windows keeps
        // the trailing inset, since its caption controls are on the right.
        padding: EdgeInsets.only(
          left: 14,
          right: 14 + desktopTrailingControlInset,
          top: 10 + (Platform.isMacOS ? integratedDesktopChromeHeight : 0),
          bottom: 10,
        ),
        // Back on the left, chat on the right. Everything that controls
        // YOUR devices lives in a vertical rail down the left edge of the
        // STAGE ([_DeviceRail]) rather than here — this strip is only as tall
        // as a button, so it is the wrong place to centre anything against,
        // and the sketch puts the devices on the edge regardless.
        //
        // No shared-browser control in either: this chrome sits over the
        // player, and starting a browser is a "what shall we watch" decision
        // that lives in the popcorn ([PopcornControl]).
        child: Row(
          children: [
            _AvIconButton(
              key: const Key('minimizePartyButton'),
              icon: Icons.arrow_back,
              // Named for what it does. It is not a leave and not a stop: the
              // room keeps playing and the popcorn offers the way back.
              tooltip: 'Minimize — the party keeps going',
              scrim: true,
              onTap: onBack,
            ),
            const Spacer(),
            _AvIconButton(
              icon: Icons.chat_bubble_outline,
              tooltip: 'Chat',
              active: chatOpen,
              onTap: onToggleChat,
            ),
          ],
        ),
      ),
    );
  }
}

/// A flat, boxless, monochrome player-chrome icon button (`Player.tsx`
/// `IconBtn`): no box/border/fill; glyph rests at 62% near-white, brightens to
/// full near-white on hover / when [active], and is red when [danger].
///
/// [scrim] backs the glyph with a dark disc: a bare icon sitting over full-bleed
/// video is legible or invisible depending on the frame behind it, which is not
/// a coin-flip worth taking for the control that leaves the immersive stage.
class _AvIconButton extends StatefulWidget {
  const _AvIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.busy = false,
    this.scrim = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;
  final bool busy;
  final bool scrim;

  static const Color _rest = Color(0x9EF4F4F5); // rgba(244,244,245,.62)
  static const Color _bright = Color(0xFFF4F4F5);
  static const Color _danger = Color(0xFFE0655E);

  @override
  State<_AvIconButton> createState() => _AvIconButtonState();
}

class _AvIconButtonState extends State<_AvIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.danger
        ? _AvIconButton._danger
        : ((widget.active || _hover)
              ? _AvIconButton._bright
              : _AvIconButton._rest);

    final Widget glyph = widget.busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _AvIconButton._rest,
            ),
          )
        : Icon(widget.icon, size: 19, color: color);

    return AnalogTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.busy ? null : widget.onTap,
          child: widget.scrim
              ? Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x9917181B),
                    border: Border.all(color: AppColors.line2),
                  ),
                  child: Center(child: glyph),
                )
              : SizedBox(width: 34, height: 34, child: Center(child: glyph)),
        ),
      ),
    );
  }
}

/// Mic/camera toggle that shows a pending spinner while the (slow, native)
/// LiveKit publish future is in flight, and reads danger (red) while OFF —
/// matching the web `IconBtn danger={!micOn}`.
class _AvPendingToggle extends StatefulWidget {
  const _AvPendingToggle({
    required this.iconOn,
    required this.iconOff,
    required this.on,
    required this.tooltip,
    required this.onToggle,
  });

  final IconData iconOn;
  final IconData iconOff;
  final bool on;
  final String tooltip;
  final Future<void> Function() onToggle;

  @override
  State<_AvPendingToggle> createState() => _AvPendingToggleState();
}

class _AvPendingToggleState extends State<_AvPendingToggle> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onToggle();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AvIconButton(
      icon: widget.on ? widget.iconOn : widget.iconOff,
      tooltip: widget.tooltip,
      danger: !widget.on,
      busy: _busy,
      onTap: _run,
    );
  }
}

/// The docked camera column (`Dock.tsx`): a fixed left panel of camera tiles
/// beside the shrunk video. Reuses [CameraGrid]'s strip layout so the docked
/// and floating tiles render identically.
class _CameraDock extends StatelessWidget {
  const _CameraDock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 18, top: 76, right: 12, bottom: 108),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xF017181B),
          borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusLg)),
          border: Border.fromBorderSide(BorderSide(color: AppColors.line2)),
        ),
        child: CameraGrid(layout: CameraGridLayout.strip),
      ),
    );
  }
}

/// Host-only "wants to join" notification, kept visible independent of the
/// auto-hide chrome (a notification, per the design guide). Renders nothing for
/// guests or when no one is waiting.
class _JoinRequestsLayer extends ConsumerWidget {
  const _JoinRequestsLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider);
    final me = ref.watch(currentUserIdProvider);
    final isHost = party != null && me != null && party.hostId == me;
    final waiting = ref.watch(partyWaitingProvider);
    if (!isHost || waiting.isEmpty) return const SizedBox.shrink();
    return SafeArea(child: _JoinRequests(waiting: waiting));
  }
}

/// The LiveKit A/V error banner — opaque and always visible (a notification),
/// not tied to the auto-hide chrome.
class _LiveKitErrorBanner extends ConsumerWidget {
  const _LiveKitErrorBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(livekitProvider.select((s) => s.error));
    if (error == null) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: AnalogPanel(
                translucent: true,
                blur: AppBlur.overlay,
                lift: AnalogLift.over,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: AppColors.red,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        error,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lobby stage: shown before a title is selected. Distinct from the watching
/// stage (the movie), mirroring the web's lobby. Shows the room code + count and
/// a status line; cameras still float and chat still works on top of it.
class _LobbyStage extends ConsumerWidget {
  const _LobbyStage({required this.party});
  final PartyState party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = party.participants.length;
    final isHost = ref.read(partyProvider.notifier).isHost;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Reveal(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.weekend_outlined,
                  color: AppColors.faint,
                  size: 40,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'In the lobby',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  isHost
                      ? 'Pick a movie and everyone in the party watches it together, in sync.'
                      : 'Waiting for the host to pick something to watch.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.dim,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                if (isHost) ...[
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Choose a movie',
                    icon: Icons.movie_outlined,
                    variant: AppButtonVariant.primary,
                    onPressed: () => _openPicker(context, ref),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                _RoomCodePill(code: party.id, count: count),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, WidgetRef ref) =>
      pickAndSwitchPartyMedia(context, ref);
}

/// The shared-browser stage: a containerised Chromium published into the
/// party's LiveKit room, rendered here and — for the driver — driven from here.
///
/// Pointer, scroll and keyboard input are mapped from this window back to the
/// remote screen and sent over the party socket, which is also where the server
/// checks who is allowed to drive. Control is offered on desktop only: a touch
/// surface has no hover, no right click and no keyboard, so the mapping that
/// makes a click land where you aimed does not exist there.
class _SharedBrowserStage extends ConsumerStatefulWidget {
  const _SharedBrowserStage({
    required this.onToggleFullscreen,
    required this.isFullscreen,
  });

  final VoidCallback onToggleFullscreen;
  final bool isFullscreen;

  @override
  ConsumerState<_SharedBrowserStage> createState() =>
      _SharedBrowserStageState();
}

class _SharedBrowserStageState extends ConsumerState<_SharedBrowserStage> {
  final FocusNode _focus = FocusNode(debugLabel: 'sharedBrowser');
  final GlobalKey _videoKey = GlobalKey();
  DateTime _lastMove = DateTime.fromMillisecondsSinceEpoch(0);
  final TextEditingController _url = TextEditingController();

  /// The X button number of the press in progress.
  ///
  /// A pointer-up event reports `buttons == 0` — the buttons still held, which is
  /// none of them. Deriving the button from it would release button 1 after a
  /// right-click press of button 3, leaving button 3 stuck down on the remote
  /// screen and every later click behaving like a drag.
  int _activeButton = 1;

  /// Desktop only. `Platform.isAndroid || isIOS` would be the same test inverted,
  /// but naming the supported set means a new platform is view-only by default.
  static final bool _canDrive =
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void dispose() {
    _focus.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final browser = ref.watch(sharedBrowserProvider).browser;
    final screen = ref.watch(livekitProvider).screenShare;
    final isHost = ref.read(partyProvider.notifier).isHost;

    if (browser != null && browser.failed) {
      return _BrowserMessage(
        icon: Icons.error_outline,
        title: 'The shared browser stopped',
        body: browser.error ?? 'Something went wrong with the shared browser.',
        action: isHost
            ? AppButton(
                label: 'Back to the party',
                variant: AppButtonVariant.secondary,
                onPressed: () =>
                    ref.read(partyProvider.notifier).stopSharedBrowser(),
              )
            : null,
      );
    }

    // No track yet: either the container is still starting, or this client has
    // not been subscribed to the publication. Both look the same to a viewer and
    // both resolve on their own, so they get the same message.
    if (screen == null) {
      return const _BrowserMessage(
        icon: Icons.public,
        title: 'Starting the shared browser…',
        body: 'Everyone in the party will see the same page.',
        showSpinner: true,
      );
    }

    final myUserId = ref.read(currentUserIdProvider);
    // Deliberately NOT gated on the server having sent a screen size: an older
    // server made that null, which silently disabled driving with nothing on
    // screen to explain it. The geometry falls back to the container default.
    final driving =
        _canDrive &&
        myUserId != null &&
        browser != null &&
        browser.active &&
        browser.driverUserId == myUserId;

    final video = KeyedSubtree(
      key: _videoKey,
      // `fit` is left at VideoTrackRenderer's default (contain), which is what
      // this needs: the remote screen is a fixed 16:9 and distorting it to fill
      // the window would be worse than letterbox bars. The input mapping below
      // depends on it being contain, so this is load-bearing, not cosmetic.
      child: lk.VideoTrackRenderer(screen, key: ValueKey(screen.sid)),
    );

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The input wrappers are ALWAYS in the tree, enabled or not. Adding or
          // removing them when control changes hands would change the tree shape
          // above the renderer, which destroys and recreates the native
          // RTCVideoRenderer and its texture — a platform-thread init that freezes
          // the UI mid-session (the hazard camera_grid.dart documents). Gating the
          // handlers instead keeps one stable element.
          Focus(
            focusNode: _focus,
            autofocus: true,
            canRequestFocus: driving,
            onKeyEvent: driving ? _onKey : null,
            child: MouseRegion(
              cursor: driving ? SystemMouseCursors.precise : MouseCursor.defer,
              child: Listener(
                onPointerDown: driving
                    ? (event) {
                        _focus.requestFocus();
                        _activeButton = switch (event.buttons) {
                          kSecondaryButton => 3,
                          kMiddleMouseButton => 2,
                          _ => 1,
                        };
                        _send(
                          event.localPosition,
                          'down',
                          button: _activeButton,
                        );
                      }
                    : null,
                onPointerUp: driving
                    ? (event) => _send(
                        event.localPosition,
                        'up',
                        button: _activeButton,
                      )
                    : null,
                onPointerMove: driving
                    ? (event) => _move(event.localPosition)
                    : null,
                onPointerHover: driving
                    ? (event) => _move(event.localPosition)
                    : null,
                onPointerSignal: driving
                    ? (event) {
                        if (event is PointerScrollEvent) {
                          ref.read(partyProvider.notifier).sendBrowserInput({
                            'type': 'scroll',
                            'dy': event.scrollDelta.dy,
                          });
                        }
                      }
                    : null,
                child: video,
              ),
            ),
          ),

          // Driver toolbar. The stream carries Chromium's own tab strip and
          // address bar, so this is a convenience layer — typing a URL by
          // injecting keystrokes into the remote address bar is fiddly, and
          // back/forward as buttons beats remembering alt+Left.
          if (driving)
            Positioned(
              top: AppSpacing.md,
              left: 0,
              right: 0,
              child: Center(
                child: _BrowserToolbar(
                  url: _url,
                  onKey: _key,
                  onSubmitted: _focus.requestFocus,
                ),
              ),
            ),

          Positioned(
            left: AppSpacing.lg,
            bottom: AppSpacing.lg,
            right: AppSpacing.lg,
            child: _BrowserControlBar(
              browser: browser,
              isHost: isHost,
              driving: driving,
              canDrive: _canDrive,
              isFullscreen: widget.isFullscreen,
              onToggleFullscreen: widget.onToggleFullscreen,
            ),
          ),
        ],
      ),
    );
  }

  // ── input ──────────────────────────────────────────────────────────────────

  /// Where the image actually sits inside this widget, and how big it is.
  ///
  /// BoxFit.contain centres the image and letterboxes the remainder, so the
  /// image's box is NOT the widget's box. Assuming otherwise is what makes a
  /// click drift further off the further it is from the centre.
  ({double scale, Offset origin, int width, int height})? _geometry() {
    final browser = ref.read(sharedBrowserProvider).browser;
    if (browser == null) return null;
    final remoteWidth = browser.remoteWidth;
    final remoteHeight = browser.remoteHeight;
    final box = _videoKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final size = box.size;
    if (size.isEmpty) return null;
    final scale = math.min(
      size.width / remoteWidth,
      size.height / remoteHeight,
    );
    return (
      scale: scale,
      origin: Offset(
        (size.width - remoteWidth * scale) / 2,
        (size.height - remoteHeight * scale) / 2,
      ),
      width: remoteWidth,
      height: remoteHeight,
    );
  }

  /// [button] is already an X button number (1 left, 2 middle, 3 right).
  void _send(Offset local, String type, {int button = 1}) {
    final geometry = _geometry();
    if (geometry == null) return;
    final x = (local.dx - geometry.origin.dx) / geometry.scale;
    final y = (local.dy - geometry.origin.dy) / geometry.scale;
    // A press in the letterbox is not a press on the remote screen.
    if (x < 0 || y < 0 || x > geometry.width || y > geometry.height) return;
    ref.read(partyProvider.notifier).sendBrowserInput({
      'type': type,
      'x': x.round(),
      'y': y.round(),
      'button': button,
    });
  }

  void _move(Offset local) {
    // ~40/s. Above this, xdotool becomes the bottleneck on the far side and the
    // result reads as laggy input rather than as too many events.
    final now = DateTime.now();
    if (now.difference(_lastMove).inMilliseconds < 25) return;
    _lastMove = now;
    _send(local, 'move');
  }

  void _key(String combo) => ref.read(partyProvider.notifier).sendBrowserInput({
    'type': 'key',
    'key': combo,
  });

  /// Keys xdotool names differently from Flutter. Anything with a character and
  /// no modifier is sent as text instead, so layouts and dead keys behave.
  ///
  /// `final`, not `const`: LogicalKeyboardKey overrides == and hashCode, which a
  /// constant map key may not do.
  static final Map<LogicalKeyboardKey, String> _keyNames = {
    LogicalKeyboardKey.backspace: 'BackSpace',
    LogicalKeyboardKey.enter: 'Return',
    LogicalKeyboardKey.numpadEnter: 'Return',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.arrowUp: 'Up',
    LogicalKeyboardKey.arrowDown: 'Down',
    LogicalKeyboardKey.arrowLeft: 'Left',
    LogicalKeyboardKey.arrowRight: 'Right',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'Prior',
    LogicalKeyboardKey.pageDown: 'Next',
    LogicalKeyboardKey.space: 'space',
    LogicalKeyboardKey.f5: 'F5',
    LogicalKeyboardKey.f11: 'F11',
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final modifiers = <String>[
      // meta → ctrl: macOS users press cmd for shortcuts, and the remote browser
      // is Chromium on Linux, where those shortcuts are ctrl.
      if (keys.isControlPressed || keys.isMetaPressed) 'ctrl',
      if (keys.isAltPressed) 'alt',
    ];
    final named = _keyNames[event.logicalKey];
    final character = event.character;

    if (named != null) {
      _key([...modifiers, if (keys.isShiftPressed) 'shift', named].join('+'));
      return KeyEventResult.handled;
    }
    if (character != null && character.length == 1) {
      if (modifiers.isEmpty) {
        // Plain typing: send the character, not a keysym, so shifted and
        // non-US-layout characters arrive as themselves.
        ref.read(partyProvider.notifier).sendBrowserInput({
          'type': 'text',
          'text': character,
        });
      } else {
        _key([...modifiers, character.toLowerCase()].join('+'));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// Back / forward / reload / new tab / address bar, for the driver.
///
/// Everything here is injected as a keystroke into the remote Chromium, except the
/// address bar, which goes through the server's navigate call — typing a URL by
/// simulating ctrl+l and 40 keypresses is fragile when the page is busy.
class _BrowserToolbar extends ConsumerWidget {
  const _BrowserToolbar({
    required this.url,
    required this.onKey,
    required this.onSubmitted,
  });

  final TextEditingController url;
  final void Function(String combo) onKey;

  /// Hands keyboard focus back to the stream. Without it the next keystroke after
  /// submitting a URL goes into this text field, not the remote browser.
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: wp.surface.withValues(alpha: .92),
          border: Border.all(color: wp.line),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            children: [
              _AvIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onTap: () => onKey('alt+Left'),
              ),
              _AvIconButton(
                icon: Icons.arrow_forward,
                tooltip: 'Forward',
                onTap: () => onKey('alt+Right'),
              ),
              _AvIconButton(
                icon: Icons.refresh,
                tooltip: 'Reload',
                onTap: () => onKey('F5'),
              ),
              _AvIconButton(
                icon: Icons.add,
                tooltip: 'New tab',
                onTap: () => onKey('ctrl+t'),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: TextField(
                  controller: url,
                  style: TextStyle(color: wp.text, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Type a URL and press Enter',
                    hintStyle: TextStyle(color: wp.dim, fontSize: 13),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (value) {
                    final target = value.trim();
                    if (target.isEmpty) return;
                    ref
                        .read(partyProvider.notifier)
                        .navigateSharedBrowser(target);
                    url.clear();
                    onSubmitted();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is driving, how to change that, and the fullscreen toggle.
///
/// The fullscreen control belongs here rather than in the player chrome: this
/// stage has no player, and a remote browser is exactly the thing you want to
/// fill the window.
class _BrowserControlBar extends ConsumerWidget {
  const _BrowserControlBar({
    required this.browser,
    required this.isHost,
    required this.driving,
    required this.canDrive,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  final SharedBrowserState? browser;
  final bool isHost;
  final bool driving;
  final bool canDrive;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    final party = ref.read(partyProvider.notifier);
    final session = ref.watch(partyProvider);
    final myUserId = ref.read(currentUserIdProvider);
    final requests = browser?.requests ?? const <SharedBrowserRequest>[];
    final asked = requests.any((r) => r.userId == myUserId);

    final driverId = browser?.driverUserId;
    var driverName = driverId == null ? 'Nobody' : 'Someone';
    if (driverId != null) {
      for (final participant
          in session?.participants ?? const <Participant>[]) {
        if (participant.userId == driverId) {
          driverName = participant.name;
          break;
        }
      }
    }

    Widget pill(Widget child) => DecoratedBox(
      decoration: BoxDecoration(
        color: wp.surface.withValues(alpha: .9),
        border: Border.all(color: wp.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: child,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Host: pending control requests, with the decision attached.
        if (isHost && requests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: pill(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final request in requests) ...[
                    Text(
                      '${request.name} wants to drive',
                      style: TextStyle(color: wp.text, fontSize: 12.5),
                    ),
                    _AvIconButton(
                      icon: Icons.close,
                      tooltip: 'Decline',
                      onTap: () => party.denyBrowserControl(request.userId),
                    ),
                    _AvIconButton(
                      icon: Icons.check,
                      tooltip: 'Give control',
                      onTap: () => party.grantBrowserControl(request.userId),
                    ),
                  ],
                ],
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            pill(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    driving ? 'You are driving' : '$driverName is driving',
                    style: TextStyle(color: wp.dim, fontSize: 12),
                  ),
                  if (!canDrive)
                    // Deliberate: a touch device is view-only. Say so instead of
                    // offering a control that cannot work.
                    Text(
                      ' · control needs a computer',
                      style: TextStyle(color: wp.dim, fontSize: 11.5),
                    ),
                  if (canDrive && !driving) ...[
                    const SizedBox(width: AppSpacing.sm),
                    if (isHost)
                      _TextAction(
                        label: 'Take control',
                        onTap: party.reclaimBrowserControl,
                      )
                    else
                      _TextAction(
                        label: asked ? 'Asked…' : 'Ask to drive',
                        onTap: asked ? null : party.requestBrowserControl,
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            pill(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AvIconButton(
                    icon: isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                    onTap: onToggleFullscreen,
                  ),
                  if (isHost)
                    _AvIconButton(
                      icon: Icons.close,
                      tooltip: 'Close the shared browser',
                      onTap: party.stopSharedBrowser,
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A small text button for the control bar (Ask to drive / Take control).
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnalogButton(
      label: label,
      tone: AnalogButtonTone.ghost,
      dense: true,
      onPressed: onTap,
    );
  }
}

class _BrowserMessage extends StatelessWidget {
  const _BrowserMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.showSpinner = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSpinner)
                  const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.text,
                    ),
                  )
                else
                  Icon(icon, color: AppColors.faint, size: 38),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.dim,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the movie picker and, on a pick, calls [PartyNotifier.selectMedia] —
/// shared by the lobby's "Choose a movie" and the Watch Party menu's "Switch
/// movie" (watching-stage). `selectMedia` is a plain `party:selectMedia` ack
/// (no lobby-only guard), so it's safe from `watching` too.
Future<void> pickAndSwitchPartyMedia(
  BuildContext context,
  WidgetRef ref,
) async {
  final itemId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _MediaPickerSheet(),
  );
  if (itemId != null && itemId.isNotEmpty) {
    await ref.read(partyProvider.notifier).selectMedia(itemId);
  }
}

/// Host-only movie picker (matches the web host's pick flow). Lists the library
/// with a search box; tapping a poster returns its id, fed to
/// [PartyNotifier.selectMedia] → the server broadcasts the pick to everyone.
class _MediaPickerSheet extends ConsumerWidget {
  const _MediaPickerSheet();

  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 160,
    mainAxisSpacing: AppSpacing.xl,
    crossAxisSpacing: AppSpacing.lg,
    childAspectRatio: 0.52,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(browseItemsProvider);
    final api = ref.watch(apiClientProvider);

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Choose a movie', style: AppTheme.titleLarge),
                const Spacer(),
                AnalogIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  iconSize: 20,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              hint: 'Search your library',
              onChanged: (v) =>
                  ref.read(browseQueryProvider.notifier).state = v,
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: items.when(
                loading: () => GridView.builder(
                  gridDelegate: _gridDelegate,
                  itemCount: 12,
                  itemBuilder: (_, _) => const _PickerSkeletonCell(),
                ),
                error: (e, _) => ErrorState(
                  title: 'Couldn\'t load your library',
                  message: '$e',
                  onRetry: () => ref.invalidate(browseItemsProvider),
                ),
                data: (list) => list.isEmpty
                    ? const EmptyState(
                        icon: Icons.movie_filter_outlined,
                        title: 'Nothing found',
                        message: 'Try a different search.',
                      )
                    : GridView.builder(
                        gridDelegate: _gridDelegate,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final item = list[i];
                          return PosterCard(
                            title: item.name,
                            subtitle: item.productionYear?.toString(),
                            imageUrl: api.imageUrl(item.id),
                            onTap: () => Navigator.of(context).pop(item.id),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A poster-shaped shimmer placeholder for the media-picker loading grid.
class _PickerSkeletonCell extends StatelessWidget {
  const _PickerSkeletonCell();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: LoadingSkeleton(borderRadius: AppSpacing.radius),
        ),
        SizedBox(height: AppSpacing.sm),
        LoadingSkeleton(width: 96, height: 12),
        SizedBox(height: 6),
        LoadingSkeleton(width: 52, height: 10),
      ],
    );
  }
}

/// The shareable room code + participant count, on an acrylic surface with an
/// [AnalogBadge] count.
class _RoomCodePill extends StatelessWidget {
  const _RoomCodePill({required this.code, required this.count});
  final String code;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnalogPanel(
      translucent: true,
      blur: AppBlur.overlay,
      lift: AnalogLift.over,
      radius: AppSpacing.radiusPill,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Code',
            style: TextStyle(color: AppColors.dim, fontSize: 12),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            code,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          AnalogBadge(
            leading: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.text,
                shape: BoxShape.circle,
              ),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Host-only "wants to join" card with approve/reject. Fades in on appear
/// ([Reveal]) and sits on an acrylic surface.
class _JoinRequests extends ConsumerWidget {
  const _JoinRequests({required this.waiting});
  final List<Participant> waiting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(partyProvider.notifier);
    return Reveal(
      child: SizedBox(
        width: 268,
        child: AnalogPanel(
          translucent: true,
          blur: AppBlur.overlay,
          lift: AnalogLift.over,
          radius: AppSpacing.radiusLg,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm + 3,
                  AppSpacing.md,
                  AppSpacing.sm + 3,
                ),
                child: Text(
                  'Wants to join · ${waiting.length}',
                  style: const TextStyle(
                    color: AppColors.dim,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.line),
              for (final w in waiting)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.xs),
                          child: Text(
                            w.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      AnalogIconButton(
                        icon: Icons.close,
                        tooltip: 'Reject',
                        color: AppColors.red,
                        onPressed: () => notifier.reject(w.userId),
                      ),
                      AnalogIconButton(
                        icon: Icons.check,
                        tooltip: 'Approve',
                        color: AppColors.green,
                        onPressed: () => notifier.approve(w.userId),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right-side chat rail. It is deliberately opaque and blur-free; the movie
/// stage narrows by the same width while open instead of sitting behind it.
/// The room chat, as a glass panel over the picture.
///
/// It is an overlay in the strict sense: nothing else in the party Stack reads
/// its width, so opening it changes no other widget's constraints and the
/// video neither resizes nor reflows. What used to happen — the stage
/// narrowing by 360px — reframed the entire movie every time someone wanted to
/// type.
///
/// Opening it moves keyboard focus into the composer, and closing it hands
/// focus back so the player's keymap (space, arrows, F) works again without a
/// click. A drawer you have to click into before typing is a drawer that
/// costs two actions instead of one.
class _ChatSlideOver extends StatefulWidget {
  const _ChatSlideOver({
    required this.open,
    required this.width,
    required this.onClose,
  });

  final bool open;
  final double width;
  final VoidCallback onClose;

  @override
  State<_ChatSlideOver> createState() => _ChatSlideOverState();
}

class _ChatSlideOverState extends State<_ChatSlideOver> {
  final FocusNode _composer = FocusNode(debugLabel: 'chatComposer');

  @override
  void initState() {
    super.initState();
    if (widget.open) _grabFocus();
  }

  @override
  void didUpdateWidget(_ChatSlideOver old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      _grabFocus();
    } else {
      // Give focus back to whatever the player put it on. unfocus() alone
      // would leave the tree with no primary focus and swallow the next key.
      _composer.unfocus();
    }
  }

  /// Focus after the frame that opens the drawer. Requesting it during build
  /// targets a node that is still parked off-screen, and the request is
  /// dropped.
  void _grabFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.open) _composer.requestFocus();
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      // Clear of the window-chrome band, exactly as _WatchChrome is. Running to
      // the top edge put the drawer's own header inside the strip macOS uses
      // for dragging the window, so the top-right of the title bar stopped
      // responding whenever chat was open — and the panel's heading sat level
      // with the traffic lights, reading as part of the title bar rather than
      // as content.
      top: Platform.isMacOS ? integratedDesktopChromeHeight : 0,
      bottom: 0,
      right: open ? 0 : -(widget.width + 12),
      width: widget.width,
      child: SafeArea(
        left: false,
        // Escape closes. With the cursor parked in the composer the player's
        // own keymap no longer sees anything typed here, so without this the
        // drawer would be a place you can get into from the keyboard and only
        // out of with the mouse.
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
          },
          child: LiquidGlass(
          opaque: MediaQuery.of(context).highContrast,
          // Square against the right edge, rounded on the side that faces the
          // picture — the panel reads as something laid ON the stage rather
          // than a slot cut out of it.
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AnalogRadius.cardPx + 6),
            bottomLeft: Radius.circular(AnalogRadius.cardPx + 6),
          ),
          blur: 24,
          shadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 34,
              offset: Offset(-10, 0),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ROOM CHAT',
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              color: AppColors.faint,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Conversation',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnalogIconButton(
                      icon: Icons.close,
                      tooltip: 'Close chat',
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(child: ChatPanel(composerFocus: _composer)),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// The Watch Party control panel, opened by right-click / long-press over the
/// stage.
///
/// Rebuilt on the tray principle the rest of the app moved to: a face for each
/// person, a glyph for each action, and no prose. What it replaced was a 540px
/// scrolling column of section headings, explanatory sentences, labelled
/// buttons and a QR block — a settings page rendered over a film.
///
/// What survived the cut and why:
///
/// * **Faces, not a roster.** Avatars carry identity better than a list of
///   names, and the host's is ringed rather than captioned. Host actions
///   (transfer, remove) hang off a right-click on the face itself, which is
///   where you would aim anyway.
/// * **Sync mode as two glyphs.** Tethered = everyone waits for the slowest
///   viewer; free-running = the host never waits and others catch up. The
///   paragraph explaining each now lives in the tooltip.
/// * **No QR.** It cost the most space of anything here and answered a question
///   nobody asks from inside a running party — you invite people before you
///   start watching, and copy-link does that in one press from any device.
/// * **The code stays.** It is data, not chrome: the one thing you read aloud
///   to someone sitting next to you.
///
/// Everything is gated by role, and the two destructive actions (end the party,
/// remove someone) keep their confirmation and their red.
class _HostControlsDialog extends ConsumerStatefulWidget {
  const _HostControlsDialog();

  @override
  ConsumerState<_HostControlsDialog> createState() =>
      _HostControlsDialogState();
}

class _HostControlsDialogState extends ConsumerState<_HostControlsDialog> {
  bool _copied = false;
  bool _refreshing = false;

  Future<void> _copyInvite(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copied = true);
    // The glyph itself is the receipt, so no toast: a panel this small should
    // not raise a notice over the top of itself.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Rebuild this client's A/V room. Host and guest alike — a wedged publish
  /// path is not a role-specific fault, and the host having to end the party to
  /// clear one was the worst version of this.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final error = await ref.read(partyProvider.notifier).reconnectAv();
    if (!mounted) return;
    setState(() => _refreshing = false);
    showAnalogToast(
      context,
      error == null ? 'Video reconnected' : 'Could not reconnect video',
      tone: error == null ? AnalogToastTone.success : AnalogToastTone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final party = ref.watch(partyProvider);
    if (party == null) return const SizedBox.shrink();
    final me = ref.watch(currentUserIdProvider);
    final isHost = me != null && party.hostId == me;
    final notifier = ref.read(partyProvider.notifier);
    final watching = party.stage == 'watching';
    final joinUrl = '${ref.watch(apiClientProvider).baseUrl}/party/${party.id}';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 336),
        child: LiquidGlass(
          opaque: MediaQuery.of(context).highContrast,
          borderRadius: BorderRadius.circular(AnalogRadius.cardPx + 6),
          blur: 24,
          shadow: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 40,
              offset: Offset(0, 14),
            ),
          ],
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PartyFaces(
                party: party,
                isHost: isHost,
                notifier: notifier,
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: wp.line),
              const SizedBox(height: AppSpacing.md),

              // Everyone's actions, then the host's. One wrapping row so the
              // panel grows by a line rather than by a section.
              Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _AvIconButton(
                    icon: _refreshing ? Icons.hourglass_empty : Icons.refresh,
                    tooltip: _refreshing
                        ? 'Reconnecting…'
                        : 'Reconnect my video and audio',
                    onTap: _refreshing ? null : _refresh,
                  ),
                  _AvIconButton(
                    icon: _copied ? Icons.check : Icons.link,
                    tooltip: _copied ? 'Invite copied' : 'Copy the invite link',
                    onTap: () => _copyInvite(joinUrl),
                  ),
                  if (isHost) ...[
                    _AvIconButton(
                      icon: party.collaborativeControl
                          ? Icons.lock_open
                          : Icons.lock_outline,
                      tooltip: party.collaborativeControl
                          ? 'Everyone can play, pause and seek'
                          : 'Only you can play, pause and seek',
                      active: party.collaborativeControl,
                      onTap: () =>
                          notifier.setCollaborative(!party.collaborativeControl),
                    ),
                    if (watching) ...[
                      const _AvDivider.vertical(),
                      _AvIconButton(
                        icon: Icons.link,
                        tooltip:
                            'Tethered — everyone waits for the slowest viewer',
                        active: party.syncMode == 'dragging',
                        onTap: () => notifier.setSyncMode('dragging'),
                      ),
                      _AvIconButton(
                        icon: Icons.bolt,
                        tooltip:
                            'Free-running — you never wait; others catch up',
                        active: party.syncMode != 'dragging',
                        onTap: () => notifier.setSyncMode('hopping'),
                      ),
                      const _AvDivider.vertical(),
                      _AvIconButton(
                        icon: Icons.swap_horiz,
                        tooltip: 'Switch to another title',
                        onTap: () async {
                          Navigator.of(context).pop();
                          if (context.mounted) {
                            await pickAndSwitchPartyMedia(context, ref);
                          }
                        },
                      ),
                      _AvIconButton(
                        icon: Icons.grid_view,
                        tooltip: 'Stop the movie and pick something else',
                        onTap: () {
                          notifier.backToLobby();
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                    const _AvDivider.vertical(),
                    _AvIconButton(
                      icon: Icons.stop_circle_outlined,
                      tooltip: 'End the party for everyone',
                      danger: true,
                      onTap: () => _end(context, notifier),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: AppSpacing.md),
              // The code: data, not a label, so it keeps its own line and its
              // own weight. Selectable because reading it out is half of what
              // it is for.
              SelectableText(
                party.id,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  color: wp.dim,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _end(BuildContext context, PartyNotifier notifier) async {
    // Captured before the async gaps: the dialog's context is defunct once the
    // panel closes and the confirm resolves, so navigating through it would
    // silently no-op.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    final ok = await showConfirm(
      context,
      title: 'End party for everyone?',
      body:
          'Everyone will be disconnected and returned to the lobby. This can\'t be undone.',
      confirmLabel: 'End party',
      danger: true,
    );
    if (!ok) return;
    await notifier.end();
    router.go('/home');
  }
}

/// The room, as faces.
///
/// The host's avatar is ringed — a mark on the face itself rather than a badge
/// beside a name, because at this size the face IS the row. Right-clicking a
/// guest's face gives the host transfer and remove; on a guest's own screen the
/// faces are just faces.
class _PartyFaces extends StatelessWidget {
  const _PartyFaces({
    required this.party,
    required this.isHost,
    required this.notifier,
  });

  final PartyState party;
  final bool isHost;
  final PartyNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final p in party.participants)
          _Face(
            key: ValueKey(p.userId),
            participant: p,
            actionable: isHost && !p.isHost,
            notifier: notifier,
          ),
      ],
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    super.key,
    required this.participant,
    required this.actionable,
    required this.notifier,
  });

  final Participant participant;
  final bool actionable;
  final PartyNotifier notifier;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final p = participant;

    final face = Tooltip(
      message: p.isHost ? '${p.name} · host' : p.name,
      child: Container(
        width: _size + 6,
        height: _size + 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Uniform, always: a non-uniform border on a circle throws every
          // frame, so the ring is drawn at full width and merely made
          // transparent when this is not the host.
          border: Border.all(
            color: p.isHost ? wp.text : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: AvatarView(userId: p.userId, name: p.name, size: _size),
        ),
      ),
    );

    if (!actionable) return face;

    return AnalogContextMenu(
      actions: [
        AnalogMenuAction(
          label: 'Make host',
          icon: Icons.swap_horiz,
          onSelected: () => notifier.transferHost(p.userId),
        ),
        AnalogMenuAction(
          label: 'Remove from party',
          icon: Icons.person_remove,
          danger: true,
          onSelected: () => notifier.kick(p.userId),
        ),
      ],
      child: face,
    );
  }
}

/// Mic, camera and hide-self, as a vertical rail on the left edge of the
/// stage.
///
/// Separate from [_WatchChrome] because it belongs to a different box. That
/// chrome is a top strip one button tall; this needs the FULL stage height to
/// centre against, and cramming both into one row was what put five controls
/// into the same horizontal strip as the title and the window buttons.
///
/// Fades with the rest of the chrome, and stops taking input while hidden —
/// an invisible mute button is worse than no mute button.
class _DeviceRail extends ConsumerWidget {
  const _DeviceRail({
    required this.watching,
    required this.dock,
    required this.onToggleLayout,
  });

  final bool watching;
  final bool dock;
  final VoidCallback onToggleLayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lkState = ref.watch(livekitProvider);
    final lk = ref.read(livekitProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AvPendingToggle(
            iconOn: Icons.mic,
            iconOff: Icons.mic_off,
            on: lkState.micEnabled,
            tooltip: lkState.micEnabled
                ? 'Mute microphone'
                : 'Unmute microphone',
            onToggle: () => lk.setMic(!lkState.micEnabled),
          ),
          _AvPendingToggle(
            iconOn: Icons.videocam,
            iconOff: Icons.videocam_off,
            on: lkState.cameraEnabled,
            tooltip: lkState.cameraEnabled
                ? 'Turn camera off'
                : 'Turn camera on',
            onToggle: () => lk.setCamera(!lkState.cameraEnabled),
          ),
          _AvIconButton(
            icon: lkState.hideSelf ? Icons.visibility_off : Icons.visibility,
            tooltip: lkState.hideSelf ? 'Show my tile' : 'Hide my tile',
            active: lkState.hideSelf,
            onTap: () => lk.setHideSelf(!lkState.hideSelf),
          ),
          if (watching)
            _AvIconButton(
              icon: dock
                  ? Icons.view_sidebar_outlined
                  : Icons.picture_in_picture_alt_outlined,
              tooltip: dock ? 'Float cameras' : 'Dock cameras',
              onTap: onToggleLayout,
            ),
          // Last, and separated: a repair, not a device control.
          const _AvDivider(),
          const _ReconnectAvButton(),
        ],
      ),
    );
  }
}

/// Rebuilds this client's A/V room without disturbing the party.
///
/// Sits with the mic and camera because that is where the fault shows up: a
/// screen share that will not start, or a camera that will not come back, with
/// chat and playback working fine. Before this, the only way out was ending the
/// party — one person's wedged track costing everyone their seat.
class _ReconnectAvButton extends ConsumerStatefulWidget {
  const _ReconnectAvButton();

  @override
  ConsumerState<_ReconnectAvButton> createState() => _ReconnectAvButtonState();
}

class _ReconnectAvButtonState extends ConsumerState<_ReconnectAvButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await ref.read(partyProvider.notifier).reconnectAv();
    if (!mounted) return;
    setState(() => _busy = false);
    // Says something either way. A repair button that goes quiet on success is
    // indistinguishable from one that did nothing.
    showAnalogToast(
      context,
      error == null ? 'Video reconnected' : 'Could not reconnect video',
      tone: error == null ? AnalogToastTone.success : AnalogToastTone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AvIconButton(
      // A static glyph while busy, never a spinner: this rail is persistent
      // chrome, and an indeterminate progress indicator in persistent chrome
      // never settles — it hangs pumpAndSettle and every widget test with it.
      icon: _busy ? Icons.hourglass_empty : Icons.refresh,
      tooltip: _busy ? 'Reconnecting…' : 'Reconnect video and audio',
      onTap: _busy ? null : _run,
    );
  }
}

/// A hairline between the device toggles and the repair below them.
class _AvDivider extends StatelessWidget {
  const _AvDivider() : vertical = false;

  /// For a row of controls rather than a column — the control panel groups
  /// its glyphs the same way the rail does, turned ninety degrees.
  const _AvDivider.vertical() : vertical = true;

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: vertical ? 1 : 18,
      height: vertical ? 18 : 1,
      margin: vertical
          ? const EdgeInsets.symmetric(horizontal: 6)
          : const EdgeInsets.symmetric(vertical: 6),
      color: AppColors.line2,
    );
  }
}
