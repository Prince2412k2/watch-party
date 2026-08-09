// Opening a library title into the shared player.
//
// Lifted out of `_SoloPlayer._open()` unchanged in behaviour. It lived inside a
// route's State, which meant the sequence — pre-select tracks, mint a cache-proxy
// URL, prefer an offline copy, play — could only run while that route was
// mounted, and was torn down with it.
//
// The PARTY path does not come through here. `PartyNotifier._syncPlayerToMedia`
// opens party media itself, behind a generation-guarded queue that exists to stop
// two opens racing. Routing party titles through this function as well would be
// exactly the double-open that queue was written to prevent.

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      autoplay: false,
    );
    if (isStale()) {
      await controller.pause();
      return const OpenTitleResult.ready(usesCacheProxy: false);
    }
    await controller.play();
    if (isStale()) await controller.pause();
    return OpenTitleResult.ready(usesCacheProxy: isAuthenticated);
  } catch (e) {
    return OpenTitleResult.failed(e);
  }
}
