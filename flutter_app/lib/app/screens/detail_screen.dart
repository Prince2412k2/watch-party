import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../analog/chrome/analog_button.dart';
import '../../analog/chrome/analog_toast.dart';
import '../../models/models.dart';
import '../../state/offline_provider.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import 'detail_stage.dart';

/// Title-detail screen. For an authenticated user this is the fullscreen
/// cinematic [DetailStage] (movie / show / episode); a logged-out guest gets a
/// minimal offline-only body sourced from the on-device manifest. Watching
/// hands the play target + selected audio/subtitle indices into the solo player
/// route; the mid-movie "Start party" affordance stays wired over playback.
class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;

    // Guest offline-browse (PLAN §E): a logged-out user has no Jellyfin
    // session, so their detail view is sourced entirely from the offline
    // manifest and goes straight to local playback — never touching the network.
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    if (!isAuthenticated) {
      final offline = ref.watch(offlineProvider);
      OfflineRecord? record;
      for (final r in offline) {
        if (r.itemId == itemId) {
          record = r;
          break;
        }
      }
      return Scaffold(
        backgroundColor: wp.bg,
        body: SafeArea(
          child: record == null
              ? EmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Not available offline',
                  message: 'Sign in to browse and download this title.',
                  actionLabel: 'Login',
                  onAction: () => context.go('/login'),
                )
              : _GuestOfflineDetailBody(record: record),
        ),
      );
    }

    return Scaffold(
      backgroundColor: wp.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: DetailStage(
              itemId: itemId,
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/movies'),
              onWatch: (playItem, tracks) => startPlayback(
                context,
                ref,
                itemId: playItem.id,
                audioStreamIndex: tracks.audioStreamIndex,
                subtitleStreamIndex: tracks.subtitleStreamIndex,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A guest's detail view for a downloaded title — no server, no session, just
/// what's already on disk (PLAN §E).
class _GuestOfflineDetailBody extends StatelessWidget {
  const _GuestOfflineDetailBody({required this.record});
  final OfflineRecord record;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final runtime = record.runTimeTicks > 0
        ? '${(record.runTimeTicks / 600000000).round()}m'
        : null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnalogIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/movies'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            record.title,
            style: AppTheme.displaySmall.copyWith(color: wp.text),
          ),
          if (runtime != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(runtime, style: AppTheme.mono.copyWith(color: wp.dim)),
          ],
          const SizedBox(height: AppSpacing.lg),
          // A play triangle is the most legible mark in the medium and does
          // not need the word. Kept at primary weight and given a bigger
          // target than the default: losing the label must not read as
          // demoting the one thing this page exists to do.
          AnalogIconButton(
            icon: Icons.play_arrow,
            tooltip: 'Play',
            tone: AnalogIconButtonTone.primary,
            size: 56,
            iconSize: 28,
            onPressed: () => ProviderScope.containerOf(
              context,
            ).read(nowPlayingProvider.notifier).open(itemId: record.itemId),
          ),
        ],
      ),
    );
  }
}

/// Start playing a library item.
///
/// Opens into the app's own player. This only sets STATE — [PlayerHost],
/// mounted above the router, is what renders it. Nothing navigates, which is
/// the point: the player is no longer a place you go.
///
/// In a party the request goes to the ROOM rather than to this player — see
/// [PartyPlayback]. Solo, it is the same open it always was.
///
/// Public because the show stage launches playback too.
Future<void> startPlayback(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
}) async {
  final outcome = await ref
      .read(partyPlaybackProvider)
      .requestOpen(
        itemId: itemId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
  if (outcome != OpenOutcome.refusedPassenger || !context.mounted) return;
  // Told, not silently ignored: pressing Watch and having nothing happen is
  // indistinguishable from the app being broken.
  showAnalogToast(
    context,
    'Only the host can put a film on in this party',
    tone: AnalogToastTone.info,
  );
}
