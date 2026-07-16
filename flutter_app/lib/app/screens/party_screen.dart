import 'dart:async';

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

/// The watch-party screen — an IMMERSIVE, full-bleed layout mirroring the web
/// app (`app/client/src/pages/Party.jsx`). The movie fills the window; camera
/// tiles float over it as draggable PiP windows ([FloatingCameraLayer]); chat
/// is a right-side slide-over (not a docked column); the party controls live in
/// an auto-hiding floating cluster over the video; and host/people management
/// (approve/reject, transfer-host, kick, collaborative + sync-mode, back-to-
/// lobby, end party) live in a modal reached from the control cluster —
/// matching the web's RoomControls modal rather than a permanent panel.
///
/// Lobby vs watching are distinct stages, like the web: `stage == 'lobby'`
/// shows a "waiting for a title" stage; `stage == 'watching'` mounts the real
/// [PlayerView]. Every provider/feature from the previous docked design is
/// preserved — the composition and (now) the presentation changed: the bespoke
/// chrome is rebuilt on shadcn primitives (acrylic surfaces, `sc.IconButton` +
/// `sc.Tooltip`, `sc.Badge`, `sc.Switch`, a toggle-group, a participant context
/// menu, and toasts), with calm entrance motion on the lobby + roster.
///
/// `partyId == null` is the pre-join entry point (create or join by id); once
/// joined the same widget renders the immersive in-party layout.
class PartyScreen extends ConsumerStatefulWidget {
  const PartyScreen({super.key, this.partyId});
  final String? partyId;

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen> {
  final _joinController = TextEditingController();
  bool _busy = false;
  bool _waiting = false;
  String? _error;
  bool _autoJoinAttempted = false;

  @override
  void initState() {
    super.initState();
    final id = widget.partyId;
    if (id != null && id.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join(id));
    }
  }

  @override
  void dispose() {
    _joinController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final partyId = await ref.read(partyProvider.notifier).create();
      if (!mounted) return;
      context.go('/party/$partyId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(String partyId) async {
    if (_autoJoinAttempted && widget.partyId == partyId) return;
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

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(partyProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: party == null
          ? SafeArea(
              child: _PartyLobby(
                joinController: _joinController,
                busy: _busy,
                waiting: _waiting,
                error: _error,
                onCreate: _create,
                onJoin: () {
                  final id = _joinController.text.trim();
                  if (id.isNotEmpty) context.go('/party/$id');
                },
              ),
            )
          // The immersive stage is intentionally NOT wrapped in SafeArea — it is
          // full-bleed like the web's fixed stage; individual overlays inset
          // themselves off the edges.
          : const _ImmersiveParty(),
    );
  }
}

/// Pre-join entry: create a new party or join one by id. Also surfaces the
/// "waiting for host approval" state returned by `join()`. The card fades +
/// slides in on mount ([Reveal]) for a calm, cinematic entrance.
class _PartyLobby extends StatelessWidget {
  const _PartyLobby({
    required this.joinController,
    required this.busy,
    required this.waiting,
    required this.error,
    required this.onCreate,
    required this.onJoin,
  });

