import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:window_manager/window_manager.dart';

import '../../models/models.dart';
import '../../player/player_view.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/floating_camera_tile.dart';
import '../../ui/widgets/party_qr.dart';

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
/// Creation and join-by-code live in the shell popcorn ([PartyWidget]); this
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
                partyId: widget.partyId,
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
    required this.partyId,
    required this.onLeave,
    required this.onBackHome,
  });

  final bool waiting;
  final bool busy;
  final String? error;
  final String? partyId;
  final VoidCallback onLeave;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    if (error != null) return _PartyNotFound(message: error!, onBack: onBackHome);
    if (waiting) return _WaitingRoom(partyId: partyId, onLeave: onLeave);
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
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
          ),
          SizedBox(height: AppSpacing.lg),
          Text('Connecting…', style: TextStyle(color: AppColors.dim, fontSize: 14)),
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

/// The redesigned waiting room (`pages/Lobby.tsx`): a sonar pulse conveying a
/// live connection, the "WAITING ROOM" eyebrow + heading, the party code as the
/// focal element, and a quiet "Leave party" exit.
class _WaitingRoom extends StatelessWidget {
  const _WaitingRoom({required this.partyId, required this.onLeave});
  final String? partyId;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Reveal(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SonarPulse(),
            const SizedBox(height: 40),
            const Text(
              'WAITING ROOM',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: AppColors.faint,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              "The host hasn't\nstarted yet",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w300,
                height: 1.1,
                letterSpacing: -1,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SizedBox(
              width: 320,
              child: Text(
                "You'll be pulled in the moment they let you through.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.dim, fontSize: 15, height: 1.55),
              ),
            ),
            if (partyId != null && partyId!.isNotEmpty) ...[
              const SizedBox(height: 40),
              const Text(
                'PARTY CODE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: AppColors.faint,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                partyId!,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                  color: AppColors.text,
                ),
              ),
            ],
            const SizedBox(height: 44),
            TextButton(
              onPressed: onLeave,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.dim,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              child: const Text(
                'Leave party',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three expanding rings + a solid centre dot — a live-connection sonar, not a
/// generic spinner (`Lobby.tsx` `@keyframes sonar`).
class _SonarPulse extends StatefulWidget {
  const _SonarPulse();

  @override
  State<_SonarPulse> createState() => _SonarPulseState();
}

class _SonarPulseState extends State<_SonarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++) _ring((_c.value + i / 3) % 1.0),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.text,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.text.withValues(alpha: 0.5),
                      blurRadius: 16,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(double t) {
    final scale = 0.2 + t * 0.8;
    final opacity = ((1 - t) * 0.9).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.text, width: 1.5),
          ),
        ),
      ),
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
///   5  chat slide-over + its scrim
/// The Watch Party menu opens above everything via right-click / long-press.
class _ImmersiveParty extends ConsumerStatefulWidget {
  const _ImmersiveParty();

  @override
  ConsumerState<_ImmersiveParty> createState() => _ImmersivePartyState();
}

class _ImmersivePartyState extends ConsumerState<_ImmersiveParty> {
  bool _chatOpen = false;
  bool _chromeVisible = true;
  bool _isFullscreen = false;

  /// Camera layout: false = floating PiP tiles, true = docked left column.
  bool _dock = false;

  /// Single-open guard for the right-click / long-press Watch Party menu.
  bool _menuOpen = false;

  /// Push-to-talk hold guard (mirrors `usePushToTalk`): distinguishes a
  /// PTT-driven unmute from a manual one and guards key-repeat.
  bool _pttHolding = false;

  Timer? _idleTimer;

