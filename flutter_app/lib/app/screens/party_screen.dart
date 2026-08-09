import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  bool _isFullscreen = false;

  /// The drawer itself moved to [PartyOverlay] at the root, so its open state
  /// has to be somewhere both can see. This screen only reads it (to pin the
  /// chrome open and light the chat button) and toggles it.
  bool get _chatOpen => ref.read(chatDrawerOpenProvider);

  /// Single-open guard for the right-click / long-press Watch Party menu.
  bool _menuOpen = false;

  /// Push-to-talk hold guard (mirrors `usePushToTalk`): distinguishes a
  /// PTT-driven unmute from a manual one and guards key-repeat.
  bool _pttHolding = false;

  /// The party's SINGLE chrome auto-hide clock, covering the player and the
  /// top-right A/V cluster together. Same
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
  /// [immersive] is true for the player — the stage where chrome sits over
  /// content someone is looking at. The lobby keeps it up, now as a named hold
  /// rather than a timer that is simply never armed.
  void _poke({required bool immersive, PlayerInputKind? kind}) {
    if (immersive) {
      _autoHide.release(_kLobbyHold);
    } else {
      _autoHide.hold(_kLobbyHold);
    }
    _autoHide.noteInput(kind ?? PlayerInputKind.pointer);
  }

  void _setChatOpen(bool open) {
    ref.read(chatDrawerOpenProvider.notifier).state = open;
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
    // ONE unified auto-hide flag: chrome + transport bar fade together. "Stays
    // shown while chat is open / in the lobby" is now a pair of HOLDS on the
    // shared controller rather than extra terms in this expression, so the rule
    // lives in player_core alongside the player's. The lobby hold is released
    // by the first _poke on an immersive stage, exactly as the old timer was
    // only armed by the first _poke there.
    final chromeShown = _autoHide.visible;
    final chatOpen = ref.watch(chatDrawerOpenProvider);

    final stage = watching
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
            chatOpen: chatOpen,
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
      onHover: (_) => _poke(immersive: watching),
      child: Listener(
        onPointerDown: (event) {
          _poke(immersive: watching);
          if (event.buttons == kSecondaryButton) _handleSecondary();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          // Trackpad / touch fallback for the right-click Watch Party menu.
          onLongPress: _openWatchPartyMenu,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 0 — the stage. The cameras, chat, join requests and the
              // A/V banner are NOT here any more: they render in
              // [PartyOverlay] at the root, so they survive leaving this
              // screen. What is left is the picture and its own chrome.
              Positioned.fill(child: stage),

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
                      chatOpen: chatOpen,
                      onBack: _minimize,
                      onToggleChat: () => _setChatOpen(!chatOpen),
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
                      child: const _DeviceRail(),
                    ),
                  ),
                ),
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
    required this.chatOpen,
    required this.onBack,
    required this.onToggleChat,
  });

  final bool watching;
  final bool chatOpen;
  final VoidCallback onBack;
  final VoidCallback onToggleChat;

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
                    if (watching) ...[
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

              // The two SETTINGS, as switches.
              //
              // These stayed labelled on purpose. A glyph works for a verb —
              // press it, something happens, and if you guessed wrong you press
              // it again. It does not work for a persistent mode: a lock icon
              // cannot say whether it means "locked now" or "press to lock",
              // and getting sync mode wrong is not something a viewer can even
              // see, let alone undo. A switch shows its state without being
              // interpreted, and one word says which state that is.
              if (isHost) ...[
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: wp.line),
                _SettingRow(
                  label: 'Everyone can control',
                  hint: 'Guests may play, pause and seek',
                  value: party.collaborativeControl,
                  onChanged: notifier.setCollaborative,
                ),
                if (watching)
                  _SettingRow(
                    label: 'Wait for everyone',
                    hint: party.syncMode == 'dragging'
                        ? 'Playback holds for the slowest viewer'
                        : 'You never wait; others catch up',
                    value: party.syncMode == 'dragging',
                    onChanged: (on) =>
                        notifier.setSyncMode(on ? 'dragging' : 'hopping'),
                  ),
              ],

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

/// A named switch: a mode you set and leave, as opposed to a button you press.
///
/// The hint is one line and it changes with the state, so it reports what is
/// true rather than explaining the feature.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: wp.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  hint,
                  style: TextStyle(color: wp.faint, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          AnalogSwitch(
            value: value,
            onChanged: onChanged,
            semanticLabel: label,
          ),
        ],
      ),
    );
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
  const _DeviceRail();

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
          // Reconnect is NOT here. It moved to the watch-party control panel:
          // the rail is the four things you reach for mid-film, and a repair
          // you need once a month does not earn a permanent seat among them.
        ],
      ),
    );
  }
}

/// A hairline separating groups of controls.
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