  final TextEditingController joinController;
  final bool busy;
  final bool waiting;
  final String? error;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    if (waiting) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Reveal(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(height: AppSpacing.xl),
                  Text(
                    'Waiting to be let in',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    'The host has to approve your request. Hang tight — this screen updates the moment you are let in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.dim,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Reveal(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Watch Party',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Host a session or join one already running.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.dim, fontSize: 13.5),
                ),
                const SizedBox(height: AppSpacing.xxl),
                AppButton(
                  label: 'Start a party',
                  variant: AppButtonVariant.primary,
                  expand: true,
                  busy: busy,
                  onPressed: busy ? null : onCreate,
                ),
                const SizedBox(height: AppSpacing.xl),
                const Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.line)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Text(
                        'or',
                        style: TextStyle(color: AppColors.faint, fontSize: 12),
                      ),
                    ),
                    Expanded(child: Divider(color: AppColors.line)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                AppTextField(
                  controller: joinController,
                  hint: 'Party ID',
                  onSubmitted: (_) => onJoin(),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Join party',
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  busy: busy,
                  onPressed: busy ? null : onJoin,
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The immersive in-party stage. A full-bleed [Stack] whose layers mirror the
/// web's z-order (see `watchLayers.js`):
///   0  the stage — [PlayerView] when watching, a lobby card otherwise
///   1  floating camera tiles ([FloatingCameraLayer])
///   2  the auto-hiding party control chrome (top-right cluster + room pill +
///      join-request notifications)
///   3  the chat slide-over + its (acrylic) scrim
/// The host-controls modal opens above everything via [showDialog].
class _ImmersiveParty extends ConsumerStatefulWidget {
  const _ImmersiveParty();

  @override
  ConsumerState<_ImmersiveParty> createState() => _ImmersivePartyState();
}

class _ImmersivePartyState extends ConsumerState<_ImmersiveParty> {
  bool _chatOpen = false;
  bool _chromeVisible = true;
  bool _isFullscreen = false;
  Timer? _idleTimer;

  @override
  void dispose() {
    _idleTimer?.cancel();
    // Don't leave the OS window stuck in fullscreen after navigating away
    // from the party (e.g. the host ends the party mid-fullscreen). This is
    // purely a window-chrome toggle — it never touches the party/LiveKit
    // state, so the call itself is unaffected either way.
    if (_isFullscreen) {
      unawaited(windowManager.setFullScreen(false));
    }
    super.dispose();
  }

  /// Toggles OS-level window fullscreen for the movie. The LiveKit
  /// room/camera tiles and the party socket connection are entirely
  /// unaffected — this only asks `window_manager` to resize the window and
  /// flips local UI state so [PlayerChrome] renders the right icon.
  /// [FloatingCameraLayer] is a fixed layer of the immersive [Stack] below,
  /// so the camera PiP tiles keep rendering over the video in both states.
  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _isFullscreen = next);
  }

  /// Wake the chrome and re-arm the idle hide. Only auto-hides while watching;
  /// in the lobby (no video) the chrome stays put, like the web.
  void _poke({required bool watching}) {
    _idleTimer?.cancel();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    if (!watching) return;
    _idleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_chatOpen) setState(() => _chromeVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(partyProvider)!;
    final notifier = ref.read(partyProvider.notifier);
    final controller = ref.watch(playerControllerProvider);
    final canControl = notifier.canControl;
    final isHost = notifier.isHost;
    final watching = party.stage == 'watching';

    // Chrome is always shown when chat is open or when idle-hide is disabled.
    final chromeShown = _chromeVisible || _chatOpen || !watching;

    final stage = watching
        ? PlayerView(
            controller: controller,
            itemId: party.mediaItemId,
            mediaSourceId: party.mediaSourceId,
            apiClient: ref.watch(apiClientProvider),
            canControl: canControl,
            title: party.mediaItemId,
            onBack: () => _confirmLeave(context, isHost: isHost),
            onToggleFullscreen: _toggleFullscreen,
            isFullscreen: _isFullscreen,
            // Author the host's scrubs to the sync engine → server → every
            // other client (web + Flutter). Without this the drag only moves
            // the local player and never propagates.
            onSeek: (pos) => ref.read(syncEngineProvider).requestSeek(pos),
            // Party playback is always routed through MediaCacheProxy (see
            // party_provider.dart), so the "downloaded" indicator is always
            // available here (unlike the detail screen's offline-guest path).
            cachedSpans: party.mediaItemId == null
                ? null
                : ref
                      .watch(mediaCacheProxyProvider)
                      .cachedSpansFor(party.mediaItemId!),
          )
        : _LobbyStage(party: party);

    return MouseRegion(
      onHover: (_) => _poke(watching: watching),
      child: Listener(
        onPointerDown: (_) => _poke(watching: watching),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 0 — the stage. Never permanently covered: the camera layer only
            // paints its tiles (transparent elsewhere) and the chrome/chat sit
            // in their own corners.
            Positioned.fill(child: stage),

            // 1 — floating camera tiles over the whole stage.
            const Positioned.fill(child: FloatingCameraLayer()),

            // 2 — party control chrome (auto-hiding while watching).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !chromeShown,
                child: AnimatedOpacity(
                  opacity: chromeShown ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _PartyChrome(
                    party: party,
                    isHost: isHost,
                    chatOpen: _chatOpen,
                    onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
                    onOpenHostControls: () => _openHostControls(context),
                    onLeave: () => _confirmLeave(context, isHost: isHost),
                  ),
                ),
              ),
            ),

            // 3 — chat slide-over + acrylic scrim.
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
    );
  }

  void _openHostControls(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x8C000000),
      builder: (_) => const _HostControlsDialog(),
    );
  }

  Future<void> _confirmLeave(
    BuildContext context, {
    required bool isHost,
  }) async {
    final ok = await showConfirm(
      context,
      title: isHost ? 'End the party?' : 'Leave the party?',
      body: isHost
          ? 'This ends the session for everyone.'
          : 'You can rejoin later with the party ID.',
      confirmLabel: isHost ? 'End party' : 'Leave',
      danger: true,
    );
    if (!ok) return;
    if (isHost) {
      await ref.read(partyProvider.notifier).end();
    } else {
      await ref.read(partyProvider.notifier).leave();
    }
    if (context.mounted) context.go('/home');
  }
}

