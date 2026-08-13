// Opening a library title into the shared player.
//
// Lifted out of `_SoloPlayer._open()` unchanged in behaviour. It lived inside a
// route's State, which meant the sequence — pre-select tracks, mint a cache-proxy
// URL, prefer an offline copy, play — could only run while that route was
// mounted, and was torn down with it.
//
// Party membership does not change this path. Movies remain local playback;
// joining or leaving a room cannot open, replace, or stop them.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/state.dart';
import 'offline_playback.dart';
import 'player_controller.dart';

/// Result of an open attempt: either the player is ready, or it is not and this
/// is why.
class OpenTitleResult {
  const OpenTitleResult._(this.error, this.usesCacheProxy);

  const OpenTitleResult.ready({required bool usesCacheProxy})
    : this._(null, usesCacheProxy);
  const OpenTitleResult.failed(Object error) : this._(error, false);

  final Object? error;
  final bool usesCacheProxy;

  bool get ok => error == null;
}

/// Open [itemId] into [controller], preferring a locally-downloaded copy.
///
/// [isStale] is polled at each await boundary. A caller that has moved on — the
/// user closed the player, or picked something else — returns true, and the
/// player is left paused rather than starting a title nobody is watching any
/// more. This is the same `_exiting` guard the old route carried, made explicit
/// because the caller is no longer a widget whose `mounted` could stand in for
/// it.
Future<OpenTitleResult> openTitleIntoPlayer(
  WidgetRef ref,
  PlayerController controller, {
  required String itemId,
  String? mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
  required bool Function() isStale,
}) async {
  try {
    final isAuthenticated = ref.read(
      authProvider.select((s) => s.isAuthenticated),
    );

    // Pre-select the audio/subtitle tracks the detail stage picked, so the
    // stream the cache proxy mints delivers them. Best-effort: a failure here
    // must not block playback, so it opens with the server defaults instead.
    if (isAuthenticated &&
        (audioStreamIndex != null || subtitleStreamIndex != null)) {
      try {
        await ref
            .read(apiClientProvider)
            .playbackInfo(
              itemId,
              audioStreamIndex: audioStreamIndex,
              subtitleStreamIndex: subtitleStreamIndex,
            );
      } catch (_) {}
    }

    // Routed through the on-device caching proxy rather than a direct signed
    // URL — it mints and re-mints one itself on demand.
    final streamUrl = isAuthenticated
        ? ref
              .read(mediaCacheProxyProvider)
              .urlFor(itemId, mediaSourceId: mediaSourceId)
        : '';

    await openPreferringOffline(
      ref,
      controller,
      itemId: itemId,
      streamUrl: streamUrl,
      startAt: await _resumePoint(ref, itemId),
      autoplay: false,
    );
    if (isStale()) return const OpenTitleResult.ready(usesCacheProxy: false);
    await controller.play();
    return OpenTitleResult.ready(usesCacheProxy: isAuthenticated);
  } catch (e) {
    return OpenTitleResult.failed(e);
  }
}

/// Where this viewer got to last time, or zero.
///
/// The other half of watch history: `watch_history_provider.dart` writes the
/// position down, and this is what it was written down FOR. Jellyfin decides
/// whether a position is worth resuming from at all — it stores none below its
/// MinResumePct or past its MaxResumePct — so a title that was barely started or
/// all but finished comes back as zero here, which is the intended answer.
///
/// In a party this deliberately returns zero. The room's position is the host's
/// and the sync engine seeks to it; opening at your own resume point first would
/// jump the film to a scene nobody else is on, for the moment it takes sync to
/// pull it back.
///
/// Best-effort in every direction: an unreachable detail fetch means starting
/// from the beginning, which is worse than resuming but far better than failing
/// to open the film.
Future<Duration> _resumePoint(WidgetRef ref, String itemId) async {
  if (ref.read(partyProvider) != null) return Duration.zero;
  try {
    final item = await ref.read(itemDetailProvider(itemId).future);
    final ticks = item.userData?.playbackPositionTicks ?? 0;
    return ticks > 0 ? PlaybackReport.durationOf(ticks) : Duration.zero;
  } catch (_) {
    return Duration.zero;
  }
}
