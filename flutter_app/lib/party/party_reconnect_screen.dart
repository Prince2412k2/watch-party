import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/state.dart';
import '../ui/ui.dart';
import '../ui/widgets/profile_menu.dart';

/// What a party looks like while its connection is being got back.
///
/// Deliberately the login page's shape — the reel turning on one side, a
/// column on the other — because both are the same moment: the app is doing
/// something on your behalf and there is nothing for you to do but see that it
/// is happening. Where login puts a form, this puts the room you are trying to
/// get back into: the film, and the people waiting in it.
///
/// It does NOT stop the film. Playback keeps running underneath, which is what
/// makes [PartyConnectionNotifier.minimise] worth having — Back sends this to
/// the corner and gives you the picture back, exactly as it does for the
/// player, while the retrying carries on behind it.
class PartyReconnectScreen extends ConsumerWidget {
  const PartyReconnectScreen({super.key});

  /// Below this the reel is dropped and the room centres on its own — the same
  /// threshold, and the same reasoning, as the login page.
  static const double _twoPaneWidth = 880;

  /// The grey the surface sits on. A near-flat gradient, just enough to give
  /// the stage a top and a bottom.
  static const LinearGradient _stage = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B2C30), Color(0xFF161719)],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(partyConnectionProvider);
    final party = ref.watch(partyProvider);
    if (!connection.lost || party == null) return const SizedBox.shrink();

    final notifier = ref.read(partyConnectionProvider.notifier);
    if (connection.minimised) {
      return _MinimisedPill(
        attempt: connection.attempt,
        onTap: notifier.expand,
      );
    }

    return _EscapeMinimises(
      onMinimise: notifier.minimise,
      child: Material(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: _stage),
          child: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final room = _Room(
                        party: party,
                        attempt: connection.attempt,
                      );
                      if (constraints.maxWidth < _twoPaneWidth) {
                        return Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(48),
                            child: room,
                          ),
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(48),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 480,
                                    maxHeight: 480,
                                  ),
                                  child: const AspectRatio(
                                    aspectRatio: 1,
                                    child: ReelAnimation(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 48,
                                ),
                                child: room,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Back, where every other surface puts it. Minimises rather than
              // leaves: the party is not over, it is unreachable, and the two
              // must not be the same gesture.
              Positioned(
                left: BackButtonPlacement.left,
                top: BackButtonPlacement.top,
                child: Tooltip(
                  message: 'Keep trying in the background',
                  child: GlassBackButton(onTap: notifier.minimise),
                ),
              ),

              // The corner, as it looks everywhere else — with one more control
              // beside it. The account menu is mounted here because this
              // surface covers the shell that normally draws it.
              const Positioned(top: 20, right: 28, child: ProfileMenu()),
              Positioned(
                top: 20,
                right: 28 + IconTray.thickness + 12,
                child: _LeaveButton(onLeave: notifier.stopAndLeave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Escape minimises, matching the player. Nothing here closes on Escape: the
/// only way out of a party is the cross, which says what it does.
class _EscapeMinimises extends StatelessWidget {
  const _EscapeMinimises({required this.onMinimise, required this.child});

  final VoidCallback onMinimise;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): onMinimise,
    },
    child: Focus(autofocus: true, child: child),
  );
}

/// The film, the state of the attempt, and who is waiting in the room.
class _Room extends ConsumerWidget {
  const _Room({required this.party, required this.attempt});

  final PartyState party;
  final int attempt;

  static const double _posterWidth = 190;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    final now = ref.watch(nowPlayingProvider);
    // The room's film, falling back to whatever the player has open — a guest
    // who joined mid-film has the second before the first.
    final itemId = party.mediaItemId ?? now.itemId;
    final api = ref.read(apiClientProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (itemId != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            child: SizedBox(
              width: _posterWidth,
              height: _posterWidth * 3 / 2,
              child: AuthedNetworkImage(
                api.imageUrl(itemId),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(color: wp.surface),
                loadingBuilder: (_, _, _) => ColoredBox(color: wp.surface),
              ),
            ),
          ),
        if (now.title case final title?) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.headlineLarge.copyWith(color: wp.text),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Status(attempt: attempt),
        if (party.participants.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          _Faces(participants: party.participants),
        ],
      ],
    );
  }
}

/// "Reconnecting…", and honest about how long it has been trying.
class _Status extends StatelessWidget {
  const _Status({required this.attempt});

  final int attempt;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: wp.dim),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          // The count only appears once a drop has outlived being a blip.
          // Leading with "attempt 1" would make an outage of no consequence
          // look like a fault.
          attempt > 2 ? 'Reconnecting… (attempt $attempt)' : 'Reconnecting…',
          style: AppTheme.dim,
        ),
      ],
    );
  }
}

/// Everyone in the room, host first.
class _Faces extends StatelessWidget {
  const _Faces({required this.participants});

  final List<Participant> participants;

  static const double _face = 44;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final ordered = [
      ...participants.where((p) => p.isHost),
      ...participants.where((p) => !p.isHost),
    ];

    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      children: [
        for (final p in ordered)
          SizedBox(
            width: 76,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: _face + 6,
                  height: _face + 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Uniform width always — a non-uniform border on a circle
                    // throws every frame — so the host's ring is drawn at full
                    // width and merely made transparent for everyone else.
                    border: Border.all(
                      color: p.isHost ? wp.text : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: AvatarView(
                      userId: p.userId,
                      name: p.name,
                      size: _face,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: wp.text),
                ),
                if (p.isHost)
                  Text(
                    'Host',
                    style: AppTheme.mono.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.6,
                      color: wp.dim,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Stop trying, and leave.
///
/// Deliberately the only thing on this surface that ends the party for you —
/// and it is a cross, not a "cancel", because what it cancels is the room, not
/// the reconnecting.
class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onLeave});

  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: 'Stop trying and leave the party',
      child: Material(
        color: wp.bg,
        shape: CircleBorder(side: BorderSide(color: wp.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onLeave(),
          child: SizedBox.square(
            dimension: IconTray.thickness,
            child: Icon(Icons.close, size: 20, color: wp.text),
          ),
        ),
      ),
    );
  }
}

/// What is left on screen once Back has sent the surface away: enough to say
/// the room is still being chased, and a way back to it.
class _MinimisedPill extends StatelessWidget {
  const _MinimisedPill({required this.attempt, required this.onTap});

  final int attempt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Align(
      // Bottom LEFT: the popcorn owns the opposite corner and the nav owns the
      // middle, so this is the one place on the bottom edge that is free.
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, bottom: 24),
        child: Tooltip(
          message: 'Back to the party',
          child: Material(
            color: wp.bg,
            shape: StadiumBorder(side: BorderSide(color: wp.line2)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: wp.dim,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      attempt > 2
                          ? 'Reconnecting… ($attempt)'
                          : 'Reconnecting…',
                      style: TextStyle(fontSize: 13, color: wp.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