/// The lobby stage: shown before a title is selected. Distinct from the
/// watching stage (which is the movie), mirroring the web's lobby screen. Shows
/// the room code + count and a status line; cameras still float and chat still
/// works on top of it. Content fades in on mount ([Reveal]).
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
/// shared by the lobby's "Choose a movie" and the host controls' "Switch
/// movie" (watching-stage) so a host can change titles either before anyone's
/// watching or mid-movie, without leaving/ending the party. `selectMedia` is a
/// plain `party:selectMedia` ack (PLAN §3.5) with no lobby-only guard on
/// either the client or server, so it's safe to call from `watching` too.
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
/// with a search box; tapping a poster returns its id, which the lobby feeds to
/// [PartyNotifier.selectMedia] → the server broadcasts the pick to everyone
/// (web + Flutter) and playback starts in sync.
///
/// Kept as a Material [showModalBottomSheet] (per the redesign plan); only the
/// CONTENTS are restyled onto the design system (shadcn close button, skeleton
/// loading grid, and the frozen [PosterCard]/[ErrorState]/[EmptyState]).
class _MediaPickerSheet extends ConsumerWidget {
  const _MediaPickerSheet();

  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 160,
    mainAxisSpacing: AppSpacing.xl,
    crossAxisSpacing: AppSpacing.lg,
    // Poster is 2:3 plus a title + subtitle line below, so the cell must be
    // taller than the poster itself (a higher ratio overflows the PosterCard's
    // Column).
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

/// A poster-shaped shimmer placeholder for the media-picker loading grid,
/// composed from the frozen [LoadingSkeleton].
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

/// The floating party-control chrome: room-code pill (top-left) + a top-right
/// cluster of mic/cam/hide-self/chat toggles, host controls (host only, with a
/// waiting badge), and leave. Below the cluster, a host-only join-request card
/// with approve/reject. Consolidated at the top so it never collides with the
/// [PlayerView]'s own bottom transport bar. Rebuilt on shadcn: acrylic surfaces,
/// `sc.IconButton` + `sc.Tooltip`, `sc.Badge`.
class _PartyChrome extends ConsumerWidget {
  const _PartyChrome({
    required this.party,
    required this.isHost,
    required this.chatOpen,
    required this.onToggleChat,
    required this.onOpenHostControls,
    required this.onLeave,
  });

