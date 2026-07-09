import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../player/player_view.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// The watch-party screen (PLAN §4 E5.2/E5.3): the real implementation,
/// replacing the Phase-0 placeholder of the same name. Composes the shared
/// [PlayerView] (its [PlayerController] instance is also what [SyncEngine]
/// drives — see `partyProvider._postJoinSetup`) with docked, non-overlapping
/// side/bottom panels: cameras + mic/cam controls, chat, host controls, and
/// the participant roster with approve/reject for waiting guests.
///
/// `partyId == null` is the lobby entry point (create or join by id); once a
/// party is live the same widget renders the in-party layout.
class PartyScreen extends ConsumerStatefulWidget {
  const PartyScreen({super.key, this.partyId});
  final String? partyId;

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen> {
  final _joinController = TextEditingController();
  bool _busy = false;
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
    });
    try {
      final status = await ref.read(partyProvider.notifier).join(partyId);
      if (!mounted) return;
      if (status == 'waiting') {
        setState(() => _error = null);
      }
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
      body: SafeArea(
        child: party == null
            ? _PartyLobby(
                joinController: _joinController,
                busy: _busy,
                error: _error,
                onCreate: _create,
                onJoin: () {
                  final id = _joinController.text.trim();
                  if (id.isNotEmpty) context.go('/party/$id');
                },
              )
            : const _PartyRoom(),
      ),
    );
  }
}

/// Pre-party: create a new party or join one by id.
class _PartyLobby extends StatelessWidget {
  const _PartyLobby({
    required this.joinController,
    required this.busy,
    required this.error,
    required this.onCreate,
    required this.onJoin,
  });