  @override
  void dispose() {
    _idleTimer?.cancel();
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

  /// Wake the chrome and re-arm the SINGLE idle hide. Only auto-hides while
  /// watching; in the lobby (no video) the chrome stays put, like the web.
  void _poke({required bool watching}) {
    _idleTimer?.cancel();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    if (!watching) return;
    _idleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_chatOpen) setState(() => _chromeVisible = false);
    });
  }

  // Push-to-talk (hold T): momentarily opens the mic, returning to muted on
  // release. No-op if the user has manually unmuted; the hold guard suppresses
  // key-repeat. Wired through livekit only — never authors playback commands.
  void _pttStart() {
    if (_pttHolding) return;
    if (ref.read(livekitProvider).micEnabled) return; // manually unmuted → no-op
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
  // socket / LiveKit / sync engine stay alive and the popcorn shows "N in
  // party". End (host) lives in the Watch Party menu; leave lives in the
  // popcorn — Stop Movie (backToLobby) and Stop Stream (end) stay distinct.
  Future<void> _minimize() async {
    final notifier = ref.read(partyProvider.notifier);
    if (notifier.isHost) {
      await notifier.backToLobby();
    } else {
      await notifier.leave();
    }
    final player = ref.read(playerControllerProvider);
    await player.pause();
    await player.seek(Duration.zero);
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(partyProvider)!;
    final controller = ref.watch(playerControllerProvider);
    final canControl = ref.read(partyProvider.notifier).canControl;
    final watching = party.stage == 'watching';

    // ONE unified auto-hide flag: chrome + transport bar fade together. Stays
    // shown while chat is open or in the lobby.
    final chromeShown = _chromeVisible || _chatOpen || !watching;

    final stage = watching
        ? PlayerView(
            controller: controller,
            itemId: party.mediaItemId,
            mediaSourceId: party.mediaSourceId,
            apiClient: ref.watch(apiClientProvider),
            canControl: canControl,
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
            onWake: () => _poke(watching: true),
            onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
            onPushToTalkStart: _pttStart,
            onPushToTalkStop: _pttStop,
          )
        : _LobbyStage(party: party);

    return MouseRegion(
      onHover: (_) => _poke(watching: watching),
      child: Listener(
        onPointerDown: (event) {
          _poke(watching: watching);
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
              // VideoView — only the surrounding box narrows.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: (watching && _dock) ? 210.0 : 0.0,
                top: 0,
                right: 0,
                bottom: 0,
                child: stage,
              ),

              // 1 — cameras: floating PiP layer, or the docked left column.
              // Exactly one child so the stage above keeps a stable Stack slot.
              if (watching && _dock)
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 210,
                  child: _CameraDock(),
                )
              else
                const Positioned.fill(child: FloatingCameraLayer()),

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
                      dock: _dock,
                      chatOpen: _chatOpen,
                      onBack: _minimize,
                      onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
                      onToggleLayout: () => setState(() => _dock = !_dock),
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

              // 5 — chat slide-over + acrylic scrim.
              if (_chatOpen)
                Positioned.fill(
                  child: Scrim(
                    opacity: 0.5,
                    blur: true,
                    onTap: () => setState(() => _chatOpen = false),
                  ),
                ),
              _ChatSlideOver(
                open: _chatOpen,
                onClose: () => setState(() => _chatOpen = false),
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
    final lkState = ref.watch(livekitProvider);
    final lk = ref.read(livekitProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14 + desktopLeadingControlInset,
          right: 14 + desktopTrailingControlInset,
          top: 10,
          bottom: 10,
        ),
        child: Row(
          children: [
            _AvIconButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              danger: true,
              onTap: onBack,
            ),
            const Spacer(),
            _AvIconButton(
              icon: Icons.chat_bubble_outline,
              tooltip: 'Chat',
              active: chatOpen,
              onTap: onToggleChat,
            ),
            _AvPendingToggle(
              iconOn: Icons.mic,
              iconOff: Icons.mic_off,
              on: lkState.micEnabled,
              tooltip: lkState.micEnabled ? 'Mute microphone' : 'Unmute microphone',
              onToggle: () => lk.setMic(!lkState.micEnabled),
            ),
            _AvPendingToggle(
              iconOn: Icons.videocam,
              iconOff: Icons.videocam_off,
              on: lkState.cameraEnabled,
              tooltip: lkState.cameraEnabled ? 'Turn camera off' : 'Turn camera on',
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
          ],
        ),
      ),
    );
  }
}

/// A flat, boxless, monochrome player-chrome icon button (`Player.tsx`
/// `IconBtn`): no box/border/fill; glyph rests at 62% near-white, brightens to
/// full near-white on hover / when [active], and is red when [danger].
class _AvIconButton extends StatefulWidget {
  const _AvIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;
  final bool busy;

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

