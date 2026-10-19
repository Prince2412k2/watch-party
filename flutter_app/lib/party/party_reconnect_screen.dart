import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/state.dart';
import '../ui/ui.dart';

/// A quiet connection tag above the player. Playback, focus and pointer events
/// stay with the movie while the party reconnects in the background.
class PartyReconnectScreen extends ConsumerWidget {
  const PartyReconnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(partyConnectionProvider);
    final party = ref.watch(partyProvider);
    if (!connection.lost || party == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              liveRegion: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xB31A1A1A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_outlined,
                        size: 13,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Reconnecting…',
                        style: TextStyle(
                          inherit: false,
                          fontFamily: AppFonts.sans,
                          fontSize: 12,
                          height: 1.3,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