  final TextEditingController joinController;
  final bool busy;
  final String? error;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Watch Party',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: AppSpacing.sm),
              const Text('Host a session or join one already running.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.dim, fontSize: 13.5)),
              const SizedBox(height: AppSpacing.xxl),
              AppButton(
                label: 'Start a party',
                variant: AppButtonVariant.primary,
                expand: true,
                busy: busy,
                onPressed: busy ? null : onCreate,
              ),
              const SizedBox(height: AppSpacing.xl),
              const Row(children: [
                Expanded(child: Divider(color: AppColors.line)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text('or', style: TextStyle(color: AppColors.faint, fontSize: 12)),
                ),
                Expanded(child: Divider(color: AppColors.line)),
              ]),
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
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// In-party layout: the player never gets covered — cameras/chat/controls are
/// docked in a fixed-width side panel (row layout) that collapses to a bottom
/// sheet-style column on narrow windows.
class _PartyRoom extends ConsumerWidget {
  const _PartyRoom();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider)!;
    final notifier = ref.read(partyProvider.notifier);
    final controller = ref.watch(playerControllerProvider);
    final canControl = notifier.canControl;
    final isHost = notifier.isHost;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final stage = Expanded(
          flex: narrow ? 0 : 1,
          child: SizedBox(
            height: narrow ? constraints.maxWidth * 9 / 16 : null,
            child: PlayerView(
              controller: controller,
              canControl: canControl,
              title: party.mediaItemId,
              onBack: () => _confirmStopStream(context, ref),
            ),
          ),
        );

        final panel = SizedBox(
          width: narrow ? double.infinity : 340,
          child: _PartyPanel(party: party, isHost: isHost, canControl: canControl),
        );

        if (narrow) {
          return Column(children: [stage, Expanded(child: panel)]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            stage,
            const VerticalDivider(width: 1, color: AppColors.line),
            panel,
          ],
        );
      },
    );
  }

  Future<void> _confirmStopStream(BuildContext context, WidgetRef ref) async {
    final isHost = ref.read(partyProvider.notifier).isHost;
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

/// Docked side panel: tabs for Cameras+Chat, host controls, and the roster.
class _PartyPanel extends StatefulWidget {
  const _PartyPanel({required this.party, required this.isHost, required this.canControl});
  final PartyState party;
  final bool isHost;
  final bool canControl;

  @override
  State<_PartyPanel> createState() => _PartyPanelState();
}

class _PartyPanelState extends State<_PartyPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.surface),
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: AppColors.text,
            unselectedLabelColor: AppColors.faint,
            indicatorColor: AppColors.accent,
            labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Room'),
              Tab(text: 'Chat'),
              Tab(text: 'People'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _RoomTab(party: widget.party, isHost: widget.isHost),
                const ChatPanel(),
                _PeopleTab(party: widget.party, isHost: widget.isHost),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cameras + mic/cam controls + (host-only) collaborative/sync-mode toggles +
/// Stop Movie / Stop Stream actions.
class _RoomTab extends ConsumerWidget {
  const _RoomTab({required this.party, required this.isHost});
  final PartyState party;
  final bool isHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(
          height: 220,
          child: CameraGrid(layout: CameraGridLayout.grid),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: MicCamControls(),
        ),
        const Divider(color: AppColors.line, height: AppSpacing.lg),
        if (isHost) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Host controls',
                    style: TextStyle(color: AppColors.dim, fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeThumbColor: AppColors.accent,
                  title: const Text('Collaborative control',
                      style: TextStyle(color: AppColors.text, fontSize: 13)),
                  value: party.collaborativeControl,
                  onChanged: (v) => ref.read(partyProvider.notifier).setCollaborative(v),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Sync mode', style: TextStyle(color: AppColors.text, fontSize: 13)),
                    ),
                    DropdownButton<String>(
                      value: party.syncMode,
                      dropdownColor: AppColors.surface2,
                      style: const TextStyle(color: AppColors.text, fontSize: 13),
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'hopping', child: Text('Hopping')),
                        DropdownMenuItem(value: 'dragging', child: Text('Dragging')),
                      ],
                      onChanged: (v) {
                        if (v != null) ref.read(partyProvider.notifier).setSyncMode(v);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton(
                label: 'Stop movie (back to lobby)',
                variant: AppButtonVariant.secondary,
                onPressed: party.stage == 'lobby'
                    ? null
                    : () => ref.read(partyProvider.notifier).backToLobby(),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: isHost ? 'Stop stream (end party)' : 'Leave party',
                variant: AppButtonVariant.danger,
                onPressed: () async {
                  final ok = await showConfirm(
                    context,
                    title: isHost ? 'End the party?' : 'Leave the party?',
                    body: isHost ? 'This ends the session for everyone.' : null,
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
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Participant roster + (host-only) waiting-room approve/reject, kick, and
/// transfer-host.
class _PeopleTab extends ConsumerWidget {
  const _PeopleTab({required this.party, required this.isHost});
  final PartyState party;
  final bool isHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(partyWaitingProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (isHost && waiting.isNotEmpty) ...[
          const Text('Waiting to join',
              style: TextStyle(color: AppColors.dim, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          for (final w in waiting)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(w.name, style: const TextStyle(color: AppColors.text, fontSize: 13.5))),
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check_circle_outline, color: AppColors.green, size: 20),
                    onPressed: () => ref.read(partyProvider.notifier).approve(w.userId),
                  ),
                  IconButton(
                    tooltip: 'Reject',
                    icon: const Icon(Icons.cancel_outlined, color: AppColors.red, size: 20),
                    onPressed: () => ref.read(partyProvider.notifier).reject(w.userId),
                  ),
                ],
              ),
            ),
          const Divider(color: AppColors.line, height: AppSpacing.xl),
        ],
        const Text('In the room',
            style: TextStyle(color: AppColors.dim, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        for (final p in party.participants)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                if (p.isHost)
                  const Padding(
                    padding: EdgeInsets.only(right: AppSpacing.xs),
                    child: Icon(Icons.star, color: AppColors.accent, size: 15),
                  ),
                Expanded(child: Text(p.name, style: const TextStyle(color: AppColors.text, fontSize: 13.5))),
                if (isHost && !p.isHost) ...[
                  IconButton(
                    tooltip: 'Make host',
                    icon: const Icon(Icons.swap_horiz, color: AppColors.faint, size: 18),
                    onPressed: () => ref.read(partyProvider.notifier).transferHost(p.userId),
                  ),
                  IconButton(
                    tooltip: 'Kick',
                    icon: const Icon(Icons.person_remove_outlined, color: AppColors.red, size: 18),
                    onPressed: () => ref.read(partyProvider.notifier).kick(p.userId),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