    return sc.Tooltip(
      tooltip: (context) => sc.TooltipContainer(child: Text(widget.tooltip)),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.busy ? null : widget.onTap,
          child: SizedBox(width: 34, height: 34, child: Center(child: glyph)),
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
              child: sc.SurfaceCard(
                surfaceBlur: AppBlur.overlay,
                surfaceOpacity: 0.9,
                borderColor: AppColors.line2,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: AppColors.red),
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

/// Opens the movie picker and, on a pick, calls [PartyNotifier.selectMedia] —
/// shared by the lobby's "Choose a movie" and the Watch Party menu's "Switch
/// movie" (watching-stage). `selectMedia` is a plain `party:selectMedia` ack
/// (no lobby-only guard), so it's safe from `watching` too.
Future<void> pickAndSwitchPartyMedia(BuildContext context, WidgetRef ref) async {
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
                sc.Tooltip(
                  tooltip: (context) =>
                      const sc.TooltipContainer(child: Text('Close')),
                  child: sc.IconButton.ghost(
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.dim,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
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
/// `sc.SecondaryBadge` count.
class _RoomCodePill extends StatelessWidget {
  const _RoomCodePill({required this.code, required this.count});
  final String code;
  final int count;

  @override
  Widget build(BuildContext context) {
    return sc.SurfaceCard(
      surfaceBlur: AppBlur.overlay,
      surfaceOpacity: 0.9,
      borderColor: AppColors.line2,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
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
          sc.SecondaryBadge(
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
        child: sc.SurfaceCard(
          surfaceBlur: AppBlur.overlay,
          surfaceOpacity: 0.9,
          borderColor: AppColors.line2,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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
                      sc.Tooltip(
                        tooltip: (context) =>
                            const sc.TooltipContainer(child: Text('Reject')),
                        child: sc.IconButton.ghost(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.red,
                            size: 18,
                          ),
                          onPressed: () => notifier.reject(w.userId),
                        ),
                      ),
                      sc.Tooltip(
                        tooltip: (context) =>
                            const sc.TooltipContainer(child: Text('Approve')),
                        child: sc.IconButton.ghost(
                          icon: const Icon(
                            Icons.check,
                            color: AppColors.green,
                            size: 18,
                          ),
                          onPressed: () => notifier.approve(w.userId),
                        ),
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

/// Right-side chat slide-over — animates in/out, never permanently docked
/// (mirrors the web's dismissible chat panel). Wraps the existing [ChatPanel]
/// so all send/receive/rate-limit behavior is preserved.
class _ChatSlideOver extends StatelessWidget {
  const _ChatSlideOver({required this.open, required this.onClose});
  final bool open;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      right: open ? 0 : -360,
      width: 340,
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: sc.SurfaceCard(
            surfaceBlur: AppBlur.overlay,
            surfaceOpacity: 0.9,
            borderColor: AppColors.line2,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            clipBehavior: Clip.antiAlias,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Chat',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      sc.Tooltip(
                        tooltip: (context) => const sc.TooltipContainer(
                          child: Text('Close chat'),
                        ),
                        child: sc.IconButton.ghost(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.dim,
                            size: 18,
                          ),
                          onPressed: onClose,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.line),
                const Expanded(child: ChatPanel()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Watch Party menu (mirrors the web's RoomControls modal): participant
/// roster (host-only transfer/kick), a host-only collaborative-control toggle,
/// a host+watching sync-mode picker with a mode description, host+watching
/// "Switch movie" / "Pick something else" (backToLobby = Stop Movie), the QR +
/// code share block (everyone), and a host-only danger-zone End party (Stop
/// Stream). Opened for everyone via right-click / long-press; host-only sections
/// are gated by [isHost] internally.
class _HostControlsDialog extends ConsumerWidget {
  const _HostControlsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider);
    if (party == null) return const SizedBox.shrink();
    final me = ref.watch(currentUserIdProvider);
    final isHost = me != null && party.hostId == me;
    final notifier = ref.read(partyProvider.notifier);
    final watching = party.stage == 'watching';
    final joinUrl = '${ref.watch(apiClientProvider).baseUrl}/party/${party.id}';

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Text(
                    'Watch party',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  sc.Tooltip(
                    tooltip: (context) =>
                        const sc.TooltipContainer(child: Text('Close')),
                    child: sc.IconButton.ghost(
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.dim,
                        size: 18,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                shrinkWrap: true,
                children: [
                  _sectionLabel('In the party · ${party.participants.length}'),
                  const SizedBox(height: AppSpacing.sm),
                  StaggeredList(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final p in party.participants)
                        _RosterRow(
                          key: ValueKey(p.userId),
                          participant: p,
                          notifier: notifier,
                          isHost: isHost,
                        ),
                    ],
                  ),
                  if (isHost) ...[
                    const Divider(color: AppColors.line, height: AppSpacing.xl),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Collaborative control',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Let guests browse, play, pause & seek',
                                style: TextStyle(
                                  color: AppColors.dim,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        sc.Switch(
                          value: party.collaborativeControl,
                          onChanged: (v) => notifier.setCollaborative(v),
                        ),
                      ],
                    ),
                  ],
                  if (watching && isHost) ...[
                    const Divider(color: AppColors.line, height: AppSpacing.xl),
                    _sectionLabel('Sync mode'),
                    const SizedBox(height: 6),
                    Text(
                      party.syncMode == 'dragging'
                          ? 'Everyone waits for the slowest viewer'
                          : 'Host never waits; slow viewers catch up',
                      style: const TextStyle(
                        color: AppColors.dim,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SyncModeToggle(
                      value: party.syncMode,
                      onChanged: notifier.setSyncMode,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: 'Switch movie',
                      icon: Icons.swap_horiz,
                      variant: AppButtonVariant.primary,
                      expand: true,
                      onPressed: () async {
                        Navigator.of(context).pop();
                        if (context.mounted) {
                          await pickAndSwitchPartyMedia(context, ref);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: '← Pick something else',
                      variant: AppButtonVariant.secondary,
                      expand: true,
                      onPressed: () {
                        notifier.backToLobby();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                  const Divider(color: AppColors.line, height: AppSpacing.xl),
                  _sectionLabel('Share this code'),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      PartyQr(url: joinUrl, size: 96),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText(
                              party.id,
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                color: AppColors.text,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            AppButton(
                              label: 'Copy link',
                              variant: AppButtonVariant.secondary,
                              icon: Icons.copy,
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: joinUrl),
                                );
                                if (context.mounted) {
                                  _showPartyToast(context, 'Invite link copied');
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isHost) ...[
                    const Divider(color: AppColors.line, height: AppSpacing.xl),
                    _sectionLabel('Danger zone', danger: true),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'End party for everyone',
                      variant: AppButtonVariant.danger,
                      expand: true,
                      onPressed: () async {
                        // Capture the router before the async gaps — the dialog
                        // context is defunct after the menu closes + the confirm
                        // resolves, so navigating through it would silently no-op.
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
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionLabel(String text, {bool danger = false}) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: danger ? AppColors.red : AppColors.faint,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
}

/// One participant in the Watch Party menu roster. Transfer-host / kick (inline
/// + a right-click [sc.ContextMenu]) appear only when the VIEWER is the host and
/// the row is a guest.
class _RosterRow extends StatelessWidget {
  const _RosterRow({
    super.key,
    required this.participant,
    required this.notifier,
    required this.isHost,
  });

  final Participant participant;
  final PartyNotifier notifier;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final showActions = isHost && !p.isHost;
    final row = Row(
      children: [
        if (p.isHost)
          const Padding(
            padding: EdgeInsets.only(right: AppSpacing.xs),
            child: Icon(Icons.star, color: AppColors.text, size: 15),
          ),
        Expanded(
          child: Text(
            p.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (p.isHost)
          const sc.SecondaryBadge(
            child: Text(
              'HOST',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          )
        else if (showActions) ...[
          sc.Tooltip(
            tooltip: (context) =>
                const sc.TooltipContainer(child: Text('Make host')),
            child: sc.IconButton.ghost(
              icon: const Icon(
                Icons.swap_horiz,
                color: AppColors.faint,
                size: 18,
              ),
              onPressed: () => notifier.transferHost(p.userId),
            ),
          ),
          sc.Tooltip(
            tooltip: (context) =>
                const sc.TooltipContainer(child: Text('Kick')),
            child: sc.IconButton.ghost(
              icon: const Icon(Icons.logout, color: AppColors.red, size: 18),
              onPressed: () => notifier.kick(p.userId),
            ),
          ),
        ],
      ],
    );

    if (!showActions) return row;

    return sc.ContextMenu(
      items: [
        sc.MenuButton(
          leading: const Icon(Icons.swap_horiz, size: 16),
          onPressed: (_) => notifier.transferHost(p.userId),
          child: const Text('Make host'),
        ),
        sc.MenuButton(
          leading: const Icon(Icons.logout, color: AppColors.red, size: 16),
          onPressed: (_) => notifier.kick(p.userId),
          child: const Text('Kick', style: TextStyle(color: AppColors.red)),
        ),
      ],
      child: row,
    );
  }
}

/// The sync-mode segmented control, an `sc.ButtonGroup` of `sc.Toggle`s. Tapping
/// the already-selected segment is a no-op (radio semantics), so a mode can
/// never be deselected into an invalid empty state.
class _SyncModeToggle extends StatelessWidget {
  const _SyncModeToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    sc.Toggle seg(String id, String label) => sc.Toggle(
      value: value == id,
      style: const sc.ButtonStyle.outline(),
      onChanged: (on) {
        if (on) onChanged(id);
      },
      child: Text(label),
    );

    return sc.ButtonGroup(
      children: [seg('hopping', 'Hopping'), seg('dragging', 'Dragging')],
    );
  }
}

/// Shows a transient shadcn toast through the app-wide `ToastLayer` (provided by
/// the root `ShadcnLayer`).
void _showPartyToast(BuildContext context, String message) {
  sc.showToast(
    context: context,
    location: sc.ToastLocation.topCenter,
    builder: (context, overlay) => sc.SurfaceCard(
      surfaceBlur: AppBlur.overlay,
      surfaceOpacity: 0.9,
      borderColor: AppColors.line2,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 16,
            color: AppColors.green,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
