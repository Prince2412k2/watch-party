import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../state/state.dart';
import '../tokens.dart';
import 'app_button.dart';

/// A slim, persistent "you're in a party" strip shown ABOVE all routed
/// content (wired in `app.dart`'s `MaterialApp.router` builder — above the
/// router's Navigator — so it survives full route pushes like the immersive
/// `/party/:id` screen and `/detail/:id`, not just the shelled tabs).
///
/// This is what makes the party feel app-wide rather than screen-scoped: the
/// party session itself already survives navigation (the party provider is a
/// plain, non-autoDispose `StateNotifierProvider`, so it isn't torn down when
/// its screen unmounts — see `party_provider.dart`); this widget is just the
/// always-visible affordance to get back to it or stop it.
///
/// Hidden when there's no active party, and while the party screen itself is
/// on screen (it already renders full party chrome there).
class GlobalPartyBar extends ConsumerWidget {
  const GlobalPartyBar({super.key, required this.currentLocation});

  /// The router's current path, so the bar can hide itself on `/party*`.
  final String currentLocation;

  static const double height = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider);
    if (party == null) return const SizedBox.shrink();
    if (currentLocation.startsWith(Routes.party)) {
      return const SizedBox.shrink();
    }

    final notifier = ref.read(partyProvider.notifier);
    final isHost = notifier.isHost;
    final watching = party.stage == 'watching';
    final status = watching ? 'Watching together' : 'In the party lobby';

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_outlined, size: 16, color: AppColors.text),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$status · ${party.participants.length} in party · ${party.id}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          AppButton(
            label: 'Return to party',
            variant: AppButtonVariant.secondary,
            onPressed: () => rootNavigatorKey.currentContext?.go(
              '/party/${party.id}',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: isHost ? 'End' : 'Leave',
            variant: AppButtonVariant.danger,
            onPressed: () async {
              if (isHost) {
                await notifier.end();
              } else {
                await notifier.leave();
              }
            },
          ),
        ],
      ),
    );
  }
}
