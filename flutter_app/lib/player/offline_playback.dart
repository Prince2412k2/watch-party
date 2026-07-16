import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/offline_provider.dart';
import '../state/providers.dart';
import 'player_controller.dart';

/// Offline-playback wiring (PLAN §4 E8.3). Opens [itemId] on [controller],
/// preferring the local file from `offlineProvider`'s manifest over
/// [streamUrl] when the title has been fully downloaded — mirrors the web
/// app's `native/useOffline.js`.
///
/// E4.2's `PlayerView` (not yet built at the time this lands) should call
/// this instead of `controller.open(streamUrl, ...)` directly, e.g.:
///
/// ```dart
/// final signed = await api.nativeStreamUrl(item.id);
/// final offline = await openPreferringOffline(
///   ref, controller,
///   itemId: item.id,
///   streamUrl: signed.url,
///   startAt: resumePosition,
///   autoplay: true,
/// );
/// // `offline` is true when playback opened from the local file — use it to
/// // show an "Offline" badge in the player chrome and to skip any
/// // network-only affordances (quality switch, live sync, etc).
/// ```
///
/// E3's detail screen can use [resolveOfflinePlayback] directly (already
/// exported by `offline_provider.dart`) if it needs the resolved URL without
/// opening a controller — e.g. to decide whether "Play" should work with no
/// network.
Future<bool> openPreferringOffline(
  WidgetRef ref,
  PlayerController controller, {
  required String itemId,
  required String streamUrl,
  Duration startAt = Duration.zero,
  bool autoplay = false,
}) async {
  // Same rule as [resolveOfflinePlayback], resolved from a widget's [WidgetRef]
  // (the detail/party playback path is a Consumer, not a provider): once the
  // title is fully offline, playback always opens the on-device cache proxy
  // (which serves it straight from disk, no network) rather than [streamUrl].
  final offline = ref.read(offlineProvider);
  final isOffline = offline.any((r) => r.itemId == itemId);
  final url = isOffline
      ? ref.read(mediaCacheProxyProvider).urlFor(itemId)
      : streamUrl;
  await controller.open(url, startAt: startAt, autoplay: autoplay);
  return isOffline;
}