  final PartyState party;
  final bool isHost;
  final bool chatOpen;
  final VoidCallback onToggleChat;
  final VoidCallback onOpenHostControls;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lkState = ref.watch(livekitProvider);
    final lk = ref.read(livekitProvider.notifier);
    final waiting = ref.watch(partyWaitingProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                _RoomCodePill(code: party.id, count: party.participants.length),
                const Spacer(),
                _ChromeCluster(
                  children: [
                    _PendingToggle(
                      iconOn: Icons.mic,
                      iconOff: Icons.mic_off,
                      on: lkState.micEnabled,
                      tooltip: lkState.micEnabled
                          ? 'Mute microphone'
                          : 'Unmute microphone',
                      onToggle: () => lk.setMic(!lkState.micEnabled),
                    ),
                    _PendingToggle(
                      iconOn: Icons.videocam,
                      iconOff: Icons.videocam_off,
                      on: lkState.cameraEnabled,
                      tooltip: lkState.cameraEnabled
                          ? 'Turn camera off'
                          : 'Turn camera on',
                      onToggle: () => lk.setCamera(!lkState.cameraEnabled),
                    ),
                    _ChromeIconButton(
                      icon: lkState.hideSelf
                          ? Icons.visibility_off
                          : Icons.visibility,
                      active: !lkState.hideSelf,
                      tooltip: lkState.hideSelf
                          ? 'Show my tile'
                          : 'Hide my tile',
                      onTap: () => lk.setHideSelf(!lkState.hideSelf),
                    ),
                    _ChromeIconButton(
                      icon: Icons.chat_bubble_outline,
                      active: chatOpen,
                      tooltip: 'Chat',
                      onTap: onToggleChat,
                    ),
                    if (isHost)
                      _ChromeIconButton(
                        icon: Icons.manage_accounts_outlined,
                        active: false,
                        tooltip: 'Host controls',
                        badge: waiting.isNotEmpty ? waiting.length : null,
                        onTap: onOpenHostControls,
                      ),
                    _ChromeIconButton(
                      icon: Icons.close,
                      active: false,
                      danger: true,
                      tooltip: isHost ? 'End party' : 'Leave',
                      onTap: onLeave,
                    ),
                  ],
                ),
              ],
            ),
            // Host-only join-request notification (stays visible while shown).
            if (isHost && waiting.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _JoinRequests(waiting: waiting),
            ],
            if (lkState.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                lkState.error!,
                style: const TextStyle(color: AppColors.red, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The acrylic container that groups the chrome's icon-buttons.
class _ChromeCluster extends StatelessWidget {
  const _ChromeCluster({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return sc.SurfaceCard(
      surfaceBlur: AppBlur.overlay,
      surfaceOpacity: 0.9,
      borderColor: AppColors.line2,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A single chrome control — a shadcn icon-button (ghost when idle, secondary
/// when active) with a hover [sc.Tooltip], an optional red count badge, and a
/// busy spinner. Public signature is unchanged so [_PendingToggle] still wraps
/// it.
class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.badge,
    this.busy = false,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback? onTap;
  final bool danger;
  final int? badge;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.red
        : (active ? AppColors.text : AppColors.dim);
    final Widget iconWidget = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.dim,
            ),
          )
        : Icon(icon, size: 19, color: color);

    final Widget button = active
        ? sc.IconButton.secondary(
            icon: iconWidget,
            onPressed: busy ? null : onTap,
          )
        : sc.IconButton.ghost(icon: iconWidget, onPressed: busy ? null : onTap);

    Widget content = button;
    if (badge != null && badge! > 0) {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: -3,
            right: -3,
            // The badge is decorative — never let it swallow taps meant for the
            // button beneath it.
            child: IgnorePointer(
              child: sc.DestructiveBadge(
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return sc.Tooltip(
      tooltip: (context) => sc.TooltipContainer(child: Text(tooltip)),
      child: content,
    );
  }
}

/// Mic/camera toggle that shows a pending spinner while the (slow, native)
/// LiveKit publish future is in flight, so the button reads as "working" rather
/// than the UI appearing frozen. Wraps [onToggle] with a local `_busy` guard.
class _PendingToggle extends StatefulWidget {
  const _PendingToggle({
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
  State<_PendingToggle> createState() => _PendingToggleState();
}

class _PendingToggleState extends State<_PendingToggle> {
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
    return _ChromeIconButton(
      icon: widget.on ? widget.iconOn : widget.iconOff,
      active: widget.on,
      tooltip: widget.tooltip,
      busy: _busy,
      onTap: _run,
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

/// Host-only "wants to join" notification card with approve/reject. Fades in on
/// appear ([Reveal]) and sits on an acrylic surface.
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
/// so all send/receive/rate-limit behavior is preserved. The good
/// [AnimatedPositioned] slide is intentionally kept; only the surface is
/// restyled acrylic and the close affordance moved to a shadcn icon-button.
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

/// The host-controls modal (mirrors the web's RoomControls modal): participant
/// roster with transfer-host + kick, collaborative-control toggle, sync-mode
/// picker (watching only), back-to-lobby (host + watching), the shareable room
/// code, and the danger-zone end-party action.
///
/// Kept as a Material [showDialog] shell (per the redesign plan); the CONTENTS
/// are rebuilt on the design system: `sc.Switch`, a shadcn toggle-group, a
/// per-participant `sc.ContextMenu`, `sc.Badge`s, and a toast on copy.
class _HostControlsDialog extends ConsumerWidget {
  const _HostControlsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider);
    if (party == null) return const SizedBox.shrink();
    final notifier = ref.read(partyProvider.notifier);
    final watching = party.stage == 'watching';

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 640),
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
                    'Host controls',
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
                        ),
                    ],
                  ),
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
                              'Let guests play, pause & seek',
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
                  if (watching) ...[
                    const Divider(color: AppColors.line, height: AppSpacing.xl),
                    _sectionLabel('Sync mode'),
                    const SizedBox(height: AppSpacing.sm),
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
                      label: '← Back to lobby',
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
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          party.id,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            color: AppColors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      AppButton(
                        label: 'Copy',
                        variant: AppButtonVariant.secondary,
                        icon: Icons.copy,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: party.id),
                          );
                          if (context.mounted) {
                            _showPartyToast(context, 'Party code copied');
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.line, height: AppSpacing.xl),
                  _sectionLabel('Danger zone', danger: true),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'End party for everyone',
                    variant: AppButtonVariant.danger,
                    expand: true,
                    onPressed: () async {
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
                      if (context.mounted) context.go('/home');
                    },
                  ),
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

/// One participant in the host-controls roster. Non-host rows carry both the
/// inline make-host / kick affordances AND a right-click ([sc.ContextMenu])
/// wired to the same [PartyNotifier] actions.
class _RosterRow extends StatelessWidget {
  const _RosterRow({
    super.key,
    required this.participant,
    required this.notifier,
  });

  final Participant participant;
  final PartyNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final p = participant;
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
        else ...[
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

    if (p.isHost) return row;

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

/// The sync-mode segmented control, rebuilt as a shadcn toggle-group
/// (`sc.ButtonGroup` of `sc.Toggle`s). Public signature is unchanged. Tapping
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
/// the root `ShadcnLayer`), replacing the old `ScaffoldMessenger`/`SnackBar`.
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
